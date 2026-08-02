use crate::{line::tab_separator, AgentBadge, AgentState, LinePart};
use ansi_term::{ANSIString, ANSIStrings};
use unicode_width::UnicodeWidthStr;
use zellij_tile::prelude::*;
use zellij_tile_utils::style;

// The badge is a FILLED rectangle — the state colour is the background and the
// number of agent panes is punched out of it in near-black — not a coloured
// glyph on the tab's own fill. A one-cell glyph tinted peach is a few lit pixels
// you have to go looking for; a solid block is the thing you catch from across the
// room, which is the entire job of this badge.
//
// Same construction as line.rs's layout_indicator_pill (the yellow GRID
// rectangle): hand-painted flat block, no powerline caps, so the two right-hand
// signals in this bar read as one family.

/// Blend `color` toward `toward` (0.0 = unchanged, 1.0 = fully `toward`).
///
/// Only RGB blends: an EightBit entry is an index into a table this plugin can't
/// see, so a 256-colour terminal keeps the full-strength colour rather than being
/// handed a wrong one. Muting is a nicety; every caller below stays correct
/// without it.
fn blend(color: PaletteColor, toward: PaletteColor, t: f32) -> PaletteColor {
    match (color, toward) {
        (PaletteColor::Rgb((r, g, b)), PaletteColor::Rgb((tr, tg, tb))) => {
            let mix = |a: u8, b: u8| (a as f32 + (b as f32 - a as f32) * t).round() as u8;
            PaletteColor::Rgb((mix(r, tr), mix(g, tg), mix(b, tb)))
        },
        _ => color,
    }
}

fn cursors<'a>(
    focused_clients: &'a [ClientId],
    multiplayer_colors: MultiplayerColors,
) -> (Vec<ANSIString<'a>>, usize) {
    // cursor section, text length
    let mut len = 0;
    let mut cursors = vec![];
    for client_id in focused_clients.iter() {
        if let Some(color) = client_id_to_colors(*client_id, multiplayer_colors) {
            cursors.push(style!(color.1, color.0).paint(" "));
            len += 1;
        }
    }
    (cursors, len)
}

