// tab-history — a background zellij plugin that gives Ctrl+Tab / Ctrl+Shift+Tab
// browser-style history instead of sequential cycling.
//
// Why this exists: zellij's GoToNextTab / GoToPreviousTab march through tabs by
// position with no memory, so flipping between "the two tabs I'm actually
// working in" means counting past everything wedged between them. This plugin
// keeps a most-recently-used (MRU) order of tabs and walks THAT:
//
//   Ctrl+Tab        → back    (toward older / previously-focused tabs)
//   Ctrl+Shift+Tab  → forward  (back toward the tab you came from)
//
// The gesture model mirrors a browser's back/forward, with a settle timeout
// standing in for "you let go of the button" (a terminal keybind can't observe
// key release):
//
//   - The first press freezes the current MRU order into a snapshot and starts
//     walking it. While the gesture is live, further presses walk that frozen
//     snapshot back and forth — landing on a tab does NOT re-sort it to the
//     top, so you can pass over a tab and keep going, or reverse, without the
//     list shifting under you.
//   - COMMIT_WINDOW seconds after the LAST press the gesture settles: the tab
//     you landed on becomes the new MRU front (the "current history node"), and
//     the next press starts a fresh gesture from there.
//
// Wiring (see ../config.kdl): loaded as a background plugin via `load_plugins`
// so it records focus history from session start; Ctrl+Tab / Ctrl+Shift+Tab are
// bound to `MessagePlugin`, which delivers "back" / "forward" to `pipe()`. Its
// ReadApplicationState + ChangeApplicationState grants are pre-seeded into
// zellij's permission cache by terminal — a background plugin has no pane to show
// the interactive grant prompt in (same story as link-handler).

use std::collections::BTreeMap;
use zellij_tile::prelude::*;

/// Seconds of stillness after the last press before the landed tab commits to
/// the front of the MRU order. Short enough to feel like a held-modifier
/// alt-tab, long enough to chain a few presses without it settling underfoot.
const COMMIT_WINDOW: f64 = 1.5;

#[derive(Default)]
struct State {
    /// Set once zellij confirms our permission grant; until then we ignore
    /// keypresses (go_to_tab would be a no-op anyway).
    granted: bool,
    /// Tab positions in most-recently-used order; front (index 0) = the tab
    /// focused most recently. Tracked by `TabInfo.position` — zellij exposes no
    /// stable per-tab id, so a tab CLOSE (which renumbers later positions) can
    /// briefly point history at the wrong tab; it self-heals on the next manual
    /// focus. Closing/reordering tabs mid-session is rare enough that this is an
    /// accepted trade for not maintaining our own id map.
    mru: Vec<usize>,
    /// Position of the currently-active tab, from the latest TabUpdate.
    active: Option<usize>,
    /// Number of tabs currently open.
    tab_count: usize,
    /// The live back/forward gesture, if one is in progress.
    gesture: Option<Gesture>,
    /// Outstanding settle timers. Each press schedules one set_timeout(COMMIT_
    /// WINDOW); equal-duration timers fire in the order scheduled, so the count
    /// returns to 0 exactly COMMIT_WINDOW after the LAST press — that firing is
    /// the settle. Counting timers this way sidesteps needing a wall clock
    /// inside the wasm sandbox.
    pending_timers: usize,
}

/// A frozen snapshot of the MRU order plus a cursor into it. Walking the
/// snapshot (not the live `mru`) is what lets a gesture go back and forth
/// without the order shifting as we switch tabs.
struct Gesture {
    order: Vec<usize>,
    cursor: usize,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        // Reading tab state and switching tabs are both permissioned for
        // non-builtin plugins; terminal pre-seeds these into the cache so the
        // grant is silent (no pane to prompt in).
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[
            EventType::PermissionRequestResult,
            EventType::TabUpdate,
            EventType::Timer,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                self.granted = true;
            },
            Event::TabUpdate(tabs) => {
                self.handle_tab_update(&tabs);
            },
            Event::Timer(_) => {
                self.handle_timer();
            },
            _ => {},
        }
        false // background-only: never renders
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        match pipe_message.name.as_str() {
            "back" => self.cycle(1),
            "forward" => self.cycle(-1),
            _ => {},
        }
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // Background-only plugin. Never rendered. Intentionally empty.
    }
}

