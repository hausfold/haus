use ansi_term::{ANSIString, ANSIStrings};
use ansi_term::{
    Color::{Fixed, RGB},
    Style,
};
use std::collections::HashMap;
use zellij_tile::prelude::actions::Action;
use zellij_tile::prelude::*;
use zellij_tile_utils::palette_match;

use crate::first_line::{to_char, KeyAction, KeyMode, KeyShortcut};
use crate::second_line::{system_clipboard_error, text_copied_hint};
use crate::{action_key, action_key_group, color_elements, TO_NORMAL};
use crate::{ColoredElements, LinePart};
use unicode_width::UnicodeWidthStr;

/// What `one_line_ui` hands back to the plugin's `render`: the line to print,
/// plus the paging bookkeeping for the overflowing hint window (see `PagingOut`).
pub struct OneLineUi {
    pub line: LinePart,
    pub max_hint_scroll: usize,
    pub hint_scroll: usize,
}

impl OneLineUi {
    // A line with no pageable hints (clipboard toasts, empty right side, …).
    fn plain(line: LinePart) -> Self {
        OneLineUi {
            line,
            max_hint_scroll: 0,
            hint_scroll: 0,
        }
    }
}

/// Result of paginating whichever hint list overflowed this frame. `max` is the
/// largest valid window-start (so `render` can clamp future scroll events);
/// `clamped` is the start actually shown (the caller stores it back, so an
/// over-scroll snaps to the last page and scrolling back up is immediate).
#[derive(Default)]
struct PagingOut {
    max: usize,
    clamped: usize,
}

pub fn one_line_ui(
    help: &ModeInfo,
    tab_info: Option<&TabInfo>,
    mut max_len: usize,
    separator: &str,
    base_mode_is_locked: bool,
    text_copied_to_clipboard_destination: Option<CopyDestination>,
    clipboard_failure: bool,
    hint_scroll: usize,
) -> OneLineUi {
    if let Some(text_copied_to_clipboard_destination) = text_copied_to_clipboard_destination {
        return OneLineUi::plain(text_copied_hint(text_copied_to_clipboard_destination));
    }
    if clipboard_failure {
        return OneLineUi::plain(system_clipboard_error(&help.style.colors));
    }
    let mut line_part_to_render = LinePart::default();
    // At most one hint list is on screen at a time (the mode ribbon in Normal,
    // OR a submode's keybinds), so a single scroll offset + paging result drives
    // whichever one overflowed.
    let mut paging = PagingOut::default();
    let mut append = |line_part: &LinePart, max_len: &mut usize| {
        line_part_to_render.append(line_part);
        *max_len = max_len.saturating_sub(line_part.len);
    };

    render_mode_key_indicators(
        help,
        max_len,
        separator,
        base_mode_is_locked,
        hint_scroll,
        &mut paging,
    )
    .map(|mode_key_indicators| append(&mode_key_indicators, &mut max_len))
    .and_then(|_| match help.mode {
        // Unlocked (Normal): the full mode ribbon on the left already spells
        // out every submode, so the bottom-right `⌘ + <a,f,l,p,t,y,⏎>` launcher
        // block is just clutter here — leave the right side empty. The hints
        // still render in Locked, where the ribbon collapses to the lone
        // unlock key and the reminder earns its space.
        InputMode::Normal => Some(()),
        InputMode::Locked => render_secondary_info(help, tab_info, max_len)
            .map(|secondary_info| append(&secondary_info, &mut max_len)),
        _ => add_keygroup_separator(help, max_len)
            .map(|key_group_separator| append(&key_group_separator, &mut max_len))
            .and_then(|_| keybinds(help, max_len, hint_scroll, &mut paging))
            .map(|keybinds| append(&keybinds, &mut max_len)),
    });
    OneLineUi {
        line: line_part_to_render,
        max_hint_scroll: paging.max,
        hint_scroll: paging.clamped,
    }
}

fn to_base_mode(base_mode: InputMode) -> Action {
    Action::SwitchToMode {
        input_mode: base_mode,
    }
}

