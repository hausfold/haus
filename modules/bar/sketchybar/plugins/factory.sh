#!/bin/bash
# factory.sh — the merge-lease pill: whether this Mac may merge pull requests
# while nobody is watching, and for how much longer
# (hausfold.co/docs/haus/rooms/bar-widgets).
#
# WHY IT SITS BESIDE THE COFFEE PILL. They answer the same shape of question —
# "what did I leave switched on, and when does it stop" — and they are the only
# two pills in the bar that do. A caffeinate assertion holds the Mac awake for a
# stated time; a factory lease holds tier-1 MERGE AUTHORITY for one, and while
# it stands `factory watchdog run` passes `factory shift` on a cadence and lands
# what the filter can vouch for with nobody in the room. That is a state you put
# the machine in deliberately and then stop thinking about, which is exactly the
# kind a bar is for. Expired or revoked, everything queues at "PR open" — the
# ordinary human-in-the-loop workflow — so the pill going grey is never a fault.
#
# It renders state and relays four verbs and does nothing else. Every duration,
# exit code and word below is factory's; the lease file is machine-local by that
# tool's own design, and nothing here writes it.
#
# `factory_change`, below, is the poke the palette's Merge Lease command fires
# after it grants or revokes (modules/launcher/commands/merge-lease.sh, through
# `haus-bar-poke`), so the two surfaces never disagree for up to a tick. This
# pill's own rows do not need it: they end in `barlib_tick`, which is the same
# repaint one process earlier.
# widget: interval   = 30
# widget: popup      = true
# widget: mark       = plum
# widget: subscribes = factory_change

BAR_ITEM=factory
source "$HOME/.config/sketchybar/barlib.sh"

# The pill's glyph, and its dropdown heading's. Nerd Font `oct-git_merge_queue`
# (U+F4DB): the queue of pull requests going in on their own is the whole
# subject, and it keeps the octicon family the `github` pill already spends —
# these two pills are the same queue seen from either end. Deliberately NOT a
# robot, which is the `agents` pill's mark.
#
# The same glyph is in this pill's Nix block (modules/bar/default.nix) so the
# item is drawn correctly from `--add` time; this copy is what `pill` re-centres
# when the label goes away and what the heading wears. Same two-copy shape the
# coffee pill's `󰅶` has, for the same reason.
ICON=""

# This file, by the path SketchyBar knows it as — a popup row's click_script is
# a string SketchyBar runs later in a fresh process, so it cannot call functions
# from here.
SELF="$HOME/.config/sketchybar/plugins/factory.sh"

# Resolve `factory`. modules/ai puts it in `environment.systemPackages` under
# `haus.ai.enable`, so the honest question is "is that binary on this disk" and
# it is a RUNTIME one: a Mac with the AI room off has this pill's subject
# missing entirely, and a nix-time answer would make the bar depend on a room it
# may not read (AGENTS.md, the extension-point rule).
#
# $FACTORY_BIN first, so a branch build can be pointed at; then the system
# profile, which is where that room puts it; then the per-user profile, for a
# host that installed it there instead. Resolved once at source time, which is
# once per invocation — SketchyBar runs this file fresh on every tick and every
# click, so there is no staleness to carry.
FACTORY=""
for _candidate in \
    "${FACTORY_BIN:-}" \
    "/run/current-system/sw/bin/factory" \
    "/etc/profiles/per-user/${USER:-}/bin/factory"; do
    [ -n "$_candidate" ] && [ -x "$_candidate" ] && { FACTORY="$_candidate"; break; }
done

notify() { # notify <title> <body> <sf-symbol>
    # Through haus-notify, so trill draws it when it can and `rules.json` can
    # route it. Absolute: SketchyBar runs plugins under launchd's bare PATH.
    # `|| true` — a failed banner must not fail the arm reporting a failure.
    /run/current-system/sw/bin/haus-notify --source haus.bar.factory --kind fault \
        --symbol "$3" --title "$1" --body "$2" >/dev/null 2>&1 || true
}

