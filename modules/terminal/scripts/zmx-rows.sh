#!/bin/bash
# zmx-rows.sh — the one reader for the `zmx ls` wire format.
#
# Usage:
#   zmx-rows.sh <fields> [k=v ...]           over `zmx ls`  (every session)
#   zmx-rows.sh --get <session> <fields>     over `zmx get` (one session, labels)
#
#   <fields>  comma-separated keys, one TSV column each, in the order asked.
#             A key the row does not carry is an EMPTY column — the column
#             count is stable whatever zmx grows or drops, so a caller's $2
#             stays $2.
#   k=v       keep only rows whose value for k is exactly v; several are
#             ANDed. A missing key compares as the empty string, so `window=`
#             means "rows with no window label".
#
# stdout: clean TSV, one row per session, in zmx's own order (sorted by name —
# scripts/focused-session.sh leans on that order, so it is part of the
# contract). Exit 0 always: no zmx, no daemon and no match all answer EMPTY —
# the haus-notify degrade direction, where a machine without the tool gets
# silence rather than an error. A malformed CALL (no fields, a filter without
# "=") is a caller bug, not a runtime fact, and exits 1 with nothing printed.
#
# ── the wire format, in one place ────────────────────────────────────────────
# `zmx ls` emits one session per line: TAB-separated k=v fields — the fields
# zmx keeps itself (name, pid, clients, created, start_dir, cmd) followed by
# the session's labels (state=, client=, window=, lwindow=, …), the same k=v
# shape. `zmx get <session>` emits the labels alone — but SPACE-separated on
# one line in zmx 0.7.0, where older zmx used tabs. That flip is why --get
# splits on whitespace RUNS, which reads both eras: a label value cannot carry
# whitespace, because `zmx set` truncates it at the first space (measured
# 2026-09-02 — "a b" stores "a"). It is also why the two hand parses of `zmx
# get` this file replaced had been silently answering EMPTY for every key
# since 0.7.0: both split on tabs that are no longer there. Three more traps,
# each re-derived by hand — ~10 awk/sed programs in 8 files across three
# rooms — until this file:
#
#   · zmx marks the row you are ATTACHED to in its FIRST field ("→ name=…";
#     an unattached row carries two glued spaces, "  name=…"). The marker
#     arrives glued to that first key, so a parse that does not strip it
#     loses exactly the session you are sitting in.
#   · A value may carry "=" (a label is whatever a client wrote), so a key
#     ends at the FIRST "=" and the value is everything after it, verbatim.
#   · The directory is `start_dir` in zmx 0.7.0; older zmx called it `cwd`
#     and wrapped it in a file:// URL with a host in it ("file://Mac/Users/…").
#     Reading one spelling is what silently broke ⌘↵ across the rename. Ask
#     for the derived field `dir` and both are handled: start_dir, else cwd,
#     any URL prefix stripped — `dir` is always this derivation, never a raw
#     zmx field, even if zmx ever grows one by that name. (It is where the
#     session was BORN, not where it is now — a caller that wants the live
#     directory still resolves it off `pid`; lanes/lane-cwd.sh does.)
#
# What this file does NOT know is what any name or label MEANS. The `scruff.`
# session prefix is scruff's to interpret, `window=` vs `lwindow=` is the
# window layer's discriminator — callers keep their semantics and take only
# the parse from here.
#
# One invocation is one `zmx ls`, and that costs a socket round-trip per
# session — so a caller with several questions asks for several columns in
# ONE call (scripts/focused-session.sh reads name plus both window keys that
# way), never once per question.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

get=""
if [ "${1:-}" = "--get" ]; then
  get="${2:-}"
  [ -n "$get" ] || exit 1
  shift 2
fi

fields="${1:-}"
[ -n "$fields" ] || exit 1
shift

filters=""
for f in "$@"; do
  case "$f" in
    *=*) filters="$filters$f"$'\t' ;;
    *) exit 1 ;;
  esac
done

# The zmx to read. An override for the suite alone (test/zmx-rows.bats), the
# way awake.sh takes AWAKE_DATE_BIN: the PATH prelude above puts the system
# profile FIRST, so a stub earlier on a caller's PATH could never win.
ZMX="${HAUS_ZMX_BIN:-zmx}"
command -v "$ZMX" >/dev/null 2>&1 || exit 0

# ENVIRON rather than -v, twice over: -v is a piece of awk SOURCE, so macOS's
# one-true-awk dies on a value carrying a newline (measured — the bug
# test/raise-session-lane-join.bats pins) and quietly rewrites backslash
# escapes in one that does not. ENVIRON hands both through byte-for-byte.
#
# NO APOSTROPHES in the awk body, comments included: it is one single-quoted
# shell string, so a lone one ends it. `bash -n` catches it; nothing else does.
{
  if [ -n "$get" ]; then
    "$ZMX" get "$get" 2>/dev/null
  else
    "$ZMX" ls 2>/dev/null
  fi
} | ZR_FIELDS="$fields" ZR_FILTERS="$filters" ZR_GET="$get" awk '
  BEGIN {
    # ls is TAB-separated and its values may carry spaces (cmd=bash -lc…);
    # get is whitespace-separated (spaces since 0.7.0, tabs before) and its
    # values cannot carry either — see the header.
    FS = (ENVIRON["ZR_GET"] != "" ? "[ \t]+" : "\t")
    ncol = split(ENVIRON["ZR_FIELDS"], col, ",")
    nflt = 0
    n = split(ENVIRON["ZR_FILTERS"], raw, "\t")
    for (i = 1; i <= n; i++) {
      if (raw[i] == "") continue
      p = index(raw[i], "=")
      nflt++
      fk[nflt] = substr(raw[i], 1, p - 1)
      fv[nflt] = substr(raw[i], p + 1)
    }
  }
  {
    split("", f)
    seen = 0
    for (i = 1; i <= NF; i++) {
      p = index($i, "=")
      if (p == 0) continue
      k = substr($i, 1, p - 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      # the attached-row marker, glued to the first key
      sub(/^[^A-Za-z_]*/, "", k)
      if (k == "") continue
      f[k] = substr($i, p + 1)
      seen = 1
    }
    if (!seen) next
    d = (f["start_dir"] != "" ? f["start_dir"] : f["cwd"])
    sub(/^file:\/\/[^\/]*/, "", d)
    f["dir"] = d
    for (i = 1; i <= nflt; i++) if (f[fk[i]] != fv[i]) next
    row = ""
    for (i = 1; i <= ncol; i++) row = row (i > 1 ? "\t" : "") f[col[i]]
    print row
  }
'
exit 0
