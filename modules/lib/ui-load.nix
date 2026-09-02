# snug's painter bootstrap, spelled once.
#
# Ten scripts across six rooms reach ui.sh — snug's bash half of the painter
# — and each used to carry its own spelling of the same mechanics: resolve the
# path, guard the bash version, source without dying, probe before trusting.
# Ten spellings drift ten ways, and every failure mode on this seam is
# SILENT (a half-loaded painter answers `type` and then draws nothing), which
# is how each of the traps in the text below got paid for more than once. So:
# two verbs, defined here as the strings every carrier holds VERBATIM.
#
#   resolve   ui_resolve — fill HAUS_UI_SH with the painter's path and stop.
#             For a carrier that hands the path to ANOTHER shell (lane-open's
#             held snippet draws in the lane's own terminal, so resolving
#             colour here would be wrong twice over), or one that may be run
#             with no injected path at all.
#   load      ui_load — source the painter once, lazily, and set UI_READY
#             only when every verb the carrier names in UI_WANT arrived.
#
# The carriers keep a COPY in the file rather than taking this text at build
# time, deliberately: most of them are also run straight off the checkout —
# test/awake.sh and test/focus-auto.sh drive their subjects raw,
# phase-painter.bats sources haus.sh as a library, a person debugging the
# coffee pill runs modules/core/awake.sh by hand — and two are installed as
# `home.file` symlinks nothing substitutes into. A copy drifts, so the copies
# are pinned twice: `nix flake check`'s ui-load-sync diffs every carrier
# against these strings (the carrier list lives beside that check), and
# test/phase-painter.bats diffs the carriers against each other for a machine
# running only bats. Editing a verb means editing it HERE and re-copying into
# each carrier; the checks are what make forgetting one a red build instead
# of an eleventh spelling.
#
# What stays per-carrier, on purpose: HOW the path arrives (a `@uiSh@` hole,
# a prepended `HAUS_UI_SH=` line, the `haus` wrapper's --set-default — all
# three blessed in AGENTS.md), WHEN ui_load runs (lazily from the draw paths
# for focus/awake/haus-secret, eagerly at load for the CLIs), and WHICH verbs
# UI_WANT names.
{
  resolve = ''
    # ── ui_resolve — the painter's PATH, and nothing else ────────────────────────
    # The ONE copy of this block is modules/lib/ui-load.nix; `nix flake check`
    # (ui-load-sync) diffs this file against it, so edit it THERE and re-copy.
    # Honour a caller's HAUS_UI_SH — the `haus` wrapper and the injecting
    # derivations set an absolute store path — else take the copy that ships
    # beside `bin/snug` in snug's own derivation, which can never be a version
    # apart from the binary; the carrier's own PATH setup is what makes `snug`
    # findable at all. Never the name `UI_SH`: that exact name is ui.sh's own
    # source-twice sentinel, and a caller holding the path in it makes the file
    # return before defining anything — no error, no colour, and a green suite,
    # because every role is legitimately empty when the painter is absent. Ends
    # readable-or-empty, so `[ -n "$HAUS_UI_SH" ]` is the whole downstream test.
    # No source, no bash-version check: resolving must stay safe in a shell that
    # could never LOAD the painter — that is ui_load's job, where one exists.
    ui_resolve() {
        if [ -z "''${HAUS_UI_SH:-}" ]; then
            local _snug
            _snug="$(command -v snug 2>/dev/null)" \
                && HAUS_UI_SH="$(dirname "$(dirname "$(readlink -f "$_snug")")")/share/ui.sh"
        fi
        [ -r "''${HAUS_UI_SH:-}" ] || HAUS_UI_SH=""
        return 0
    }
  '';

  load = ''
    # ── ui_load — source the painter once, and answer whether it can draw ────────
    # The ONE copy of this block is modules/lib/ui-load.nix; `nix flake check`
    # (ui-load-sync) diffs this file against it, so edit it THERE and re-copy.
    # UI_READY=1 only when every verb named in UI_WANT arrived: the carrier sets
    # UI_WANT to every ui_* verb it CALLS, not a sample, because a pin whose ui.sh
    # predates one of them is a `command not found` halfway down a report — under
    # `set -e` an abort AFTER the machine changed and before anything said so —
    # and UI_READY would have licensed it. Idempotent, so calling it lazily from
    # each draw path and calling it once at load are the same verb; a path that
    # never draws never calls it and pays nothing. Three traps, each silent, each
    # paid for before this block existed:
    #
    #   * ui.sh is bash 4+ (`declare -gA`, `''${v^^}`). macOS's /bin/bash 3.2 does
    #     not fail it quietly: three `bad substitution` errors and a half-loaded
    #     painter that answers `type` and then draws nothing — so the version is
    #     checked, never assumed, and 3.2 keeps the plain output.
    #   * `|| true` is load-bearing under `set -euo pipefail`: a sourced file's
    #     non-zero exit is the caller's to survive, and a ui.sh that failed at
    #     load would otherwise abort the verb mid-flight — for `awake 3h`, AFTER
    #     the assertion started.
    #   * The path stays in `HAUS_UI_SH`, never `UI_SH` — that exact name is
    #     ui.sh's own source-twice sentinel, and holding the path in it makes the
    #     file return before defining anything, with no error and no colour.
    UI_READY=""
    ui_load() {
        [ -n "''${UI_LOADED:-}" ] && return 0
        UI_LOADED=1
        [ "''${BASH_VERSINFO[0]:-0}" -ge 4 ] || return 0
        if [ -r "''${HAUS_UI_SH:-}" ]; then
            # shellcheck source=/dev/null
            source "$HAUS_UI_SH" || true
        fi
        [ -n "''${UI_WANT:-}" ] || return 0
        # shellcheck disable=SC2086
        type $UI_WANT >/dev/null 2>&1 && UI_READY=1
        return 0
    }
  '';
}
