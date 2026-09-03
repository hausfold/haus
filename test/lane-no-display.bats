#!/usr/bin/env bats
# A background lane spawned with the screen asleep, pinned as an invariant of
# modules/terminal/lanes/lane-open.sh.
#
# ── the failure this exists for ──────────────────────────────────────────────
# MEASURED 2026-09-03: three background lanes spawned between 05:54 and 05:55,
# with the display asleep since 05:49, each came up as Ghostty's "The terminal
# failed to initialize" pane. Ghostty's log, one pair per lane:
#
#   CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)
#   embedded_window: error initializing surface err=error.OutOfMemory
#
# The direct exec has to build its own surface, a surface wants a display link,
# and macOS answers CGGetActiveDisplayList with zero while the screen is off.
#
# What made it cost three TASKS rather than three windows is that lane-open.sh
# is itself the lane's `--initial-command`: no surface means the script never
# runs, so there is no zmx session, no client, no `stamp`, and not even the
# `vanish` fault banner — that notice lives inside the path that did not
# execute. `scruff spawn` exited 0 and the palette reported three lanes that
# were working. The prompts survived only as the launcher temp files, until
# $TMPDIR was swept.
#
# ── why an invariant suite and not a functional one ──────────────────────────
# Same reasoning as ghostty-prewarm.bats one file over. Driving the real subject
# needs Ghostty, AeroSpace, a live zmx and a display this runner can put to
# sleep; what actually broke is not behaviour under load but three decisions
# that have to stay taken. So they are pinned as text, and each assertion below
# names the failure it is standing in front of.
#
# Needs bash + bats. No Nix, no Mac, no display.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh"; }

@test "the background spawn is gated on there being a display at all" {
  # The gate itself. Without it the spawn below runs into a display count of
  # zero and hands back an error pane that reads, to everything downstream, as
  # a lane.
  run grep -qE '\[ -n "\$bg" \] && \[ "\$displays" = 0 \]' "$(SUBJECT)"
  [ "$status" -eq 0 ]
}

@test "the display count comes from hausdisp, and a machine without it still opens windows" {
  # hausdisp is the displays room's helper and its first line is
  # `active displays: N`, off the same CGGetActiveDisplayList the surface
  # failed on — so the probe and the failure ask the same question.
  grep -q 'hausdisp list' "$(SUBJECT)"
  # Fail SAFE: `displays` is 1 before anything looks, so a machine with no
  # hausdisp takes the window path it always took rather than going windowless
  # everywhere, which would be #544 all over again.
  grep -qE '^displays=1$' "$(SUBJECT)"
}

@test "the display count parses out of hausdisp, and anything else reads as a display" {
  # The one line of real logic in the gate, lifted out of the subject and run —
  # the rest of this file is text. A parse that quietly yields empty would set
  # `displays` to 1 through the fallback below and take the window path on a
  # dark desk, which is the bug with an extra step.
  #
  # ⚠️ The subject is not RUN, on purpose: lane-open.sh exports its own PATH
  # prelude with /run/current-system/sw/bin at the FRONT, so a stub `hausdisp`
  # ahead of $PATH is never the one that answers — the same trap
  # test/lane-seen.bats documents for trill. Measured here 2026-09-03 by tracing
  # the real script with a stub in place: it ran the machine's hausdisp and read
  # 1. That prelude is right for production and unshadowable from a test.
  #
  # But the sed is EXTRACTED rather than retyped, the way
  # test/raise-session-lane-join.bats lifts its subject's line: a copy would go
  # on passing after the original drifted, which is the one thing this case
  # exists to prevent. Not being able to run the script is a reason to lift the
  # line out of it, not a reason to write a second one.
  local expr
  expr="$(sed -n "s/.*displays=\"\$(hausdisp list 2>\/dev\/null | \(sed [^|]*\) | head -1)\".*/\1/p" \
    "$(SUBJECT)")"
  [ -n "$expr" ]
  parse() { eval "$expr" | head -1; }
  [ "$(printf 'active displays: 0\n' | parse)" = 0 ]
  [ "$(printf 'active displays: 1\n' | parse)" = 1 ]
  [ "$(printf 'active displays: 2  (mirrored)\n' | parse)" = 2 ]
  # And the fallback: anything that is not that line leaves it empty, and empty
  # must become 1 rather than 0.
  n="$(printf 'hausdisp: command not found\n' | parse)"
  [ -z "$n" ]
}

