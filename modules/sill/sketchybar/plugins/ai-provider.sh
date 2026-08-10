#!/bin/bash
# ai-provider.sh — one table for "what does this AI client look like", sourced by
# every bar item that has to draw one. Not a plugin: it defines a function and
# exits, so it never appears in a sketchybar item's `script=`.
#
# Two readers use it, and they used to carry their own copy of the same case
# block — which is how the aiUsage pill grew an OpenAI mark for Codex while the
# agents pill still drew every client as the same anonymous paw:
#   • ai_usage.sh — one row per provider REPORTING USAGE (claude/codex/opencode),
#     where opencode is really a bring-your-own-key front end, so its mark comes
#     from the model behind it rather than from opencode itself.
#   • agents.sh   — one row per RUNNING AGENT PANE, whose client id is written
#     into the state file by agents-hook.sh. No model is known there; the
#     second argument is simply empty and the generic mark is right.
#
#   provider_style <provider> [model-or-provider-id] [nerd-font-size]
#
# The size is the caller's, because the same table is drawn at pill size in the
# bar and one step down in a popup row. Callers pass $FS_LABEL / $FS_SMALL
# (sizes.sh) rather than a number, so both follow haus.ui.scale.
#     → sets P_ICON, P_FONT, P_NAME, P_COLOR
#
# The sketchybar-app-font glyphs (:claude:, :openai:) are monochrome and take
# icon.color like any other, so the caller stays free to paint them by state.
#
# P_COLOR is that client's BRAND accent, and it is deliberately drawn from the
# half of the palette the status ladder never uses (GREEN/YELLOW/PEACH/RED are
# reserved for how-full-is-it, everywhere in the bar). That is the whole rule
# the dropdown's colour scheme rests on: **a hue on a mark means identity, a hue
# on a number means state.** Paint a header icon YELLOW and the popup silently
# starts claiming a provider is at 60% of something.

# This file is a LIBRARY (ai_usage.sh and agents.sh source it), and the family
# it draws in lives in the generated sizes.sh with the FS_* sizes. Both current
# callers source that first, but a third one wouldn't have to — and an unset
# BAR_FONT is a font string starting with ":", which sketchybar takes without
# complaint and draws as nothing. So source it here too; it only sets values.
# shellcheck source=/dev/null
[ -n "${BAR_FONT:-}" ] || source "$HOME/.config/sketchybar/sizes.sh"
# Same story for the palette, now that the table names brand accents: under
# `set -u` an unsourced colours.sh is not a wrong colour, it is the caller
# exiting mid-repaint.
# shellcheck source=/dev/null
[ -n "${MAUVE:-}" ] || source "$HOME/.config/sketchybar/colors.sh"

provider_style() {
  local prov="${1:-}" model="${2:-}" size="${3:-${FS_LABEL:-14.0}}"
  local appfont="sketchybar-app-font:Regular:${FS_APP_ICON:-16.0}"
  local nerd="${BAR_FONT}:Bold:$size"
  # The accents, and why each: FLAMINGO is the palette's warm clay, the nearest
  # neighbour to Anthropic's orange that isn't PEACH (a status colour); TEAL is
  # OpenAI's green-teal; LAVENDER is Gemini's blue-violet; MAUVE is the
  # bring-your-own-key catch-all, which is also what an unknown client gets.
  P_COLOR="${MAUVE:-0xffc9a8f1}"
  case "$prov" in
    claude)
      P_ICON=":claude:"; P_FONT="$appfont"; P_NAME="Claude"; P_COLOR="$FLAMINGO"
      ;;
    codex | openai)
      P_ICON=":openai:"; P_FONT="$appfont"; P_NAME="Codex"; P_COLOR="$TEAL"
      ;;
    opencode)
      # Opencode bills whichever provider you pointed it at, so the model — not
      # the client — is the honest mark. Empty model (an agent pane, which knows
      # its client but not its model) falls through to the generic one. The
      # accent follows the mark for the same reason: an Opencode row pointed at
      # Gemini should read as Gemini at a glance, not as "some API".
      case "$model" in
        google* | gemini*)    P_ICON="✦";       P_FONT="$nerd";    P_NAME="Opencode (${model:-gemini})"; P_COLOR="$LAVENDER" ;;
        anthropic* | claude*) P_ICON=":claude:"; P_FONT="$appfont"; P_NAME="Opencode (${model:-claude})"; P_COLOR="$FLAMINGO" ;;
        openai* | gpt*)       P_ICON=":openai:"; P_FONT="$appfont"; P_NAME="Opencode (${model:-gpt})";    P_COLOR="$TEAL" ;;
        "")                   P_ICON="󰏫";       P_FONT="$nerd";    P_NAME="Opencode" ;;
        *)                    P_ICON="󰏫";       P_FONT="$nerd";    P_NAME="Opencode (${model:-api})" ;;
      esac
      ;;
    *)
      # A client we don't have a mark for — a future one, or an agent whose hook
      # named none. Draw the generic writing-hand and say what it called itself.
      P_ICON="󰏫"; P_FONT="$nerd"; P_NAME="${prov:-agent}"
      ;;
  esac
}
