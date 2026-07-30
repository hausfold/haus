mod line;
mod tab;

use std::cmp::{max, min};
use std::collections::BTreeMap;
use std::convert::TryInto;

use tab::get_tab_to_focus;
use zellij_tile::prelude::*;

use crate::line::tab_line;
use crate::tab::tab_style;

// Fork of zellij's built-in tab-bar (v0.44.3, default-plugins/tab-bar) — see
// line.rs. Themed to nebelung + a peach username pill on the left and a
// Ctrl+Tab reminder / swap-layout ribbon on the right, so it replaces the old
// third-party zjstatus top bar while keeping upstream's active-anchored tab
// scroll viewport (the thing zjstatus lacked).
//
// Fork addition: an agent-status paw beside the name of any tab holding a
// `claude --worktree` pane (see AgentState + the pipe handler below), so eight
// tabs of agents no longer have to be cycled to find the one that's blocked.

#[derive(Debug, Default)]
pub struct LinePart {
    part: String,
    len: usize,
    tab_index: Option<usize>,
}

impl LinePart {
    pub fn append(&mut self, to_append: &LinePart) {
        self.part.push_str(&to_append.part);
        self.len += to_append.len;
    }
}

/// One agent pane's self-reported state, piped in by sill's agents-hook.sh from
/// Claude Code's own hooks (UserPromptSubmit → working, Notification → waiting,
/// Stop → idle). Authoritative: the agent tells us, we never screen-scrape.
///
/// The `Ord` derive is load-bearing — the variants are declared in URGENCY
/// order, so a tab holding several agents can just `max()` them and show the one
/// that most wants attention. Keep waiting last.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum AgentState {
    /// Turn finished, nothing blocked (Claude's Stop hook).
    Idle,
    /// Mid-turn (Claude's UserPromptSubmit hook).
    Working,
    /// Blocked on you — a permission prompt or an input nudge (Notification).
    Waiting,
}

impl AgentState {
    /// The wire vocabulary is sill's, verbatim: the same working/waiting/idle
    /// words agents-hook.sh already writes into its state files. One vocabulary
    /// across both consumers, so there's nothing to translate.
    fn from_wire(s: &str) -> Option<Self> {
        match s {
            "working" => Some(AgentState::Working),
            "waiting" => Some(AgentState::Waiting),
            "idle" => Some(AgentState::Idle),
            _ => None,
        }
    }
}

/// The `zellij pipe --name` agents-hook.sh broadcasts on. Deliberately
/// agent-neutral: anything that can run a shell hook inside a zellij pane
/// (codex, an aider wrapper, a bare script) can report on this pipe without the
/// plugin changing. Payload is one line of space-separated `key=value`:
///
///     state=working|waiting|idle|remove  pane=<zellij pane id>  agent=<name>
///
/// Unknown keys are ignored so the protocol can grow without a wasm rebuild;
/// `agent=` is parsed by nobody yet and reserved for exactly that.
static AGENT_STATUS_PIPE: &str = "nebelhaus-agent-status";

#[derive(Default, Debug)]
struct State {
    tabs: Vec<TabInfo>,
    active_tab_idx: usize,
    mode_info: ModeInfo,
    tab_line: Vec<LinePart>,
    hide_swap_layout_indication: bool,
    username: String,
    cached_keybinds: KeybindsVec,
    /// Agent state per TERMINAL pane id, as reported over AGENT_STATUS_PIPE.
    agents: BTreeMap<u32, AgentState>,
    /// Terminal pane id → tab position, from PaneUpdate. The pipe carries a pane
    /// id (all a hook can know about itself); only zellij knows which tab that
    /// pane currently lives in — and panes get moved between tabs.
    pane_tab: BTreeMap<u32, usize>,
    /// The rendered product of the two maps above: tab position → the most
    /// urgent agent state in it. Cached so a noisy PaneUpdate that doesn't move
    /// a badge doesn't repaint the bar.
    tab_badges: BTreeMap<usize, AgentState>,
}

static ARROW_SEPARATOR: &str = "";

register_plugin!(State);

impl State {
    /// Recompute tab → most-urgent-agent from (agent states × pane→tab), and
    /// report whether what the bar draws actually changed.
    ///
    /// The return value is the point: PaneUpdate fires on every pane title
    /// change, and an agent pane retitles constantly, so without this the bar
    /// would repaint on a stream of events that move no badge.
    fn refresh_tab_badges(&mut self) -> bool {
        let mut badges: BTreeMap<usize, AgentState> = BTreeMap::new();
        for (pane_id, state) in &self.agents {
            if let Some(tab_position) = self.pane_tab.get(pane_id) {
                let slot = badges.entry(*tab_position).or_insert(*state);
                *slot = (*slot).max(*state);
            }
        }
        let changed = badges != self.tab_badges;
        self.tab_badges = badges;
        changed
    }
}

impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        self.hide_swap_layout_indication = configuration
            .get("hide_swap_layout_indication")
            .map(|s| s == "true")
            .unwrap_or(false);
        // The left-hand pill. Passed in from the layout (nix substitutes the
        // real login name); empty = no pill, and the tabs start at the edge.
        self.username = configuration
            .get("username")
            .cloned()
            .unwrap_or_default();
        set_selectable(false);
        // Upstream tab-bar is is_builtin() and skips the permission check; loaded
        // as a file: plugin we are NOT builtin, so the events we render from
        // (TabUpdate/ModeUpdate, gated on ReadApplicationState) get denied — and
        // switch_tab_to on a mouse click needs ChangeApplicationState — unless we
        // ask. hearth seeds both grants into zellij's permission cache, so this
        // auto-grants silently instead of prompting in the bar's own pane. See
        // the sibling status-bar fork, which does the same for ReadApplicationState.
        //
        // ReadCliPipes is what lets `zellij pipe` reach pipe() at all — without
        // it the agent paws simply never appear. It must be in hearth's seed list
        // too: zellij only auto-grants when EVERY requested permission is cached,
        // so an unseeded addition here doesn't degrade to "no paws", it leaves the
        // WHOLE bar event-less behind a prompt no one can answer.
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::ReadCliPipes,
        ]);
        subscribe(&[
            EventType::TabUpdate,
            EventType::ModeUpdate,
            EventType::Mouse,
            EventType::InitialKeybinds,
            // Only for the agent paws: a pipe tells us a PANE's state, and this
            // is the only thing that says which tab that pane is in.
            EventType::PaneUpdate,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        let mut should_render = false;
        match event {
            Event::InitialKeybinds(keybinds) => {
                self.cached_keybinds = keybinds;
                if !self.cached_keybinds.is_empty() {
                    self.mode_info.keybinds = self.cached_keybinds.clone();
                }
                should_render = true;
            },
            Event::ModeUpdate(mut mode_info) => {
                if mode_info.keybinds.is_empty() && !self.cached_keybinds.is_empty() {
                    mode_info.keybinds = self.cached_keybinds.clone();
                } else if !mode_info.keybinds.is_empty() {
                    self.cached_keybinds = mode_info.keybinds.clone();
                }
                if self.mode_info != mode_info {
                    should_render = true;
                }
                self.mode_info = mode_info;
            },
            Event::TabUpdate(tabs) => {
                if let Some(active_tab_index) = tabs.iter().position(|t| t.active) {
                    // tabs are indexed starting from 1 so we need to add 1
                    let active_tab_idx = active_tab_index + 1;

                    if self.active_tab_idx != active_tab_idx || self.tabs != tabs {
                        should_render = true;
                    }
                    self.active_tab_idx = active_tab_idx;
                    self.tabs = tabs;
                } else {
                    eprintln!("Could not find active tab.");
                }
            },
            Event::PaneUpdate(manifest) => {
                self.pane_tab.clear();
                for (tab_position, panes) in &manifest.panes {
                    for pane in panes {
                        // Plugin panes share the id space with terminals but can
                        // never host an agent, so they'd only alias real ids.
                        if !pane.is_plugin {
                            self.pane_tab.insert(pane.id, *tab_position);
                        }
                    }
                }
                // Garbage-collect badges for panes that no longer exist. This —
                // not the `remove` pipe — is what actually cleans up in practice:
                // killing a pane outright (how an agent worktree pane usually
                // dies) never gives Claude's SessionEnd hook a chance to fire.
                let live_panes = &self.pane_tab;
                self.agents.retain(|pane_id, _| live_panes.contains_key(pane_id));
                if self.refresh_tab_badges() {
                    should_render = true;
                }
            },
            Event::Mouse(me) => match me {
                Mouse::LeftClick(_, col) => {
                    let tab_to_focus = get_tab_to_focus(&self.tab_line, self.active_tab_idx, col);
                    if let Some(idx) = tab_to_focus {
                        switch_tab_to(idx.try_into().unwrap());
                    }
                },
                Mouse::ScrollUp(_) => {
                    switch_tab_to(min(self.active_tab_idx + 1, self.tabs.len()) as u32);
                },
                Mouse::ScrollDown(_) => {
                    switch_tab_to(max(self.active_tab_idx.saturating_sub(1), 1) as u32);
                },
                _ => {},
            },
            _ => {
                eprintln!("Got unrecognized event: {:?}", event);
            },
        }
        if self.tabs.is_empty() {
            // no need to render if we have no tabs, this can sometimes happen on startup before we
            // get the tab update and then we definitely don't want to render
            should_render = false;
        }
        should_render
    }

    /// The agent-status pipe (see AGENT_STATUS_PIPE for the protocol).
    ///
    /// `zellij pipe` without `--plugin` broadcasts to every running plugin, which
    /// is exactly what agents-hook.sh does — it has no business knowing our wasm
    /// path. So the name check below is the whole addressing scheme, and every
    /// other plugin's default `pipe()` ignores us right back.
    ///
    /// Note we never read sill's /tmp/nebelhaus-agents/*.state files: a plugin is
    /// WASI-sandboxed to its own /host, /data and /cache. Pushing beats polling
    /// here anyway — a tab bar has no business running a timer.
    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        if pipe_message.name != AGENT_STATUS_PIPE {
            return false;
        }
        let payload = match pipe_message.payload.as_deref() {
            Some(payload) => payload,
            // A None payload means the pipe ended, not a state change.
            None => return false,
        };
        let mut wire_state: Option<&str> = None;
        let mut pane_id: Option<u32> = None;
        for field in payload.split_whitespace() {
            match field.split_once('=') {
                Some(("state", value)) => wire_state = Some(value),
                Some(("pane", value)) => pane_id = value.parse().ok(),
                // Unknown keys (`agent=`, whatever comes later) are ignored on
                // purpose — see AGENT_STATUS_PIPE.
                _ => {},
            }
        }
        let (Some(wire_state), Some(pane_id)) = (wire_state, pane_id) else {
            return false;
        };
        if wire_state == "remove" {
            self.agents.remove(&pane_id);
        } else if let Some(state) = AgentState::from_wire(wire_state) {
            self.agents.insert(pane_id, state);
        } else {
            return false;
        }
        // A pipe can beat the first PaneUpdate, in which case this pane isn't
        // placed in a tab yet and nothing renders — the next PaneUpdate resolves
        // it, and one arrives whenever anything about a pane changes.
        self.refresh_tab_badges()
    }

    fn render(&mut self, _rows: usize, cols: usize) {
        if self.tabs.is_empty() {
            return;
        }
        let mut all_tabs: Vec<LinePart> = vec![];
        let mut active_tab_index = 0;
        let mut is_alternate_tab = false;
        for t in &mut self.tabs {
            let mut tabname = t.name.clone();
            if t.active && self.mode_info.mode == InputMode::RenameTab {
                if tabname.is_empty() {
                    tabname = String::from("Enter name...");
                }
                active_tab_index = t.position;
            } else if t.active {
                active_tab_index = t.position;
            }
            let tab = tab_style(
                tabname,
                t,
                is_alternate_tab,
                self.mode_info.style.colors,
                self.mode_info.capabilities,
                self.tab_badges.get(&t.position).copied(),
            );
            is_alternate_tab = !is_alternate_tab;
            all_tabs.push(tab);
        }

        let background = self.mode_info.style.colors.text_unselected.background;

        // The layout pill hugs the right edge, so the reserved final column (see
        // below) must be erased in the pill's colour, not the bar background, to
        // read flush. tab_line reports which colour that last column wants.
        let edge_fill;
        (self.tab_line, edge_fill) = tab_line(
            &self.username,
            all_tabs,
            active_tab_index,
            cols.saturating_sub(1),
            self.mode_info.style.colors,
            self.mode_info.capabilities,
            self.tabs.iter().find(|t| t.active),
            &self.mode_info,
            self.hide_swap_layout_indication,
            &background,
        );

        let output = self
            .tab_line
            .iter()
            .fold(String::new(), |output, part| output + &part.part);

        match edge_fill {
            PaletteColor::Rgb((r, g, b)) => {
                print!("{}\u{1b}[48;2;{};{};{}m\u{1b}[0K", output, r, g, b);
            },
            PaletteColor::EightBit(color) => {
                print!("{}\u{1b}[48;5;{}m\u{1b}[0K", output, color);
            },
        }
    }
}
