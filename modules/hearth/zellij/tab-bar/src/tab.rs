use crate::{line::tab_separator, AgentState, LinePart};
use ansi_term::{ANSIString, ANSIStrings};
use unicode_width::UnicodeWidthStr;
use zellij_tile::prelude::*;
use zellij_tile_utils::style;

// nf-fa-paw (U+F1B0) — the exact glyph sill's `agents` menu-bar pill draws, so
// the bar and the tab read as one signal rather than two conventions.
//
// It counts as ONE column here because nebelhaus.fonts.mono is a Nerd Font
// *Mono* build (JetBrainsMono Nerd Font Mono by default), which forces every
// patched glyph to single width — same assumption the `⌃⇥` reminder and the
// `←`/`→` overflow pills in line.rs already ride on. In a non-Mono Nerd Font the
// paw draws double-width and every tab's click target drifts one column right of
// where it's painted.
static AGENT_PAW: &str = "\u{f1b0}";

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
    badge: Option<AgentState>,
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

    // Fork: the agent-status paw, painted independently of the tab name so its
    // colour carries the state instead of the name's. Sits between the name and
    // the pill's right edge, after the fullscreen/sync/bell glyphs tab_style
    // appended into `text`.
    let badge_section = badge.map(|state| {
        // The same three colours sill's `agents` pill uses — peach "needs you",
        // sky "working", green "done" — but read out of theme slots rather than
        // hardcoded hexes, so a non-nebelung zellij theme still gets sane ones.
        // Under nebelung these resolve to exactly sill's peach/sky/green.
        let badge_color = match state {
            AgentState::Waiting => palette.text_unselected.emphasis_0,
            AgentState::Working => palette.text_unselected.emphasis_1,
            AgentState::Idle => palette.exit_code_success.base,
        };
        // Contrast guard: nebelung paints the ACTIVE tab's pill in the very green
        // it uses for "done", so an unguarded green paw would be invisible on the
        // one tab you're sitting in. Fall back to the tab's own foreground there —
        // you lose the colour code on that single tab, never the badge itself.
        let badge_color = if badge_color == background_color {
            foreground_color
        } else {
            badge_color
        };
        style!(badge_color, background_color)
            .bold()
            .paint(format!("{} ", AGENT_PAW))
            .to_string()
    });
    // The paw plus its trailing space. One column for the glyph only holds in a
    // Nerd Font Mono build — see AGENT_PAW.
    if badge_section.is_some() {
        tab_text_len += 2;
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
    badge: Option<AgentState>,
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
