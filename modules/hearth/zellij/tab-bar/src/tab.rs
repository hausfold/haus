use crate::{line::tab_separator, AgentBadge, AgentState, LinePart};
use ansi_term::{ANSIString, ANSIStrings};
use unicode_width::UnicodeWidthStr;
use zellij_tile::prelude::*;
use zellij_tile_utils::style;

// Second fork of the agent-status signal: a leading STATE DOT plus a trailing
// count CHIP, replacing the original underline + superscript pair (see git
// history for that version). Both prior signals leaned on subtle terminal
// rendering — a sub-pixel underline curve, a raised-baseline digit — that
// turned out to be exactly the kind of thing that's hard to see at a normal
// terminal font size. Shape carries the state now instead of line style, and
// the count is a real filled chip instead of a few faint lit pixels: this is
// the badge the header comment described before either of those existed.
//
// Same construction as line.rs's layout_indicator_pill (the yellow GRID
// rectangle): hand-painted flat block, no powerline caps, so the badge chip
// and that pill read as one family.

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

/// The state dot's glyph. Shape carries the meaning, colour is redundant on
/// top of it — the same belt-and-suspenders reasoning the old dashed / solid /
/// dotted underline styles used, but shape survives being small and being
/// squinted at in a way a line-style distinction didn't.
///
/// `○ ◐ ●` are the fill sequence: empty, half, full — "how done is this",
/// which reads correctly whether you follow the metaphor or not. All three
/// are one cell wide in JetBrains Mono (this rice's terminal font).
fn state_dot(state: AgentState) -> char {
    match state {
        AgentState::Idle => '○',
        AgentState::Working => '◐',
        AgentState::Waiting => '●',
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
    let mut background_color = if tab.active {
        palette.ribbon_selected.background
    } else if is_alternate_tab {
        alternate_tab_color
    } else {
        palette.ribbon_unselected.background
    };

    // The same three colours sill's `agents` pill uses — peach "needs you", sky
    // "working", green "done" — read out of theme slots rather than hardcoded
    // hexes, so a non-nebelung zellij theme still gets sane ones. Under nebelung
    // these resolve to exactly sill's peach/sky/green.
    let state_color = badge.map(|badge| match badge.state {
        AgentState::Waiting => palette.text_unselected.emphasis_0,
        AgentState::Working => palette.text_unselected.emphasis_1,
        AgentState::Idle => palette.exit_code_success.base,
    });
    // Near-black from the theme rather than the tab's own foreground: that one
    // turns pink while a bell is flashing, which has nothing to do with the agent.
    // Same dark layout_indicator_pill punches its GRID text out in.
    let dark = palette.text_unselected.background;

    // THE WASH. A tab with an agent blocked on you takes over its whole pill —
    // louder than the dot could ever be on its own. This is the only state that
    // gets it: the point of a hierarchy is that the loud thing is loud *because*
    // the quiet things stayed quiet, and working/idle say their piece with the
    // dot alone. The active tab is exempt — its pill colour already means "you
    // are here", and you don't need to be told to look at the tab you're looking
    // at.
    if let (Some(badge), Some(state_color)) = (badge, state_color) {
        if badge.state == AgentState::Waiting && !tab.active {
            background_color = blend(background_color, state_color, 0.6);
        }
    }
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

    // Fork: the agent-status signal. Three pieces:
    //
    //   · a leading STATE DOT before the tab name — shape (○ ◐ ●) carries the
    //     state, colour is redundant on top of it, costing 2 columns on every
    //     agent tab
    //   · the WASH above — the pill itself, for the one state that needs you
    //   · a trailing count CHIP — a real filled rectangle, not a glyph — only
    //     once there's >1 agent to count
    //
    // Dot shape and chip fill both encode the state, which is deliberate
    // redundancy: colour alone is a bad bet (small swatches, colour-blindness),
    // so the shape has to carry the meaning on its own and colour just confirms
    // it.
    let (dot, badge_chip) = match (badge, state_color) {
        (Some(badge), Some(state_color)) => {
            // On a washed pill the state colour is already the BACKGROUND, so a
            // dot in that same colour would vanish into it: draw it near-black
            // instead, which is also what the tab's own text is. On the active tab
            // the pill is the theme's green "you are here", so darken the dot to
            // keep it legible against a light fill. Everywhere else the dot IS the
            // only colour the tab carries, so it stays full strength.
            let dot_color = if tab.active {
                blend(state_color, dark, 0.35)
            } else if badge.state == AgentState::Waiting {
                dark
            } else {
                state_color
            };
            let badge_chip = if badge.count > 1 {
                Some((badge.count.to_string(), state_color))
            } else {
                None
            };
            (Some((state_dot(badge.state), dot_color)), badge_chip)
        },
        _ => (None, None),
    };
    if dot.is_some() {
        tab_text_len += 2; // glyph + the space separating it from the name
    }
    if let Some((digits, _)) = &badge_chip {
        // " N " chip, plus the plain-background space separating it from the name.
        tab_text_len += 1 + digits.width() + 2;
    }

    // The pill is painted in pieces rather than one run so the count chip can
    // carry its OWN fill (the state colour) rather than the pill's — a rectangle
    // stuck to the tab, same construction as line.rs's layout_indicator_pill.
    let tab_styled_text = {
        let pad = |s: &str| {
            style!(foreground_color, background_color)
                .bold()
                .paint(s.to_string())
                .to_string()
        };
        let mut s = String::new();
        s.push_str(&pad(" "));
        if let Some((glyph, color)) = &dot {
            s.push_str(
                &style!(*color, background_color)
                    .bold()
                    .paint(glyph.to_string())
                    .to_string(),
            );
            s.push_str(&pad(" "));
        }
        s.push_str(
            &style!(foreground_color, background_color)
                .bold()
                .paint(text.clone())
                .to_string(),
        );
        if let Some((digits, color)) = &badge_chip {
            s.push_str(&pad(" "));
            s.push_str(
                &style!(dark, *color)
                    .bold()
                    .paint(format!(" {} ", digits))
                    .to_string(),
            );
        }
        s.push_str(&pad(" "));
        s
    };

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
        s.push_str(&tab_styled_text);
        s.push_str(&cursor_beginning);
        s.push_str(&cursor_section);
        s.push_str(&cursor_end);
        s.push_str(&right_separator.to_string());
        s
    } else {
        format!(
            "{}{}{}",
            left_separator, tab_styled_text, right_separator
        )
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
