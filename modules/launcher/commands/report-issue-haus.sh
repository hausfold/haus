#!/bin/bash
# pounce: name = Report haus Issue
# pounce: description = Open a pre-filled bug report for haus
# pounce: icon = ladybug

# One line, because the work is `haus report`'s (modules/core/haus.sh) and it
# belongs there: the block it prefills is this machine's whole `haus doctor`
# report plus the pinned revision, macOS build, Mac model and selected desktop,
# none of which a shell script can assemble without re-deriving all of it — and
# a verb also gives the `curl | bash` user, who has no palette, the same door.
#
# ⚠️ What this file used to be is worth knowing, because it is the mistake the
# whole door exists to avoid — the same one pounce's own row made for a year
# (pkgs/pounce-commands/commands/report-issue-pounce.sh has that story). It
# hand-built `issues/new?labels=bug&title=&body=` with a markdown skeleton in
# the query, and its comment said "nothing hosted needed". That was true when it
# was written and stopped being true when the forms landed: a `body=` prefill
# opens GitHub's BLANK editor and walks straight past bug.yml — its four fields,
# its "wrong repo? file it anyway" preamble, and the `bug`/`triage` labels it
# applies. Nothing failed. Every report filed through this row simply arrived
# shapeless. It also pre-blocked the reporter's own "What happened?" with a
# skeleton, and footered the issue with `scutil --get LocalHostName`, which on a
# stock Mac is the owner's full name, in public.
#
# The form is the ONLY feedback channel haus has (there is no telemetry in
# anything we ship), so the row that opens it has to open the real one.
#
# Absolute path: pounce's daemon inherits launchd's bare PATH, so nothing here
# can assume /run/current-system/sw/bin is on it.

exec /run/current-system/sw/bin/haus report