pub fn render_tab(
    text: String,
    tab: &TabInfo,
    is_alternate_tab: bool,
    palette: Styling,
    separator: &str,
    badge: Option<AgentBadge>,
) -> LinePart {
    let focused_clients = tab.other_focused_clients.as_slice();
    let separator_width = separator.width();

    let alternate_tab_color = if is_alternate_tab {
        palette.ribbon_unselected.emphasis_1
    } else {
        palette.ribbon_unselected.background
    };
    let background_color = if tab.active {
        palette.ribbon_selected.background
    } else if is_alternate_tab {
        alternate_tab_color
    } else {
        palette.ribbon_unselected.background
    };
    let foreground_color = if tab.is_flashing_bell {
        if tab.active {
            palette.ribbon_selected.emphasis_3
        } else {
            palette.ribbon_unselected.emphasis_3
        }
    } else if tab.active {
        palette.ribbon_selected.base
    } else {
        palette.ribbon_unselected.base
    };

    let separator_fill_color = palette.text_unselected.background;
    let left_separator = style!(separator_fill_color, background_color).paint(separator);
    let mut tab_text_len = text.width() + (separator_width * 2) + 2; // +2 for padding
    let tab_styled_text = style!(foreground_color, background_color)
        .bold()
        .paint(format!(" {} ", text));

    // Fork: the agent-status badge — a chip in the most urgent agent's state
    // colour, carrying the pane count once there's more than one. It rides
    // between the tab name and the pill's right edge (after the fullscreen/sync/
    // bell glyphs tab_style appended into `text`).
    let badge_section = badge.map(|badge| {
        // The same three colours sill's `agents` pill uses — peach "needs you",
        // sky "working", green "done" — but read out of theme slots rather than
        // hardcoded hexes, so a non-nebelung zellij theme still gets sane ones.
        // Under nebelung these resolve to exactly sill's peach/sky/green.
        let state_color = match badge.state {
            AgentState::Waiting => palette.text_unselected.emphasis_0,
            AgentState::Working => palette.text_unselected.emphasis_1,
            AgentState::Idle => palette.exit_code_success.base,
        };
        // Near-black from the theme rather than the tab's own foreground: that
        // one turns pink while a bell is flashing, which has nothing to do with
        // the agent. Same dark layout_indicator_pill punches its GRID text out in.
        let dark = palette.text_unselected.background;

        // Muted on tabs you're not sitting in — EXCEPT "waiting", which is the
        // one state whose whole job is to shout from a tab you're not looking at.
        // Dimming is a blend toward the BAR's near-black, not toward the tab's own
        // grey: same hue, just turned down, so an idle chip still reads as green
        // instead of washing into the pill it sits on.
        let mut fill = if !tab.active && badge.state != AgentState::Waiting {
            blend(state_color, dark, 0.35)
        } else {
            state_color
        };
        let mut ink = dark;
        // Contrast guard: nebelung paints the ACTIVE tab's pill in the very green
        // that means "done", so an un-dimmed green chip on the tab you're sitting
        // in would melt into it. Darken the chip and punch the digit out in the
        // pill's own colour — which keeps the colour code AND the chip, and reads
        // as the same "turned down" move as the mute above.
        if fill == background_color {
            let darkened = blend(state_color, dark, 0.45);
            if darkened == background_color {
                // Nothing to blend (EightBit theme) — fall back to inverting:
                // chip in the bar's near-black, digit in the state colour.
                fill = dark;
                ink = state_color;
            } else {
                fill = darkened;
                ink = background_color;
            }
        }

        // Terminal cells can't render fractional-width padding, so the chip is
        // bracketed by HALF blocks instead: ▐ and ▌ paint half a cell of chip and
        // half a cell of the tab's own fill, which centres the digit inside the
        // colour and insets the chip from both the tab name and the pill's edge.
        // Ghostty draws U+2588..259F itself, pixel-exact, so the halves butt
        // seamlessly against the full-background digit cell between them.
        //
        // At exactly one agent the digit is dropped entirely: "1" is the common
        // case and carries no information the chip's presence doesn't already, so
        // the badge collapses to a bare one-cell mark. A number appears only when
        // there's actually something to count.
        let left = style!(fill, background_color).paint("▐").to_string();
        let right = style!(fill, background_color).paint("▌").to_string();
        let digits = if badge.count > 1 {
            style!(ink, fill)
                .bold()
                .paint(badge.count.to_string())
                .to_string()
        } else {
            String::new()
        };
        format!("{}{}{}", left, digits, right)
    });
    // Two cells for the half-block brackets, plus the digits when they're drawn.
    // Accurate length is what keeps the clickable tab targets aligned with their
    // painted pills.
    if let Some(badge) = badge {
        tab_text_len += 2;
        if badge.count > 1 {
            tab_text_len += badge.count.to_string().width();
        }
    }

    let right_separator = style!(background_color, separator_fill_color).paint(separator);
    let tab_styled_text = if !focused_clients.is_empty() {
        let (cursor_section, extra_length) =
            cursors(focused_clients, palette.multiplayer_user_colors);
        tab_text_len += extra_length + 2; // 2 for cursor_beginning and cursor_end
        let mut s = String::new();
        let cursor_beginning = style!(foreground_color, background_color)
            .bold()
            .paint("[")
            .to_string();
        let cursor_section = ANSIStrings(&cursor_section).to_string();
        let cursor_end = style!(foreground_color, background_color)
            .bold()
            .paint("]")
            .to_string();
        s.push_str(&left_separator.to_string());
        s.push_str(&tab_styled_text.to_string());
        s.push_str(&cursor_beginning);
        s.push_str(&cursor_section);
        s.push_str(&cursor_end);
        if let Some(badge_section) = &badge_section {
            s.push_str(badge_section);
        }
        s.push_str(&right_separator.to_string());
        s
    } else if let Some(badge_section) = &badge_section {
        let mut s = String::new();
        s.push_str(&left_separator.to_string());
        s.push_str(&tab_styled_text.to_string());
        s.push_str(badge_section);
        s.push_str(&right_separator.to_string());
        s
    } else {
        ANSIStrings(&[left_separator, tab_styled_text, right_separator]).to_string()
    };

    LinePart {
        part: tab_styled_text,
        len: tab_text_len,
        tab_index: Some(tab.position),
    }
}

pub fn tab_style(
    mut tabname: String,
    tab: &TabInfo,
    mut is_alternate_tab: bool,
    palette: Styling,
    capabilities: PluginCapabilities,
    badge: Option<AgentBadge>,
) -> LinePart {
    let separator = tab_separator(capabilities);

    // Fork: compact status glyphs instead of upstream's verbose
    // " (FULLSCREEN)" / " (SYNC)" suffixes — those blow the tab width out in
    // thin views (the whole point of this bar). These mirror the glyphs the old
    // zjstatus config used: [] fullscreen, <> sync, ! bell.
    if tab.is_fullscreen_active {
        tabname.push_str(" []");
    } else if tab.is_sync_panes_active {
        tabname.push_str(" <>");
    }
    if tab.has_bell_notification || tab.is_flashing_bell {
        tabname.push_str(" !");
    }
    // we only color alternate tabs differently if we can't use the arrow fonts to separate them
    if !capabilities.arrow_fonts {
        is_alternate_tab = false;
    }

    render_tab(tabname, tab, is_alternate_tab, palette, separator, badge)
}

pub(crate) fn get_tab_to_focus(
    tab_line: &[LinePart],
    active_tab_idx: usize,
    mouse_click_col: usize,
) -> Option<usize> {
    let clicked_line_part = get_clicked_line_part(tab_line, mouse_click_col)?;
    let clicked_tab_idx = clicked_line_part.tab_index?;
    // tabs are indexed starting from 1 so we need to add 1
    let clicked_tab_idx = clicked_tab_idx + 1;
    if clicked_tab_idx != active_tab_idx {
        return Some(clicked_tab_idx);
    }
    None
}

pub(crate) fn get_clicked_line_part(
    tab_line: &[LinePart],
    mouse_click_col: usize,
) -> Option<&LinePart> {
    let mut len = 0;
    for tab_line_part in tab_line {
        if mouse_click_col >= len && mouse_click_col < len + tab_line_part.len {
            return Some(tab_line_part);
        }
        len += tab_line_part.len;
    }
    None
}