# `factory lease status --json` is the machine face of that CLI and the only
# thing this pill reads — one object, on stdout, with nothing else on the
# stream. Its exit code is the answer as well (0 live · 1 none/expired), which
# is why the call carries `|| true`: a lease-less Mac is the ordinary state and
# not an error to swallow into an empty parse.
#
# ONE jq, not four. `expires` and `secondsLeft` are null on an indefinite lease
# — deliberately, so a caller drawing a countdown says "until revoked" rather
# than "1,051 years" — so `// 0` is what turns that null into a number the
# arithmetic below can hold, with `indefinite` carrying the real answer.
read_lease() { # sets LIVE INDEFINITE LEFT LINE
    LIVE=0
    INDEFINITE=0
    LEFT=0
    LINE=""
    [ -n "$FACTORY" ] || return 0
    local json fields
    json=$("$FACTORY" lease status --json 2>/dev/null) || true
    [ -n "$json" ] || return 0
    fields=$(printf '%s' "$json" | jq -r '
        [ (if .live then 1 else 0 end),
          (if .indefinite then 1 else 0 end),
          (.secondsLeft // 0),
          (.line // "") ] | @tsv' 2>/dev/null) || return 0
    [ -n "$fields" ] || return 0
    IFS="$(printf '\t')" read -r LIVE INDEFINITE LEFT LINE <<EOF
$fields
EOF
}

# Seconds → "12h" / "3h 58m" / "38m", rounded UP to the minute. The rounding is
# not cosmetic: the emitted state is what barlib diffs, so a label that carried
# seconds would differ on every tick and repaint a pill that has nothing new to
# say. Up rather than down so a lease with fifty seconds left reads "1m" instead
# of "0m", which is the one value that would look like it had already lapsed.
fmt_left() { # fmt_left <seconds>
    local s=${1:-0} m h
    case "$s" in '' | *[!0-9]*) s=0 ;; esac
    m=$(((s + 59) / 60))
    h=$((m / 60))
    m=$((m % 60))
    if [ "$h" -gt 0 ] && [ "$m" -gt 0 ]; then
        printf '%dh %dm' "$h" "$m"
    elif [ "$h" -gt 0 ]; then
        printf '%dh' "$h"
    else
        printf '%dm' "$m"
    fi
}

fetch() {
    [ -n "$FACTORY" ] || { emit present=0; return 0; }
    read_lease
    local label=''
    if [ "$LIVE" = 1 ]; then
        if [ "$INDEFINITE" = 1 ]; then label="∞"; else label="$(fmt_left "$LEFT")"; fi
    fi
    emit present=1 live="$LIVE" label="$label"
}

# No factory on this Mac: draw NOTHING (`pill --hide`, the drawing=off/
# updates=on pairing the runtime owns). It comes back by itself the moment the
# binary lands, because that pairing keeps this tick running while the pill is
# hidden.
#
# Live is `busy` — "the machine has it, not you", which is the ladder's own
# words for a standing grant something else is acting on. At rest the glyph
# keeps `text`: no lease is not a fault and not a stale feed, it is the pill's
# ordinary state and the coffee pill beside it draws its own that way. Nothing
# here fills the pill: two filled capsules side by side would be two shouts, and
# this one has a countdown to carry in the label instead.
render() {
    if [ "$present" != 1 ]; then
        pill --hide
        return 0
    fi
    if [ "$live" = 1 ]; then
        pill --icon "$ICON" --label "$label" --tone busy --label-tone busy
    else
        pill --icon "$ICON" --label "" --tone text
    fi
}

# The heading says what the lease IS DOING — the time left as a badge while one
# stands, and factory's own last word about it as a caption when none does
# ("none", "expired Mon 19:30", "revoked"). Rebuilt on every open, so the revoke
# button can wear the state it acts on rather than being repainted from afar.
popup_rows() {
    read_lease
    if [ "$LIVE" = 1 ] && [ "$INDEFINITE" = 1 ]; then
        popup_heading --icon "$ICON" --label "Merge lease" \
            --badge "until revoked" --badge-tone busy
    elif [ "$LIVE" = 1 ]; then
        popup_heading --icon "$ICON" --label "Merge lease" \
            --badge "$(fmt_left "$LEFT")" --badge-tone busy
    else
        # `lease: none` / `lease: expired …` — factory's sentence, with its own
        # prefix taken off because the heading has already said which lease.
        popup_heading --icon "$ICON" --label "Merge lease" --hint "${LINE#lease: }"
    fi
    popup_action --icon "4" --label "4 hours" --run "$SELF grant 4h"
    popup_action --icon "12" --label "12 hours" --run "$SELF grant 12h"
    popup_action --icon "∞" --label "Until revoked" --run "$SELF grant indefinitely"
    popup_separator
    # The revoke is a BUTTON that wears the state it acts on: solid red while
    # there is authority to take back — the one destructive control here, drawn
    # as one — and a grey tint when there is nothing to end. It stays pressable
    # either way, because `factory lease revoke` also stops a runner that
    # outlived its lease, and that is worth a door even when the pill is grey.
    if [ "$LIVE" = 1 ]; then
        popup_button --icon "󰅖" --tone bad --solid --label "Revoke" --run "$SELF revoke"
    else
        popup_button --icon "󰅖" --tone mute --label "Revoke" --run "$SELF revoke"
    fi
}

on_click() { popup_toggle; }

on_right_click() {
    popup_close
    lease revoke
}

# The four verbs, as a CLI mode rather than handlers: each one is a popup row's
# click_script — a fresh process — so it ends `barlib_tick; exit 0` without ever
# reaching barlib_main, which would otherwise route on whatever $SENDER this
# process inherited. Same shape github.sh's CLI modes have, for the same reason.
#
# The tick at the end is what makes "off clears the pill" immediate instead of
# up to one 30-second interval away: factory has no bar event to fire, so the
# hand that changed the world is the one that has to say so.
lease() { # lease grant <duration> | lease revoke
    if [ -z "$FACTORY" ]; then
        notify "Merge lease" "factory is not installed on this Mac." exclamationmark.triangle
    else
        local err rc=0
        # stderr only: factory reports every refusal there and every ✓ on
        # stdout, so this captures the sentence worth repeating and drops the
        # one the pill is about to draw anyway.
        err=$("$FACTORY" lease "$@" 2>&1 >/dev/null) || rc=$?
        if [ "$rc" -ne 0 ]; then
            notify "Merge lease" "${err:-factory lease $* failed}" exclamationmark.triangle
        fi
    fi
    barlib_tick
}

case "${1:-}" in
    grant | revoke)
        lease "$@"
        exit 0
        ;;
esac

barlib_main "$@"
