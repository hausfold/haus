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

/// The raw SGR for a styled, independently-coloured underline: `style` is the
/// bare underline parameter (`4`, or a `4:n` sub-parameter form), followed by
/// SGR 58, which sets the underline colour separately from the foreground.
///
/// Hand-emitted because ansi_term models neither. Nothing here turns the
/// underline back OFF — the reset ansi_term writes after every string it paints
/// does that, so the SGR has to be emitted immediately before a painted run and
/// can never leak past it.
fn underline_sgr(style: &str, color: PaletteColor) -> String {
    let color = match color {
        PaletteColor::Rgb((r, g, b)) => format!("58;2;{};{};{}", r, g, b),
        PaletteColor::EightBit(c) => format!("58;5;{}", c),
    };
    format!("\u{1b}[{}m\u{1b}[{}m", style, color)
}

/// An agent count as superscript digits.
///
/// A raised digit is the one way a terminal can render a smaller number, and it
/// only works because nothing is filled behind it: on a solid block a
/// superscript floats at cap height with a third of the chip empty under it.
/// Beside an underlined name it reads as what it is — a footnote on the label.
///
/// JetBrains Mono (this rice's terminal font) covers all ten, though they live
/// in three different blocks: ¹²³ are Latin-1 leftovers, the rest are U+2070's.
/// All are East-Asian-Ambiguous, i.e. one cell wide the way this bar's `←`/`→`
/// already are.
fn superscript_digits(count: usize) -> String {
    const SUPERSCRIPTS: [char; 10] = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];
    count
        .to_string()
        .chars()
        .map(|c| {
            c.to_digit(10)
                .map(|d| SUPERSCRIPTS[d as usize])
                .unwrap_or(c)
        })
        .collect()
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
    // not a chip bolted to the edge of one. This is the only state that gets it:
    // the point of a hierarchy is that the loud thing is loud *because* the quiet
    // things stayed quiet, and working/idle say their piece with the underline
    // below. The active tab is exempt — its pill colour already means "you are
    // here", and you don't need to be told to look at the tab you're looking at.
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

    // Fork: the agent-status signal. It is NOT a chip — a chip is a foreign
    // object bolted to the tab, and with no digit in it (the one-agent case, i.e.
    // most tabs) it reads as a floating sliver rather than a badge. Instead the
    // tab's own typography carries it:
    //
    //   · a styled, independently-coloured UNDERLINE beneath the tab name —
    //     the state, on every tab, costing zero columns and nothing that floats
    //   · the WASH above — the pill itself, for the one state that needs you
    //   · a SUPERSCRIPT count in the pad cell, only once there's >1 to count
    //
    // Underline colour and shape both encode the state, which is deliberate
    // redundancy: at 19pt a two-pixel rule's hue is easy to lose, but curly vs
    // straight vs dotted survives being small, being dim, and being colour-blind.
    let (underline, superscript) = match (badge, state_color) {
        (Some(badge), Some(state_color)) => {
            // Three rules of the same weight but different rhythm: dashes read as
            // marching ants and get the state that wants you, solid is steady
            // work in progress, dotted is the quietest rule a terminal can draw
            // and belongs to "finished, nothing to do". zellij's SGR parser
            // handles 4:2/4:3/4:4/4:5 and ghostty draws all of them.
            //
            // NOT undercurl (4:3), tempting as the spell-checker "something here
            // is wrong" reading is: ghostty draws the wave partly BELOW the cell
            // box. Inside a normal pane that's invisible (the row beneath shares
            // the background), but this bar is ONE row — the wave hangs off the
            // bottom of the pill onto the bar, and worse, onto pixels the pane
            // below owns and will repaint over. Double (4:2) puts its second rule
            // in the same overhanging position. Everything here is single-height.
            let ul_style = match badge.state {
                AgentState::Waiting => "4:5", // dashed
                AgentState::Working => "4",   // solid
                AgentState::Idle => "4:4",    // dotted
            };
            // On a washed pill the state colour is already the BACKGROUND, so a
            // rule in that same colour would be invisible: draw it near-black
            // instead, which is also what the tab's own text is. On the active tab
            // the pill is the theme's green "you are here", so darken the rule to
            // keep it legible against a light fill. Everywhere else the rule IS
            // the only colour the tab carries, so it stays full strength.
            let ul_color = if tab.active {
                blend(state_color, dark, 0.35)
            } else if badge.state == AgentState::Waiting {
                dark
            } else {
                state_color
            };
            let superscript = if badge.count > 1 {
                Some((superscript_digits(badge.count), ul_color))
            } else {
                None
            };
            (Some(underline_sgr(ul_style, ul_color)), superscript)
        },
        _ => (None, None),
    };
    if let Some((digits, _)) = &superscript {
        tab_text_len += digits.width();
    }

    // The pill is painted in three pieces rather than one so the underline can
    // sit under the NAME alone — a rule running out under the padding would read
    // as a border on the pill instead of as a mark on the label.
    let tab_styled_text = {
        let pad = |s: &str| {
            style!(foreground_color, background_color)
                .bold()
                .paint(s.to_string())
                .to_string()
        };
        let mut s = String::new();
        s.push_str(&pad(" "));
        // ansi_term knows nothing about underlines, so the SGR is emitted by hand
        // ahead of the painted name; the reset ansi_term already writes after its
        // own text is what turns the underline back off.
        if let Some(underline) = &underline {
            s.push_str(underline);
        }
        s.push_str(
            &style!(foreground_color, background_color)
                .bold()
                .paint(text.clone())
                .to_string(),
        );
        if let Some((digits, color)) = &superscript {
            s.push_str(
                &style!(*color, background_color)
                    .bold()
                    .paint(digits.clone())
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