@test "the windowless path starts a client, and never a second one" {
  # `zmx run` on a session that already has a client starts ANOTHER — which is
  # the one thing `zmx attach`'s create-or-join cannot do, and the reason a
  # resume with the screen off has to bail before it.
  grep -qE 'session_live "\$sess" && exit 0' "$(SUBJECT)"
  grep -qE 'zmx run "\$sess" -d bash -lc "\$held"' "$(SUBJECT)"
}

@test "asking whether a session exists goes through zmx-rows.sh, never zmx by hand" {
  # AGENTS.md states it as an invariant: zmx flipped `zmx get`'s separator at
  # 0.7.0 and silently broke eight readers, so the wire format has exactly one
  # reader. `zmx list --short` is bare names TODAY and one marker away from
  # being the ninth — and both callers here fail UNSAFELY if it ever grows one:
  # the watch would fault on every lane, and the resume bail would miss and
  # start a second client in a live session.
  grep -q 'config/haus/term/zmx-rows.sh' "$(SUBJECT)"
  run bash -c "grep -vE '^[[:space:]]*#' '$(SUBJECT)' | grep -qE 'zmx (ls|list)'"
  [ "$status" -ne 0 ]
  # And the reader being absent must not be read as "no session": that answers
  # empty, which would fault a healthy lane.
  grep -qE '\[ -x "\$zmx_rows" \] \|\| return 1' "$(SUBJECT)"
  grep -qE '\[ -x "\$zmx_rows" \] \|\| exit 0' "$(SUBJECT)"
}

@test "-d goes AFTER the session name, which is not where it reads like it goes" {
  # `zmx run <name> [-d] [command…]`. Spelled `zmx run -d <name> …` — the
  # obvious order, and the order every other tool on this machine takes — zmx
  # reads `-d` as the SESSION NAME and the lane's name as its command: it
  # creates a session called "-d", never starts a client, and exits 0. That is
  # this file's own failure mode wearing a different hat, so the spelling is
  # pinned rather than trusted.
  #
  # It is the one case here that also passes against the subject as it was
  # BEFORE this block existed, and that is not a gap: an absence assertion is
  # green on a file with no `zmx run` in it at all. It guards the next edit, not
  # this one. The other eight all go red on the old file — checked, because a
  # pin nobody has watched fail is a pin nobody has tested.
  #
  # Comments are stripped first: the subject's own note NAMES the wrong order to
  # warn about it, and an assertion that cannot tell a warning from the bug is
  # an assertion that forces the warning out of the file.
  run bash -c "grep -vE '^[[:space:]]*#' '$(SUBJECT)' | grep -qE 'zmx run +-d'"
  [ "$status" -ne 0 ]
}

@test "the launcher is cleaned up on the windowless path" {
  # It is the WINDOW's script and no window is coming. Left behind it is a
  # stale executable in $TMPDIR per lane, and — worse — a second copy of the
  # lane's prompt outliving the session that is already running it.
  run grep -qE 'rm -f "\$launcher"' "$(SUBJECT)"
  [ "$status" -eq 0 ]
}

@test "the spawn probe asks whether a CLIENT started, not whether a process is alive" {
  # `kill -0` was the whole check, and it passed for all three lost lanes: a
  # Ghostty holding an error pane is a live process. The session is the honest
  # signal because every path in this script ends in one.
  grep -q 'kill -0 \$!' "$(SUBJECT)"
  grep -qE 'session_live "\$sess" && exit 0' "$(SUBJECT)"
  # And it must NOT be able to hang the palette: `scruff spawn`'s stdout is a
  # command substitution in spawn-agent.sh, so the wait is detached and both
  # fds are closed, exactly as the spawn above it is.
  grep -qE '\) >/dev/null 2>&1 &' "$(SUBJECT)"
}

@test "a lane that opened a window but no client says so out loud" {
  # The silence was the defect, not the crash. By the time the wait knows, the
  # hook's exit code has long been read as 0, so a banner is the only thing
  # left that can reach anybody — and it carries the launcher path, because
  # that file is where the lane's prompt still is.
  grep -q 'haus-notify' "$(SUBJECT)"
  grep -qE -- '--kind fault' "$(SUBJECT)"
  grep -q 'its prompt is in' "$(SUBJECT)"
}