impl State {
    fn handle_tab_update(&mut self, tabs: &[TabInfo]) {
        self.tab_count = tabs.len();
        self.active = tabs.iter().find(|t| t.active).map(|t| t.position);

        // Reconcile membership against the live set of positions: drop any that
        // no longer exist, append any new ones as least-recent.
        self.mru.retain(|p| *p < self.tab_count);
        for p in 0..self.tab_count {
            if !self.mru.contains(&p) {
                self.mru.push(p);
            }
        }

        // Outside a gesture, ordinary focus changes (a click, a GoToTab, a new
        // tab) refresh recency. DURING a gesture we deliberately leave the order
        // alone — our own go_to_tab calls must not re-sort the frozen snapshot.
        if self.gesture.is_none() {
            if let Some(active) = self.active {
                move_to_front(&mut self.mru, active);
            }
        }
    }

    fn handle_timer(&mut self) {
        if self.pending_timers > 0 {
            self.pending_timers -= 1;
        }
        if self.pending_timers == 0 {
            // Settle: the tab we landed on becomes the new MRU front, and the
            // next press starts a fresh gesture.
            self.gesture = None;
            if let Some(active) = self.active {
                move_to_front(&mut self.mru, active);
            }
        }
    }

    /// Walk the history by `dir` steps (+1 = back / older, -1 = forward /
    /// newer), wrapping at the ends like a classic alt-tab ring.
    fn cycle(&mut self, dir: isize) {
        if !self.granted || self.tab_count <= 1 {
            return;
        }

        // Start a gesture from the live MRU if none is running, cursor parked on
        // the current tab (front, normally). Built here rather than with
        // get_or_insert_with to keep `self.mru` / `self.active` borrows clean.
        if self.gesture.is_none() {
            let order = self.mru.clone();
            let cursor = self
                .active
                .and_then(|a| order.iter().position(|p| *p == a))
                .unwrap_or(0);
            self.gesture = Some(Gesture { order, cursor });
        }
        let gesture = self.gesture.as_mut().unwrap();

        let n = gesture.order.len();
        gesture.cursor = (gesture.cursor as isize + dir).rem_euclid(n as isize) as usize;
        let target = gesture.order[gesture.cursor];

        // Arm (another) settle timer for this press; see `pending_timers`.
        self.pending_timers += 1;
        set_timeout(COMMIT_WINDOW);

        // TabInfo.position is 0-based; switch_tab_to is 1-based (the built-in
        // tab-bar plugin switches with `position + 1` the same way).
        switch_tab_to((target + 1) as u32);
    }
}

/// Move `value` to the front of `v` (index 0), preserving the order of the
/// rest. No-op if it isn't present.
fn move_to_front(v: &mut Vec<usize>, value: usize) {
    if let Some(idx) = v.iter().position(|p| *p == value) {
        let item = v.remove(idx);
        v.insert(0, item);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn move_to_front_reorders() {
        let mut v = vec![0, 1, 2, 3];
        move_to_front(&mut v, 2);
        assert_eq!(v, vec![2, 0, 1, 3]);
    }

    #[test]
    fn move_to_front_absent_is_noop() {
        let mut v = vec![0, 1, 2];
        move_to_front(&mut v, 9);
        assert_eq!(v, vec![0, 1, 2]);
    }

    #[test]
    fn move_to_front_already_front() {
        let mut v = vec![3, 1, 2];
        move_to_front(&mut v, 3);
        assert_eq!(v, vec![3, 1, 2]);
    }
}
