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
# (sizes.sh) rather than a number, so both follow nebelhaus.ui.scale.
#     → sets P_ICON, P_FONT, P_NAME
#
# The sketchybar-app-font glyphs (:claude:, :openai:) are monochrome and take
# icon.color like any other, so the caller stays free to paint them by state.

provider_style() {
  local prov="${1:-}" model="${2:-}" size="${3:-${FS_LABEL:-14.0}}"
  local appfont="sketchybar-app-font:Regular:${FS_APP_ICON:-16.0}"
  local nerd="Hack Nerd Font:Bold:$size"
  case "$prov" in
    claude)
      P_ICON=":claude:"; P_FONT="$appfont"; P_NAME="Claude"
      ;;
    codex | openai)
      P_ICON=":openai:"; P_FONT="$appfont"; P_NAME="Codex"
      ;;
    opencode)
      # Opencode bills whichever provider you pointed it at, so the model — not
      # the client — is the honest mark. Empty model (an agent pane, which knows
      # its client but not its model) falls through to the generic one.
      case "$model" in
        google* | gemini*)    P_ICON="✦";       P_FONT="$nerd";    P_NAME="Opencode (${model:-gemini})" ;;
        anthropic* | claude*) P_ICON=":claude:"; P_FONT="$appfont"; P_NAME="Opencode (${model:-claude})" ;;
        openai* | gpt*)       P_ICON=":openai:"; P_FONT="$appfont"; P_NAME="Opencode (${model:-gpt})" ;;
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