fn base_mode_locked_mode_indicators(help: &ModeInfo) -> HashMap<InputMode, Vec<KeyShortcut>> {
    let locked_binds = &help.get_keybinds_for_mode(InputMode::Locked);
    let normal_binds = &help.get_keybinds_for_mode(InputMode::Normal);
    let pane_binds = &help.get_keybinds_for_mode(InputMode::Pane);
    let tab_binds = &help.get_keybinds_for_mode(InputMode::Tab);
    let resize_binds = &help.get_keybinds_for_mode(InputMode::Resize);
    let move_binds = &help.get_keybinds_for_mode(InputMode::Move);
    let scroll_binds = &help.get_keybinds_for_mode(InputMode::Scroll);
    let session_binds = &help.get_keybinds_for_mode(InputMode::Session);
    HashMap::from([
        (
            InputMode::Locked,
            vec![KeyShortcut::new(
                KeyMode::Unselected,
                KeyAction::Unlock,
                to_char(action_key(
                    locked_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Normal,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Pane,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Pane,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Tab,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Tab,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Resize,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Resize,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Move,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Move,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Search,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Scroll,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Session,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Session,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Quit,
                    to_char(action_key(normal_binds, &[Action::Quit])),
                ),
            ],
        ),
        (
            InputMode::Pane,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        pane_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Pane,
                    to_char(action_key(
                        pane_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Tab,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        tab_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Tab,
                    to_char(action_key(
                        tab_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Resize,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        resize_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Resize,
                    to_char(action_key(
                        resize_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Move,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        move_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Move,
                    to_char(action_key(
                        move_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Scroll,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        scroll_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Search,
                    to_char(action_key(
                        scroll_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Session,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        session_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Session,
                    to_char(action_key(
                        session_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
    ])
}

fn base_mode_normal_mode_indicators(help: &ModeInfo) -> HashMap<InputMode, Vec<KeyShortcut>> {
    let locked_binds = &help.get_keybinds_for_mode(InputMode::Locked);
    let normal_binds = &help.get_keybinds_for_mode(InputMode::Normal);
    let pane_binds = &help.get_keybinds_for_mode(InputMode::Pane);
    let tab_binds = &help.get_keybinds_for_mode(InputMode::Tab);
    let resize_binds = &help.get_keybinds_for_mode(InputMode::Resize);
    let move_binds = &help.get_keybinds_for_mode(InputMode::Move);
    let scroll_binds = &help.get_keybinds_for_mode(InputMode::Scroll);
    let session_binds = &help.get_keybinds_for_mode(InputMode::Session);
    HashMap::from([
        (
            InputMode::Locked,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Lock,
                to_char(action_key(
                    locked_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Normal,
            vec![
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Lock,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Pane,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Pane,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Tab,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Tab,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Resize,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Resize,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Move,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Move,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Search,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Scroll,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Session,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Session,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Quit,
                    to_char(action_key(normal_binds, &[Action::Quit])),
                ),
            ],
        ),
        (
            InputMode::Pane,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Pane,
                to_char(action_key(
                    pane_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Tab,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Tab,
                to_char(action_key(
                    tab_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Resize,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Resize,
                to_char(action_key(
                    resize_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Move,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Move,
                to_char(action_key(
                    move_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Scroll,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Search,
                to_char(action_key(
                    scroll_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Session,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Session,
                to_char(action_key(
                    session_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
    ])
}

fn render_mode_key_indicators(
    help: &ModeInfo,
    max_len: usize,
    separator: &str,
    base_mode_is_locked: bool,
    hint_scroll: usize,
    paging: &mut PagingOut,
) -> Option<LinePart> {
    let mut line_part_to_render = LinePart::default();
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let colored_elements = color_elements(help.style.colors, !supports_arrow_fonts);
    let default_keys = if base_mode_is_locked {
        base_mode_locked_mode_indicators(help)
    } else {
        base_mode_normal_mode_indicators(help)
    };
    match common_modifiers_in_all_modes(&default_keys) {
        Some(modifiers) => {
            if let Some(default_keys) = default_keys.get(&help.mode) {
                let keys_without_common_modifiers: Vec<KeyShortcut> = default_keys
                    .iter()
                    .map(|key_shortcut| {
                        let key = key_shortcut
                            .get_key()
                            .map(|k| k.strip_common_modifiers(&modifiers));
                        let mode = key_shortcut.get_mode();
                        let action = key_shortcut.get_action();
                        KeyShortcut::new(mode, action, key)
                    })
                    .collect();
                // Fork: the mode ribbon degrades in ONE step. It shows named
                // pills (` p PANE `, ` t TAB `, …) — the hotkey always keeps its
                // name — and the moment they overflow the pane, it windows them
                // with `‹N` / `N›` count pills (mouse-scroll pages the window),
                // exactly like the submode hints below. There is no keys-only
                // rung and no long-label rung: the ladder is just named → paged.
                //
                // The ` ctrl +` prefix is rendered into a scratch LinePart and
                // only committed together with something to its right, so a thin
                // pane never shows a dangling " ctrl +" with nothing after it.
                // We keep a compact caret form (` ^ +`) as the last-ditch prefix
                // for a pane so narrow the full prefix alone won't fit.
                let mut modifier_prefix = LinePart::default();
                render_common_modifiers(
                    &colored_elements,
                    help,
                    &modifiers,
                    &mut modifier_prefix,
                    separator,
                    false,
                );
                let mut compact_prefix = LinePart::default();
                render_common_modifiers(
                    &colored_elements,
                    help,
                    &modifiers,
                    &mut compact_prefix,
                    separator,
                    true,
                );

                let segments = named_mode_segments(&keys_without_common_modifiers, help);
                // Prefer the full ` ctrl +` prefix; fall back to the caret only
                // when the full prefix would leave no room at all.
                let (prefix, budget) = if modifier_prefix.len < max_len {
                    (&modifier_prefix, max_len - modifier_prefix.len)
                } else {
                    (&compact_prefix, max_len.saturating_sub(compact_prefix.len))
                };
                // paginate_segments renders the plain list when it fits (no
                // indicators) and a windowed `‹N …  N›` slice when it doesn't.
                let paged =
                    paginate_segments(segments, budget, hint_scroll, help.style.colors, paging);
                if paged.len > 0 {
                    line_part_to_render.append(prefix);
                    line_part_to_render.append(&paged);
                }
            }
        },
        None => {
            if let Some(default_keys) = default_keys.get(&help.mode) {
                let full_shortcut_list = full_modes_shortcut_list(&default_keys, help);
                if line_part_to_render.len + full_shortcut_list.len <= max_len {
                    line_part_to_render.append(&full_shortcut_list);
                } else {
                    let shortened_shortcut_list =
                        shortened_modes_shortcut_list(&default_keys, help);
                    if line_part_to_render.len + shortened_shortcut_list.len <= max_len {
                        line_part_to_render.append(&shortened_shortcut_list);
                    }
                }
            }
        },
    }
    if line_part_to_render.len <= max_len {
        Some(line_part_to_render)
    } else {
        None
    }
}

// One named flat pill per mode indicator (` p PANE `, ` t TAB `, the red lock
// pill, …), as a Vec so `paginate_segments` can window it. This is the ONLY form
// the mode ribbon renders now — the hotkey stays named at every width; overflow
// is handled by paging, never by dropping to bare keys.
fn named_mode_segments(
    keys_without_common_modifiers: &Vec<KeyShortcut>,
    help: &ModeInfo,
) -> Vec<LinePart> {
    keys_without_common_modifiers
        .iter()
        .map(|key| {
            let keys = key
                .key
                .as_ref()
                .map(|k| vec![k.clone()])
                .unwrap_or_else(|| vec![]);
            if is_lock(key) {
                add_lock_icon_shortcut(help, keys)
            } else {
                add_shortcut_with_inline_key(help, &key.full_text(), keys, key.is_selected())
            }
        })
        .filter(|s| s.len > 0)
        .collect()
}

fn full_modes_shortcut_list(default_keys: &Vec<KeyShortcut>, help: &ModeInfo) -> LinePart {
    let mut full_shortcut_list = LinePart::default();
    for key in default_keys {
        let keys = key
            .key
            .as_ref()
            .map(|k| vec![k.clone()])
            .unwrap_or_else(|| vec![]);
        if is_lock(key) {
            full_shortcut_list.append(&add_lock_icon_shortcut(help, keys));
        } else {
            full_shortcut_list.append(&add_shortcut(
                help,
                &key.full_text(),
                &keys,
                key.is_selected(),
                Some(3),
            ));
        }
    }
    full_shortcut_list
}

fn shortened_modes_shortcut_list(default_keys: &Vec<KeyShortcut>, help: &ModeInfo) -> LinePart {
    let mut shortened_shortcut_list = LinePart::default();
    for key in default_keys {
        let keys = key
            .key
            .as_ref()
            .map(|k| vec![k.clone()])
            .unwrap_or_else(|| vec![]);
        if is_lock(key) {
            shortened_shortcut_list.append(&add_lock_icon_shortcut(help, keys));
        } else {
            shortened_shortcut_list.append(&add_shortcut(
                help,
                &key.short_text(),
                &keys,
                key.is_selected(),
                Some(3),
            ));
        }
    }
    shortened_shortcut_list
}

fn common_modifiers_in_all_modes(
    key_shortcuts: &HashMap<InputMode, Vec<KeyShortcut>>,
) -> Option<Vec<KeyModifier>> {
    let Some(mut common_modifiers) = key_shortcuts.iter().next().and_then(|k| {
        k.1.iter()
            .next()
            .and_then(|k| k.get_key().map(|k| k.key_modifiers.clone()))
    }) else {
        return None;
    };
    for (_mode, key_shortcuts) in key_shortcuts {
        if key_shortcuts.is_empty() {
            return None;
        }
        let Some(mut common_modifiers_for_mode) = key_shortcuts
            .iter()
            .next()
            .unwrap()
            .get_key()
            .map(|k| k.key_modifiers.clone())
        else {
            return None;
        };
        for key in key_shortcuts {
            let Some(key) = key.get_key() else {
                return None;
            };
            common_modifiers_for_mode = common_modifiers_for_mode
                .intersection(&key.key_modifiers)
                .cloned()
                .collect();
        }
        common_modifiers = common_modifiers
            .intersection(&common_modifiers_for_mode)
            .cloned()
            .collect();
    }
    if common_modifiers.is_empty() {
        return None;
    }
    Some(common_modifiers.into_iter().collect())
}

// Fork: how a modifier renders anywhere on the bar. Super is always the Mac
// glyph ⌘ — this is a macOS rice, the keycaps say ⌘, and it costs 1 column
// where the word "Super" costs 5 (which is also why the bottom-right block now
// keeps its prefix on panes too thin for the word). The rest stay lowercase
// ("ctrl +") — house style, and it reads calmer than upstream's "Ctrl". When
// `compact` is set (a shrink step chosen by the caller once the list won't
// otherwise fit), Ctrl collapses to the classic caret "^", buying back three
// columns to keep more of the key list on screen before any key gets dropped.
fn modifier_label(m: &KeyModifier, compact: bool) -> String {
    match m {
        KeyModifier::Super => return "⌘".to_string(),
        KeyModifier::Ctrl if compact => return "^".to_string(),
        _ => {},
    }
    m.to_string().to_lowercase()
}

// Fork: how a bare key renders inside the hint block. Zellij spells Enter
// "ENTER" (five columns, shouting); the keycap glyph ⏎ says the same thing in
// one and sits level with the single letters it's listed beside.
fn key_label(key: &KeyWithModifier) -> String {
    let bare = match key.bare_key {
        BareKey::Enter => "⏎".to_string(),
        other => other.to_string(),
    };
    if key.key_modifiers.is_empty() {
        bare
    } else {
        let modifiers = key
            .key_modifiers
            .iter()
            .map(|m| modifier_label(m, false))
            .collect::<Vec<_>>()
            .join(" ");
        format!("{} {}", modifiers, bare)
    }
}

fn render_common_modifiers(
    palette: &ColoredElements,
    mode_info: &ModeInfo,
    common_modifiers: &Vec<KeyModifier>,
    line_part_to_render: &mut LinePart,
    separator: &str,
    compact: bool,
) {
    let joined = common_modifiers
        .iter()
        .map(|m| modifier_label(m, compact))
        .collect::<Vec<_>>()
        .join("-");
    let prefix_text = if mode_info.capabilities.arrow_fonts {
        // Add extra space in simplified ui
        format!(" {} + ", joined)
    } else {
        format!(" {} +", joined)
    };

    // Fork: no powerline cap after the modifier prefix — a single line-bg space
    // divides ` ctrl +` from the first flat pill. `separator` is left unused here
    // (the two-row classic bar still threads it).
    //
    // Paint the prefix with `superkey_prefix` (fg on the bar's line background),
    // NOT an opaque `Text` — an opaque Text renders on the plugin pane's own
    // default background, a shade off the bar colour, which reintroduces the
    // seam the flat pills paint out. `superkey_prefix`/`superkey_suffix_separator`
    // both sit on `text_unselected.background`, so prefix + separator + pills all
    // share the one bar background.
    let _ = separator;
    let prefix = palette.superkey_prefix.paint(prefix_text.as_str());
    let suffix_separator = palette.superkey_suffix_separator.paint(" ");
    line_part_to_render.part = format!(
        "{}{}{}",
        line_part_to_render.part, prefix, suffix_separator
    );
    line_part_to_render.len += prefix_text.chars().count() + 1;
}

fn render_secondary_info(
    help: &ModeInfo,
    tab_info: Option<&TabInfo>,
    max_len: usize,
) -> Option<LinePart> {
    let mut secondary_info = LinePart::default();
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let colored_elements = color_elements(help.style.colors, !supports_arrow_fonts);
    let secondary_keybinds = secondary_keybinds(&help, tab_info, max_len);
    secondary_info.append(&secondary_keybinds);
    let remaining_space = max_len.saturating_sub(secondary_info.len).saturating_sub(1); // 1 for the end padding of the line
    let mut padding = String::new();
    let mut padding_len = 0;
    for _ in 0..remaining_space {
        padding.push_str(&ANSIStrings(&[colored_elements.superkey_prefix.paint(" ")]).to_string());
        padding_len += 1;
    }
    secondary_info.part = format!("{}{}", padding, secondary_info.part);
    secondary_info.len += padding_len;
    if secondary_info.len <= max_len {
        Some(secondary_info)
    } else {
        None
    }
}

fn should_show_focus_and_resize_shortcuts(tab_info: Option<&TabInfo>) -> bool {
    let Some(tab_info) = tab_info else {
        return false;
    };
    let are_floating_panes_visible = tab_info.are_floating_panes_visible;
    if are_floating_panes_visible {
        tab_info.selectable_floating_panes_count > 1
    } else {
        tab_info.selectable_tiled_panes_count > 1
    }
}

fn secondary_keybinds(help: &ModeInfo, _tab_info: Option<&TabInfo>, max_len: usize) -> LinePart {
    let binds = &help.get_mode_keybinds();
    // Fork: the bottom-right quick hints are condensed to a single flat block —
    // ` ⌘ + <a,f,l,p,t,y,⏎> ` — the launchers plus find and fullscreen
    // (a = a new agent worktree, p = new pane, t = new tab, y = yazi peek,
    // l = pounce links, f = find, ⏎ = fullscreen toggle): keys only, no
    // word-labels and no powerline ribbons.
    // What each key does lives in the web docs / cheatsheet (nebelhaus.com), not
    // spelled out on the bar. Keys are still resolved from the live binds (via
    // run_bind_key / action_key), so a rebind re-letters the block; only the
    // labels and the Floating/Focus/Resize hints were dropped versus upstream.
    // The `a` launcher is "start an agent", not "start Claude": hearth renders
    // that bind from nebelhaus.agents.default, so it is `claude --worktree` on a
    // Claude machine and `holt new` on a Codex/Opencode one. Try each spelling
    // and take the first that resolves — matching only the Claude one used to
    // blank the whole hint block's first key the moment the default changed.
    let agent_key = [("claude", Some("--worktree")), ("holt", Some("new"))]
        .into_iter()
        .map(|(cmd, arg)| run_bind_key(binds, cmd, arg))
        .find(|keys| !keys.is_empty())
        .unwrap_or_default();
    let peek_key = run_bind_key(binds, "peek.sh", None);
    let links_key = run_bind_key(binds, "pounce", Some("cmd:links"));
    // Find: bound twice (Super f = this pane, Super Shift f = every pane), so
    // run_bind_key's own "unshifted wins" rule already lands the hint on `f`.
    let find_key = run_bind_key(binds, "find.sh", None);

    // Fullscreen: the single-action ToggleFocusFullscreen bind (Super Enter —
    // it moved off Super f when ⌘F went back to meaning find). Resolved from
    // the live binds, so this hint re-letters itself and needed no change.
    // action_key demands an exact-length action match, so only a bind whose
    // whole action list is this one element matches — a multi-action bind that
    // merely starts with ToggleFocusFullscreen wouldn't.
    let fullscreen_key = action_key(binds, &[Action::ToggleFocusFullscreen])
        .first()
        .map(|k| vec![k.clone()])
        .unwrap_or_default();

    let new_pane_action_key = action_key(
        binds,
        &[Action::NewPane {
            direction: None,
            pane_name: None,
            start_suppressed: false,
        }],
    );
    let pane_key = new_pane_action_key
        .iter()
        .find(|k| k.is_key_with_alt_modifier(BareKey::Char('n')))
        .or_else(|| new_pane_action_key.iter().next())
        .map(|k| vec![k.clone()])
        .unwrap_or_default();

    // New Tab: Super-t carries the NewTab action (Super-Shift-t is a `Run` —
    // new-tab-here.sh — not a NewTab, so it never matches here). Prefer the
    // un-shifted key so the hint reads `t`, never `Shift t` (the old bug: both
    // t-binds matched NewTab and the shifted one won the `.next()` race).
    let new_tab_action_key = action_key(
        binds,
        &[Action::NewTab {
            tiled_layout: None,
            floating_layouts: vec![],
            swap_tiled_layouts: None,
            swap_floating_layouts: None,
            tab_name: None,
            should_change_focus_to_new_tab: true,
            cwd: None,
            initial_panes: None,
            first_pane_unblock_condition: None,
        }],
    );
    let tab_key = new_tab_action_key
        .iter()
        .find(|k| k.bare_key == BareKey::Char('t') && !k.key_modifiers.contains(&KeyModifier::Shift))
        .or_else(|| new_tab_action_key.iter().find(|k| k.bare_key == BareKey::Char('t')))
        .or_else(|| new_tab_action_key.iter().next())
        .map(|k| vec![k.clone()])
        .unwrap_or_default();

    // Collection order is by feature; the block is *displayed* alphabetically
    // (sorted below) — the letters are what the eye scans, so a stable a,f,l,…
    // beats an order only the source file knows.
    let ordered: Vec<Vec<KeyWithModifier>> = vec![
        agent_key,
        pane_key,
        tab_key,
        peek_key,
        links_key,
        find_key,
        fullscreen_key,
    ];
    let common_modifiers = get_common_modifiers(ordered.iter().flatten().collect());

    // One display char per launcher, common modifier stripped so only `a`/`p`/…
    // shows inside the bracket group.
    let mut key_chars: Vec<String> = ordered
        .iter()
        .filter_map(|k| {
            k.first().map(|k| {
                if common_modifiers.is_empty() {
                    key_label(k)
                } else {
                    key_label(&k.strip_common_modifiers(&common_modifiers))
                }
            })
        })
        .collect();

    if key_chars.is_empty() {
        return LinePart::default();
    }
    // Alphabetical, case-insensitively, on what actually shows: a rebind that
    // re-letters a hint slots it where the reader would look for it instead of
    // wherever its feature happens to sit in the list above. Glyph keys (⏎) are
    // above ASCII in codepoint order, so they land at the end on their own.
    key_chars.sort_by_key(|k| k.to_lowercase());
    let joined = key_chars.join(",");

    // ` <mods> + <a,f,l,p,t,y,⏎> ` as one opaque, non-ribbon block; the bracket
    // group is painted in the emphasis colour (index 0). On a pane too thin for
    // the modifier prefix, fall back to a bare ` <a,f,l,p,t,y,⏎> `.
    let render_block = |with_modifier: bool| -> LinePart {
        let prefix = if with_modifier && !common_modifiers.is_empty() {
            format!(
                " {} + ",
                common_modifiers
                    .iter()
                    .map(|m| modifier_label(m, false))
                    .collect::<Vec<_>>()
                    .join("-")
            )
        } else {
            " ".to_string()
        };
        let bracket = format!("<{}>", joined);
        let full = format!("{}{} ", prefix, bracket);
        let start = prefix.width();
        let end = start + bracket.width();
        LinePart {
            part: serialize_text(&Text::new(&full).color_range(0, start..end).opaque()),
            len: full.width(),
        }
    };

    let full_block = render_block(true);
    if full_block.len <= max_len {
        full_block
    } else {
        render_block(false)
    }
}
fn text_as_line_part_with_emphasis(text: String, emphases_index: usize) -> LinePart {
    let part = serialize_text(&Text::new(&text).color_range(emphases_index, ..).opaque());
    LinePart {
        part,
        len: text.width(),
    }
}

// ── Flat text hints ──────────────────────────────────────────────────────────
// Fork: the bottom bar dropped zellij's powerline ribbons (`serialize_ribbon`,
// which the host caps with pointy arrow glyphs) AND, later, the *distinct*
// background pills that replaced them — no boxes, no dividers. Each hint is now
// just accented text on the bar's own background: ` key label`, then a plain
// space, so two hints abut as ` a X  b Y ` (the 2-space gap alone separates
// them). Since there's no longer a box to encode state, colour does it: the key
// letter is a constant yellow accent and the *label* colour carries the mode's
// state — light grey inactive, green active, red locked. Widths are unchanged
// from the old pill form, so the overflow-paging math still holds.
//
// "On the bar's own background" is literal: every cell is painted *explicitly*
// on `text_unselected.background` (the colour `render`'s `fill_bg` clears the
// rest of the row with). It is NOT left transparent — a transparent cell falls
// through to the plugin pane's default background, which the theme sets a shade
// off the bar colour, and that gap between the hint run and the filled remainder
// is the seam. Painting the bar bg under every hint makes the whole row uniform.

// (key accent fg, label fg) for a hint on the bar background. The key is always
// the yellow accent; the label colour encodes state — light grey for an inactive
// mode, green for the active one.
fn pill_colors(palette: Styling, selected: bool) -> (PaletteColor, PaletteColor) {
    let key_fg = palette.text_unselected.emphasis_2; // yellow key accent
    let label_fg = if selected {
        palette.ribbon_selected.background // green = active mode
    } else {
        palette.text_unselected.base // light grey = inactive
    };
    (key_fg, label_fg)
}

// ` key label ` — accented key, state-coloured label, no box and no divider, on
// the bar's own line background. Either text side may be empty: key-only yields
// ` key `, label-only yields ` label `. The trailing space is a plain pad so
// abutting hints are separated by whitespace alone; widths match the old pill
// form exactly.
//
// `bg` MUST be the bar's line background (`text_unselected.background`, the same
// colour `render`'s `fill_bg` clears the rest of the row with). Every cell —
// including the trailing pad — is painted on it *explicitly*: an unset (fg-only)
// cell would fall through to the plugin pane's own default background, which the
// nebelung theme sets a shade off the bar colour — that mismatch is exactly the
// seam this paints out, so the whole row reads as one flat background.
fn flat_pill(
    key: &str,
    label: &str,
    key_fg: PaletteColor,
    label_fg: PaletteColor,
    bg: PaletteColor,
) -> LinePart {
    let key_fg = palette_match!(key_fg);
    let label_fg = palette_match!(label_fg);
    let bg = palette_match!(bg);
    let (mut bits, len): (Vec<ANSIString>, usize) = match (key.is_empty(), label.is_empty()) {
        (false, false) => (
            vec![
                Style::new().fg(key_fg).on(bg).bold().paint(format!(" {}", key)),
                Style::new().fg(label_fg).on(bg).bold().paint(format!(" {}", label)),
            ],
            key.width() + label.width() + 3,
        ),
        (false, true) => (
            vec![Style::new().fg(key_fg).on(bg).bold().paint(format!(" {}", key))],
            key.width() + 2,
        ),
        _ => (
            vec![Style::new().fg(label_fg).on(bg).bold().paint(format!(" {}", label))],
            label.width() + 2,
        ),
    };
    // trailing pad — a plain space on the bar background, no recoloured "seam".
    bits.push(Style::new().on(bg).paint(" "));
    LinePart {
        part: ANSIStrings(&bits).to_string(),
        len,
    }
}

// Compact string for a key group: known clusters (arrows, hjkl, …) run together,
// everything else joins with `|`; a shared modifier is surfaced once up front.
fn key_group_string(keys: &[KeyWithModifier]) -> String {
    if keys.is_empty() {
        return String::new();
    }
    let common = get_common_modifiers(keys.iter().collect());
    let joined_raw = keys
        .iter()
        .map(|k| k.strip_common_modifiers(&common).to_string())
        .collect::<Vec<_>>()
        .join("");
    let sep = match joined_raw.as_str() {
        "HJKL" | "hjkl" | "←↓↑→" | "←→" | "↓↑" | "[]" | "+-" => "",
        _ => "|",
    };
    let bare = keys
        .iter()
        .map(|k| k.strip_common_modifiers(&common).to_string())
        .collect::<Vec<_>>()
        .join(sep);
    if common.is_empty() {
        bare
    } else {
        let mods = common
            .iter()
            .map(|m| m.to_string())
            .collect::<Vec<_>>()
            .join("-");
        format!("{} {}", mods, bare)
    }
}

// ── Overflow paging ──────────────────────────────────────────────────────────
// Fork: when a hint list won't fit even as bare keys, window it instead of
// dropping to a dead "...". Mirrors the top tab-bar's `← +N` / `+N →` overflow
// pills, generalised to any Vec<LinePart>: `‹N` for N hidden left, `N›` for N
// hidden right, and mouse-scroll pages the window (offset threaded in from
// State). Records the clamp ceiling + shown start into `paging` so `render` can
// bound future scroll events and snap an over-scroll to the last page.

fn more_pill(text: String, palette: Styling) -> LinePart {
    let fg = palette_match!(palette.text_unselected.emphasis_0); // peach accent
    let bg = palette_match!(palette.text_unselected.background); // line bg
    let s = format!(" {} ", text);
    LinePart {
        part: Style::new().fg(fg).on(bg).bold().paint(s.clone()).to_string(),
        len: s.width(),
    }
}

fn paginate_segments(
    segments: Vec<LinePart>,
    max_len: usize,
    scroll: usize,
    palette: Styling,
    paging: &mut PagingOut,
) -> LinePart {
    let total: usize = segments.iter().map(|s| s.len).sum();
    if segments.is_empty() || total <= max_len {
        // Everything fits (or there's nothing) — no window, no indicators.
        let mut lp = LinePart::default();
        for s in &segments {
            lp.append(s);
        }
        paging.max = 0;
        paging.clamped = 0;
        return lp;
    }

    // Fixed budget reserved for an edge indicator while choosing the window, so a
    // `‹N` / `N›` pill is never clipped by the very overflow it marks. 5 cols
    // covers ` ‹NN ` (two digits), ample for a hint list.
    const IND_RESERVE: usize = 5;

    // Largest window-start whose suffix still fits (leaving room for a left
    // indicator). Scrolling past it just re-shows the last page, so it's the
    // clamp ceiling handed back to the caller.
    let mut max_start = segments.len().saturating_sub(1);
    let mut suffix = 0usize;
    for i in (0..segments.len()).rev() {
        let left_ind = if i > 0 { IND_RESERVE } else { 0 };
        if suffix + segments[i].len + left_ind <= max_len {
            suffix += segments[i].len;
            max_start = i;
        } else {
            break;
        }
    }
    let start = scroll.min(max_start);

    let mut window = LinePart::default();
    let mut used = if start > 0 { IND_RESERVE } else { 0 };
    let mut end = start;
    while end < segments.len() {
        let seg = &segments[end];
        let right_reserve = if end + 1 < segments.len() { IND_RESERVE } else { 0 };
        // Always show at least one segment (end > start guard) even if snug.
        if end > start && used + seg.len + right_reserve > max_len {
            break;
        }
        used += seg.len;
        window.append(seg);
        end += 1;
    }

    let hidden_right = segments.len() - end;
    let mut out = LinePart::default();
    if start > 0 {
        out.append(&more_pill(format!("‹{}", start), palette));
    }
    out.append(&window);
    if hidden_right > 0 {
        out.append(&more_pill(format!("{}›", hidden_right), palette));
    }
    paging.max = max_start;
    paging.clamped = start;
    out
}

// One named flat pill per submode hint, using the SHORT label (` n New `,
// ` f Floating `, …) — never the long "Toggle Fullscreen"-style label, which is
// gone. Returned as a Vec so `paginate_segments` can window it.
fn short_named_segments(help: &ModeInfo) -> Vec<LinePart> {
    get_keys_and_hints(help)
        .into_iter()
        .filter_map(|(_long, short, keys)| {
            if keys.is_empty() {
                return None;
            }
            let pill = add_shortcut(help, &short, &keys.to_vec(), false, None);
            (pill.len > 0).then_some(pill)
        })
        .collect()
}

// Fork: the submode hint list degrades in ONE step, matching the mode ribbon:
// short-labelled named pills, and the moment they overflow, `paginate_segments`
// windows them with `‹N` / `N›` counts (mouse-scroll pages). No long-label rung
// (never used except at absurd widths) and no keys-only rung (the hotkey stays
// named): the ladder is just short → paged.
fn keybinds(
    help: &ModeInfo,
    max_width: usize,
    hint_scroll: usize,
    paging: &mut PagingOut,
) -> Option<LinePart> {
    let segments = short_named_segments(help);
    Some(paginate_segments(
        segments,
        max_width,
        hint_scroll,
        help.style.colors,
        paging,
    ))
}

fn add_shortcut(
    help: &ModeInfo,
    text: &str,
    keys: &Vec<KeyWithModifier>,
    selected: bool,
    _key_color_index: Option<usize>,
) -> LinePart {
    if keys.is_empty() {
        return LinePart::default();
    }
    let (key_fg, label_fg) = pill_colors(help.style.colors, selected);
    flat_pill(
        &key_group_string(keys),
        text,
        key_fg,
        label_fg,
        help.style.colors.text_unselected.background,
    )
}

fn add_shortcut_with_inline_key(
    help: &ModeInfo,
    text: &str,
    key: Vec<KeyWithModifier>,
    is_selected: bool,
) -> LinePart {
    if key.is_empty() {
        return LinePart::default();
    }
    let (key_fg, label_fg) = pill_colors(help.style.colors, is_selected);
    flat_pill(
        &key_group_string(&key),
        text,
        key_fg,
        label_fg,
        help.style.colors.text_unselected.background,
    )
}

// Fork: find the key bound to a `Run` command, so the bottom-right hints can
// surface our custom launchers (claude --worktree, yazi peek) next to New Pane
// / New Tab. Matches on the command basename (+ an optional required arg) so a
// rebind (e.g. Super a / Super y) still resolves.
//
// Gotcha: a `bind { Run "…"; }` does NOT reach a plugin as `Action::Run`.
// zellij rewrites a Run keybind into the pane it opens before handing the
// keybinds to plugins — a tiled `Run` arrives as `NewTiledPane { command:
// Some(RunCommandAction) }`, a floating one as `NewFloatingPane { … }`. The
// RunCommandAction (command + args) rides along inside, so we match those
// variants (plus a bare `Run`, for safety) on the carried command.
fn run_bind_key(
    binds: &[(KeyWithModifier, Vec<Action>)],
    file_name: &str,
    required_arg: Option<&str>,
) -> Vec<KeyWithModifier> {
    // Collect EVERY bind running this command, then prefer the un-shifted one —
    // the same rule the NewTab hint needs, for the same reason: `claude
    // --worktree` is bound twice (Super a splits a new pane, Super Shift a
    // replaces the focused one), and taking the first match would let bind order
    // decide whether the bar reads `c` or `Shift c`. The hint block is the
    // un-shifted launcher row, so Shift only wins if nothing else matched.
    let matches: Vec<&KeyWithModifier> = binds
        .iter()
        .filter(|(_, actions)| {
            actions.iter().any(|a| {
                let cmd = match a {
                    Action::Run { command, .. } => Some(command),
                    Action::NewTiledPane { command, .. }
                    | Action::NewFloatingPane { command, .. }
                    | Action::NewInPlacePane { command, .. } => command.as_ref(),
                    _ => None,
                };
                cmd.is_some_and(|c| {
                    c.command.file_name().and_then(|n| n.to_str()) == Some(file_name)
                        && required_arg.map_or(true, |ra| c.args.iter().any(|arg| arg == ra))
                })
            })
        })
        .map(|(key, _)| key)
        .collect();

    matches
        .iter()
        .find(|k| !k.key_modifiers.contains(&KeyModifier::Shift))
        .or_else(|| matches.first())
        .map(|k| vec![(*k).clone()])
        .unwrap_or_default()
}

// Fork: the (un)lock mode indicator is a padlock GLYPH, not the word
// `LOCK`/`UNLOCK` — closed & red when input is Locked, open & green when it's
// unlocked — so the *current* state reads at a glance instead of asking you to
// parse a verb. The colour is all in the foreground (no background fill; see
// `flat_pill`): red is the nebelung theme's `exit_code_error.base` (#ed8fa9),
// green is `ribbon_selected.background` (the shared "active mode" green). The
// `Ctrl-g` toggle key still rides in front of it (` g  ` / ` g  `), keeping the
// pill discoverable, and keeps the yellow accent (`text_unselected.emphasis_2`).
const LOCK_GLYPH_CLOSED: &str = "\u{f023}"; // nf-fa-lock
const LOCK_GLYPH_OPEN: &str = "\u{f09c}"; // nf-fa-unlock

fn add_lock_icon_shortcut(help: &ModeInfo, key: Vec<KeyWithModifier>) -> LinePart {
    let palette = help.style.colors;
    let locked = matches!(help.mode, InputMode::Locked);
    let glyph = if locked {
        LOCK_GLYPH_CLOSED
    } else {
        LOCK_GLYPH_OPEN
    };
    let icon_fg = if locked {
        palette.exit_code_error.base // red = locked
    } else {
        palette.ribbon_selected.background // green = unlocked
    };
    let key_fg = palette.text_unselected.emphasis_2; // yellow key accent
    let bg = palette.text_unselected.background;
    if key.is_empty() {
        // No toggle key resolved — render the bare glyph (glyph-only pill).
        return flat_pill("", glyph, icon_fg, icon_fg, bg);
    }
    flat_pill(&key_group_string(&key), glyph, key_fg, icon_fg, bg)
}

// Fork: is this mode indicator the (un)lock pill (in any state)? It renders as
// the state-coloured padlock glyph above; everything else stays on the shared
// green/grey ribbon.
fn is_lock(key: &KeyShortcut) -> bool {
    matches!(key.get_action(), KeyAction::Lock | KeyAction::Unlock)
}

// Fork: divides the selected-mode hint from the submode hint list. With flat
// text there's no powerline arrow to bridge — an amber tag carries the transient
// RENAMING/SEARCHING state (when there is one), followed by a single space so
// the green mode word and the grey hints don't visually run together.
fn add_keygroup_separator(help: &ModeInfo, max_len: usize) -> Option<LinePart> {
    let palette = help.style.colors;
    let mode_help_text = match help.mode {
        InputMode::RenamePane => Some("RENAMING PANE"),
        InputMode::RenameTab => Some("RENAMING TAB"),
        InputMode::EnterSearch => Some("ENTERING SEARCH TERM"),
        InputMode::Search => Some("SEARCHING"),
        _ => None,
    };

    let bar_bg = palette_match!(palette.text_unselected.background);
    let mut ret = LinePart::default();
    if let Some(mode_help_text) = mode_help_text {
        // amber state banner — accented text on the bar background, stands out as
        // a transient state without a box.
        ret.append(&flat_pill(
            "",
            mode_help_text,
            palette.text_unselected.emphasis_0,
            palette.text_unselected.emphasis_0,
            palette.text_unselected.background,
        ));
    }
    // one space (on the bar background) dividing the mode word from the hint list
    ret.part = format!("{}{}", ret.part, Style::new().on(bar_bg).paint(" "));
    ret.len += 1;

    if ret.len <= max_len {
        Some(ret)
    } else {
        None
    }
}

#[rustfmt::skip]
fn get_keys_and_hints(mi: &ModeInfo) -> Vec<(String, String, Vec<KeyWithModifier>)> {
    use Action as A;
    use InputMode as IM;
    use Direction as Dir;
    use actions::SearchDirection as SDir;
    use actions::SearchOption as SOpt;

    let mut old_keymap = mi.get_mode_keybinds();
    let s = |string: &str| string.to_string();

    // Find a keybinding to get back to "Normal" input mode. In this case we prefer '\n' over other
    // choices. Do it here before we dedupe the keymap below!
    let base_mode = mi.base_mode;
    let to_basemode_keys = base_mode.map(|b| action_key(&old_keymap, &[to_base_mode(b)])).unwrap_or_else(|| action_key(&old_keymap, &[TO_NORMAL]));
    let to_basemode_key = if to_basemode_keys.contains(&KeyWithModifier::new(BareKey::Enter)) {
        vec![KeyWithModifier::new(BareKey::Enter)]
    } else {
        // Yield `vec![key]` if `to_normal_keys` has at least one key, or an empty vec otherwise.
        to_basemode_keys.into_iter().take(1).collect()
    };

    // Sort and deduplicate the keybindings first. We sort after the `Key`s, and deduplicate by
    // their `Action` vectors. An unstable sort is fine here because if the user maps anything to
    // the same key again, anything will happen...
    old_keymap.sort_unstable_by(|(keya, _), (keyb, _)| keya.partial_cmp(keyb).unwrap());

    let mut known_actions: Vec<Vec<Action>> = vec![];
    let mut km = vec![];
    for (key, acvec) in old_keymap {
        if known_actions.contains(&acvec) {
            // This action is known already
            continue;
        } else {
            known_actions.push(acvec.to_vec());
            km.push((key, acvec));
        }
    }

    if mi.mode == IM::Pane { vec![
        (s("New"), s("New"), single_action_key(&km, &[A::NewPane{direction: None, pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Change Focus"), s("Move"),
            action_key_group(&km, &[&[A::MoveFocus{direction: Dir::Left}], &[A::MoveFocus{direction: Dir::Down}],
                &[A::MoveFocus{direction: Dir::Up}], &[A::MoveFocus{direction: Dir::Right}]])),
        (s("Close"), s("Close"), single_action_key(&km, &[A::CloseFocus, TO_NORMAL])),
        (s("Rename"), s("Rename"),
            single_action_key(&km, &[A::SwitchToMode{input_mode: IM::RenamePane}, A::PaneNameInput{input: vec![0]}])),
        (s("Toggle Fullscreen"), s("Fullscreen"), single_action_key(&km, &[A::ToggleFocusFullscreen, TO_NORMAL])),
        (s("Toggle Floating"), s("Floating"),
            single_action_key(&km, &[A::ToggleFloatingPanes, TO_NORMAL])),
        (s("Toggle Embed"), s("Embed"), single_action_key(&km, &[A::TogglePaneEmbedOrFloating, TO_NORMAL])),
        (s("Split Right"), s("Right"), single_action_key(&km, &[A::NewPane{direction: Some(Direction::Right), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Split Down"), s("Down"), single_action_key(&km, &[A::NewPane{direction: Some(Direction::Down), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Stack"), s("Stack"), single_action_key(&km, &[A::NewStackedPane{command: None, pane_name: None, near_current_pane: false, tab_id: None}, TO_NORMAL])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Tab {
        // With the default bindings, "Move focus" for tabs is tricky: It binds all the arrow keys
        // to moving tabs focus (left/up go left, right/down go right). Since we sort the keys
        // above and then dedpulicate based on the actions, we will end up with LeftArrow for
        // "left" and DownArrow for "right". What we really expect is to see LeftArrow and
        // RightArrow.
        // FIXME: So for lack of a better idea we just check this case manually here.
        let old_keymap = mi.get_mode_keybinds();
        let focus_keys_full: Vec<KeyWithModifier> = action_key_group(&old_keymap,
            &[&[A::GoToPreviousTab], &[A::GoToNextTab]]);
        let focus_keys = if focus_keys_full.contains(&KeyWithModifier::new(BareKey::Left))
            && focus_keys_full.contains(&KeyWithModifier::new(BareKey::Right)) {
            vec![KeyWithModifier::new(BareKey::Left), KeyWithModifier::new(BareKey::Right)]
        } else {
            action_key_group(&km, &[&[A::GoToPreviousTab], &[A::GoToNextTab]])
        };

        vec![
        (s("New"), s("New"), single_action_key(&km, &[A::NewTab{
            tiled_layout: None,
            floating_layouts: vec![],
            swap_tiled_layouts: None,
            swap_floating_layouts: None,
            tab_name: None,
            should_change_focus_to_new_tab: true,
            cwd: None,
            initial_panes: None,
            first_pane_unblock_condition: None,
        }, TO_NORMAL])),
        (s("Change focus"), s("Move"), focus_keys),
        (s("Close"), s("Close"), single_action_key(&km, &[A::CloseTab, TO_NORMAL])),
        (s("Rename"), s("Rename"),
            single_action_key(&km, &[A::SwitchToMode{input_mode: IM::RenameTab}, A::TabNameInput{input: vec![0]}])),
        (s("Sync"), s("Sync"), single_action_key(&km, &[A::ToggleActiveSyncTab, TO_NORMAL])),
        (s("Break pane to new tab"), s("Break out"), single_action_key(&km, &[A::BreakPane, TO_NORMAL])),
        (s("Break pane left/right"), s("Break"), action_key_group(&km, &[
            &[Action::BreakPaneLeft, TO_NORMAL],
            &[Action::BreakPaneRight, TO_NORMAL],
        ])),
        (s("Toggle"), s("Toggle"), single_action_key(&km, &[A::ToggleTab])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Resize { vec![
        (s("Increase/Decrease size"), s("Increase/Decrease"),
            action_key_group(&km, &[
                &[A::Resize{resize: Resize::Increase, direction: None}],
                &[A::Resize{resize: Resize::Decrease, direction: None}]
            ])),
        (s("Increase to"), s("Increase"), action_key_group(&km, &[
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Left)}],
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Down)}],
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Up)}],
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Right)}]
            ])),
        (s("Decrease from"), s("Decrease"), action_key_group(&km, &[
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Left)}],
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Down)}],
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Up)}],
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Right)}]
            ])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Move { vec![
        (s("Switch Location"), s("Move"), action_key_group(&km, &[
            &[Action::MovePane{direction: Some(Dir::Left)}], &[Action::MovePane{direction: Some(Dir::Down)}],
            &[Action::MovePane{direction: Some(Dir::Up)}], &[Action::MovePane{direction: Some(Dir::Right)}]])),
        (s("When done"), s("Back"), to_basemode_key),
    ]} else if mi.mode == IM::Scroll { vec![
        (s("Enter search term"), s("Search"),
            action_key(&km, &[A::SwitchToMode{input_mode: IM::EnterSearch}, A::SearchInput{input: vec![0]}])),
        (s("Scroll"), s("Scroll"),
            action_key_group(&km, &[&[Action::ScrollDown], &[Action::ScrollUp]])),
        (s("Scroll page"), s("Scroll"),
            action_key_group(&km, &[&[Action::PageScrollDown], &[Action::PageScrollUp]])),
        (s("Scroll half page"), s("Scroll"),
            action_key_group(&km, &[&[Action::HalfPageScrollDown], &[Action::HalfPageScrollUp]])),
        (s("Edit scrollback in default editor"), s("Edit"),
            single_action_key(&km, &[Action::EditScrollback { ansi: false }, TO_NORMAL])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::EnterSearch { vec![
        (s("When done"), s("Done"), action_key(&km, &[A::SwitchToMode{input_mode: IM::Search}])),
        (s("Cancel"), s("Cancel"),
            action_key(&km, &[A::SearchInput{input: vec![27]}, A::SwitchToMode{input_mode: IM::Scroll}])),
    ]} else if mi.mode == IM::Search { vec![
        (s("Enter Search term"), s("Search"),
            action_key(&km, &[A::SwitchToMode{input_mode: IM::EnterSearch}, A::SearchInput{input: vec![0]}])),
        (s("Scroll"), s("Scroll"),
            action_key_group(&km, &[&[Action::ScrollDown], &[Action::ScrollUp]])),
        (s("Scroll page"), s("Scroll"),
            action_key_group(&km, &[&[Action::PageScrollDown], &[Action::PageScrollUp]])),
        (s("Scroll half page"), s("Scroll"),
            action_key_group(&km, &[&[Action::HalfPageScrollDown], &[Action::HalfPageScrollUp]])),
        (s("Search down"), s("Down"), action_key(&km, &[A::Search{direction: SDir::Down}])),
        (s("Search up"), s("Up"), action_key(&km, &[A::Search{direction: SDir::Up}])),
        (s("Case sensitive"), s("Case"),
            action_key(&km, &[A::SearchToggleOption{option: SOpt::CaseSensitivity}])),
        (s("Wrap"), s("Wrap"),
            action_key(&km, &[A::SearchToggleOption{option: SOpt::Wrap}])),
        (s("Whole words"), s("Whole"),
            action_key(&km, &[A::SearchToggleOption{option: SOpt::WholeWord}])),
    ]} else if mi.mode == IM::Session { vec![
        (s("Detach"), s("Detach"), action_key(&km, &[Action::Detach])),
        (s("Session Manager"), s("Manager"), session_manager_key(&km)),
        (s("Share"), s("Share"), share_key(&km)),
        (s("Configure"), s("Config"), configuration_key(&km)),
        (s("Layout Manager"), s("Layouts"), layout_manager_key(&km)),
        (s("Plugin Manager"), s("Plugins"), plugin_manager_key(&km)),
        (s("About"), s("About"), about_key(&km)),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Tmux { vec![
        (s("Move focus"), s("Move"), action_key_group(&km, &[
            &[A::MoveFocus{direction: Dir::Left}], &[A::MoveFocus{direction: Dir::Down}],
            &[A::MoveFocus{direction: Dir::Up}], &[A::MoveFocus{direction: Dir::Right}]])),
        (s("Split down"), s("Down"), action_key(&km, &[A::NewPane{direction: Some(Dir::Down), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Split right"), s("Right"), action_key(&km, &[A::NewPane{direction: Some(Dir::Right), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Fullscreen"), s("Fullscreen"), action_key(&km, &[A::ToggleFocusFullscreen, TO_NORMAL])),
        (s("New tab"), s("New"), action_key(&km, &[A::NewTab{
            tiled_layout: None,
            floating_layouts: vec![],
            swap_tiled_layouts: None,
            swap_floating_layouts: None,
            tab_name: None,
            should_change_focus_to_new_tab: true,
            cwd: None,
            initial_panes: None,
            first_pane_unblock_condition: None,
        }, TO_NORMAL])),
        (s("Rename tab"), s("Rename"),
            action_key(&km, &[A::SwitchToMode{input_mode: IM::RenameTab}, A::TabNameInput{input: vec![0]}])),
        (s("Previous Tab"), s("Previous"), action_key(&km, &[A::GoToPreviousTab, TO_NORMAL])),
        (s("Next Tab"), s("Next"), action_key(&km, &[A::GoToNextTab, TO_NORMAL])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if matches!(mi.mode, IM::RenamePane | IM::RenameTab) { vec![
        (s("When done"), s("Done"), to_basemode_key),
    ]} else { vec![] }
}

fn single_action_key(
    keymap: &[(KeyWithModifier, Vec<Action>)],
    action: &[Action],
) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        if acvec.iter().next() == action.iter().next() {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn session_manager_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("session-manager"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn share_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("zellij:share"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn plugin_manager_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("plugin-manager"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn layout_manager_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("zellij:layout-manager"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn about_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("zellij:about"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn configuration_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("configuration"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn get_common_modifiers(mut keyvec: Vec<&KeyWithModifier>) -> Vec<KeyModifier> {
    if keyvec.is_empty() {
        return vec![];
    }
    let mut common_modifiers = keyvec.pop().unwrap().key_modifiers.clone();
    for key in keyvec {
        common_modifiers = common_modifiers
            .intersection(&key.key_modifiers)
            .cloned()
            .collect();
    }
    common_modifiers.into_iter().collect()
}
