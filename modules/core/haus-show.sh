#!/usr/bin/env bash
# haus show — read one local desktop or room file and say what it is.
#
#   haus show ./writer.nix          a person, about to publish or about to trust
#   haus show --json ./writer.nix   the same thing for CI and agents
#
# It is the publisher's pre-share check: the class, the checker's verdict with
# every rule broken, what the file sets and what it leaves alone. It fetches
# nothing, writes nothing and activates nothing. Acquisition step A in the
# workshop's notes/rooms-desktops.md; the remote sources (B) and the
# what-your-machine-becomes diff (C) come later, and the places they slot into
# this frame are marked below so a later step extends it rather than
# reinventing it.
#
# It lives beside its evaluator in share/haus/ rather than inside haus.sh, so
# the machine's `haus show` and `nix run github:hausfold/haus#show` are the same
# file rather than two that agree today. See modules/desktop-check.nix.
set -euo pipefail

# APPENDED, unlike haus.sh's own prefix. This script needs `nix` and `jq` and
# nothing else, and the flake wrapper (`nix run …#show`) pins its own jq on the
# front for a runner that may have none — prepending here would put a system jq
# ahead of the pinned one and quietly undo that. The tail is the fallback for a
# bare login-item or sudo shell with almost nothing on PATH.
PATH="${PATH:-}:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
export PATH

# The staged evaluator: nixpkgs' lib, the room registry, the desktop rules and
# the report, all from the revision this machine pinned. The flake package bakes
# its own; on a machine the system profile's copy is the pin you actually run.
CHECK="${HAUS_DESKTOP_CHECK:-/run/current-system/sw/share/haus/desktop-check}"

say()   { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*"; }
die()   { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 2; }
field() { printf '  \033[38;5;103m%-9s\033[0m %s\n' "$1" "$2"; }
good()  { printf '  \033[38;5;108m✓\033[0m %s\n' "$*"; }
bad()   { printf '  \033[38;5;167m✗\033[0m %s\n' "$*"; }
note()  { printf '  \033[38;5;179m⚠\033[0m %s\n' "$*"; }
dim()   { printf '  \033[38;5;103m%s\033[0m\n' "$*"; }
plural() { [ "$1" = 1 ] || printf s; }

usage() {
  cat <<'EOF'
haus show — inspect a desktop or room file. Reads only; nothing is written,
fetched or applied.

  haus show <file>            what it is, whether it is a valid desktop,
                              what it sets and what it leaves alone
  haus show --room <file>     you are telling haus this file is CODE; it
                              prints the trust warning and does not even
                              evaluate the file
  haus show --json <file>     the same report as JSON on stdout

exit codes
  0  it is a desktop and it passed — or it is a room and you said --room
  1  it was checked as a desktop and it failed; every rule is listed
  2  the file could not be read, or the arguments were wrong
  3  it is code and you did not say --room, so nothing was checked

A desktop is data: a closed `{ haus = { … }; }` value whose every leaf is a
public option a shared desktop may set. A room is a nix-darwin module — code,
which haus cannot vet. `haus show` PROVES the first and only ever REPORTS the
second; it never infers that something is safe.

Under --json, `class` is one of desktop, room or unreadable, and `checked`
says whether anything was verified. `ok` is true ONLY when the checker passed;
it is null when nothing was checked, so `.ok == true` never means "we didn't
look".

Reading a desktop means EVALUATING it, and Nix evaluation can read files and
fetch URLs. So it runs restricted: no fetch of any kind resolves, and the only
paths it may read are the checker's own and the one file you named. An attempt
to reach anything else fails loudly and names what it reached for. That is a
guard, not a claim about what a ROOM does — a room is code, and the answer for
code is still "read it, or trust whoever wrote it".
EOF
}

json="" asroom="" file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) json=1 ;;
    --room) asroom=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown flag $1 — try 'haus show --help'" ;;
    *)  [ -z "$file" ] || die "one file at a time (got '$file' and '$1')"; file="$1" ;;
  esac
  shift
done

[ -n "$file" ] || { usage >&2; exit 2; }
[ -e "$file" ] || die "no such file: $file"
[ -f "$file" ] || die "$file is not a file — point at the desktop's .nix, not the directory holding it"
[ -d "$CHECK" ] || die "no desktop checker at $CHECK — this machine's haus predates 'haus show'; run 'haus update' first."

# Absolute, because the expression below is evaluated with no working directory
# of its own and a relative path in it would resolve against the store. PHYSICAL
# (`pwd -P`), because the sandbox below allows paths by name: on macOS `/var` is
# a symlink to `/private/var`, and the logical spelling of a file under it is a
# path Nix then refuses as out of bounds.
abs="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"

# The subject's path goes into a Nix expression, so it is escaped as a Nix
# string rather than pasted. A `"` or a `${` in a directory name is enough to
# break the parse on an ordinary file — and the same hole would let a crafted
# path inject Nix into an expression this command is about to evaluate.
nix_string() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g'; }

# The last non-blank line of a captured stderr, unindented — Nix puts its actual
# message there, under however many frames of trace. `|| true` because a
# no-match `grep` under `set -o pipefail` would take the caller down with it.
lastline() { { grep -v '^[[:space:]]*$' "$1" | tail -n 1 | sed 's/^[[:space:]]*//'; } || true; }

# ---- the sandbox, and why it is not optional --------------------------------
# Reading a stranger's file means EVALUATING it, and Nix evaluation is not inert:
# plain `builtins.readFile` and `builtins.fetchurl` run at eval time. Without the
# options below, `haus show` on a hostile "desktop" reads any file the user can
# read and can reach the network — during the very command they ran to decide
# whether to trust it. (Measured, not assumed: a fixture whose accent was
# `readFile ~/creds` had the secret read AND printed back in the report.)
#
#   restrict-eval   paths must be named on the search path. Both are named
#                   below, and NOTHING else is: the checker's own directory, and
#                   the one file being read. Not its parent — a stranger's file
#                   in ~/Downloads must not be able to read the rest of it.
#   allowed-uris    empty, so no fetch of any scheme resolves.
#   IFD off         a file that can BUILD during evaluation runs code, which is
#                   the thing this whole command exists to avoid doing.
#   NIX_PATH=''      cleared, or the caller's own search path silently widens
#                   what "restricted" means.
#
# What this buys, beyond the refusal itself: a blocked read is an ERROR naming
# the path the file reached for, so an attempt shows up in the report rather
# than in nobody's logs.
#
# `--room` skips all of it. You have said the file is code; evaluating it anyway
# to produce a report nobody will read would be the one thing this command
# refuses to do to a stranger's file.
report=""
class="room"
if [ -z "$asroom" ]; then
  err="$(mktemp)"
  trap 'rm -f "$err"' EXIT
  report="$(
    NIX_PATH='' nix eval --impure --json \
      --option restrict-eval true \
      --option allowed-uris '' \
      --option allow-import-from-derivation false \
      -I "$CHECK" -I "$abs" \
      --expr "import ${CHECK}/read.nix \"$(nix_string "$abs")\"" 2>"$err"
  )" || {
    # Nix's own last line, not a guess. This path is reached by a type error, a
    # blocked read, an infinite recursion and a missing input as well as by a
    # syntax error, and telling all of them "check it parses" sends the reader
    # looking in the wrong place — most misleadingly when the real answer is
    # "this file tried to read something it may not".
    die "$file could not be evaluated. Nix says:
   $(lastline "$err")"
  }
  class="$(jq -r .class <<<"$report")"
fi

# When the reader could not read it, ask Nix why — outside the `tryEval` that
# made the first pass survivable. `tryEval` returns a bool and no message, so
# the guarded evaluation cannot tell "this does not parse" from "this reached
# for a file it may not", and those two send a reader to completely different
# places. Only on the failure path, so the ordinary run still costs one eval.
reason=""
if [ "$class" = unreadable ]; then
  # `|| true` on both halves, and deliberately: this eval is EXPECTED to fail —
  # that is the whole point of running it — and `set -o pipefail` would
  # otherwise make its failure, or a `grep` that matched nothing, abort the
  # command with no output at all.
  NIX_PATH='' nix eval --impure --raw \
    --option restrict-eval true \
    --option allowed-uris '' \
    --option allow-import-from-derivation false \
    -I "$CHECK" -I "$abs" \
    --expr "builtins.deepSeq (import \"$(nix_string "$abs")\") \"read\"" \
    >/dev/null 2>"$err" || true
  reason="$(lastline "$err")"
fi

if [ -n "$json" ]; then
  # Data on stdout, diagnostics on stderr — notes/agent-surface.md's rule. This
  # is haus's first --json verb, so the envelope is the one the rest of the
  # sweep copies: a schemaVersion, and `checked` said out loud rather than left
  # to be inferred from an empty failure list.
  #
  # `ok` is NULL when nothing was checked, never `true`. A room and an
  # unreadable file are both "not a failed desktop", and a consumer reading
  # `.ok` alone must not be told they passed — `.ok == true` has to mean the
  # checker said so. `failures` still carries the reason an unreadable file had
  # no reading, because throwing that away leaves the caller with an exit code
  # and no sentence.
  jq -n --arg class "$class" --arg file "$abs" --arg reason "$reason" \
     --argjson report "${report:-null}" '{
    schemaVersion: 1,
    file: ($report.file // $file),
    class: $class,
    checked: ($class == "desktop"),
    ok: (if $class == "desktop" then $report.ok else null end),
    failures: (if $class == "room" then []
               else ($report.failures // []) + (if $reason == "" then [] else [$reason] end) end),
    sets: (if $class == "desktop" then $report.sets else [] end),
    rooms: (if $class == "desktop" then $report.rooms else [] end),
    silent: (if $class == "desktop" then $report.silent else [] end)
  }'
fi

render_room() {
  [ -n "$json" ] && return 0
  say "$file"
  printf '\n'
  field "class" "a room — this is CODE, and haus cannot check it"
  field "read" "$abs"
  printf '\n'
  note "A room is a nix-darwin module. It may install packages, write files"
  printf '    and run activation scripts as root. Nothing here vouches for it:\n'
  printf '    read it, or trust whoever wrote it.\n'
  printf '\n'
  # Step B is where origin and revision arrive; a local file has neither.
  dim "A local file has no origin and no revision — whoever handed it to you"
  dim "is the whole provenance."
}

render_desktop() {
  [ -n "$json" ] && return 0
  local ok nsets nrooms nfail room silent

  ok="$(jq -r .ok <<<"$report")"
  nsets="$(jq -r '.sets | length' <<<"$report")"
  nrooms="$(jq -r '.rooms | length' <<<"$report")"

  say "$file"
  printf '\n'
  if [ "$ok" = true ]; then
    field "class" "a desktop — data only, and haus checked it"
  else
    field "class" "not a desktop — it breaks the rules below"
  fi
  field "read" "$abs"
  printf '\n'

  if [ "$ok" = true ]; then
    good "every leaf it sets is a public option a shared desktop may set"
  else
    nfail="$(jq -r '.failures | length' <<<"$report")"
    bad "$nfail rule$(plural "$nfail") broken — this file cannot be selected as a desktop"
    printf '\n'
    # The checker names the file on every line, which is what makes it useful
    # inside a flake check over a directory of fixtures and noise here, where
    # the filename is already the second line of the report.
    jq -r --arg abs "$abs" '.failures[] | ltrimstr($abs + ": ")' <<<"$report" |
      while IFS= read -r line; do printf '    \033[38;5;167m·\033[0m %s\n' "$line"; done
  fi
  printf '\n'

  if [ "$nsets" -eq 0 ]; then
    field "sets" "nothing at all — this is the blank desktop's shape"
  else
    field "sets" "$nsets option$(plural "$nsets") across $nrooms room$(plural "$nrooms")"
    printf '\n'
    while IFS= read -r room; do
      printf '    \033[38;5;108m%s\033[0m\n' \
        "$(jq -r --arg r "$room" '.rooms[] | select(.room == $r) | .title' <<<"$report")"
      jq -r --arg r "$room" '.sets[] | select(.room == $r) | "\(.path)\t\(.value)"' <<<"$report" |
        while IFS=$'\t' read -r path value; do
          printf '      %-46s \033[38;5;103m%s\033[0m\n' "$path" "$value"
        done
    done < <(jq -r '.rooms[].room' <<<"$report")
    # A leaf no registry namespace owns cannot survive in a PASSING desktop —
    # the checker refuses it — but a failing one is exactly where a reader wants
    # to see it rather than have it silently dropped from the listing.
    jq -r '.sets[] | select(.room == null) | "\(.path)\t\(.value)"' <<<"$report" |
      while IFS=$'\t' read -r path value; do
        printf '      %-46s \033[38;5;167m%s\033[0m\n' "$path" "$value"
      done
  fi
  printf '\n'

  silent="$(jq -r '[.silent[].title] | join(" · ")' <<<"$report")"
  if [ -n "$silent" ]; then
    field "silent" "$silent"
    printf '            \033[38;5;103mthose rooms stay whatever your host and haus decide\033[0m\n'
  else
    field "silent" "nothing — it has an opinion about every room"
  fi
  # Step C turns the two lists above into "what your machine becomes": rooms on
  # and off RELATIVE to your current config, the machine-wide claims, and the
  # list-typed options a host naming the same list would replace whole.
}

case "$class" in
  room)
    render_room
    # Code, and you said so: nothing was checked, and that is the answer you
    # asked for. Without --room it is exit 3 — a publisher's CI must go red the
    # day a desktop file becomes a function, and "we checked nothing" is not a
    # pass.
    [ -n "$asroom" ] && exit 0
    exit 3
    ;;
  unreadable)
    [ -n "$json" ] || {
      say "$file"
      printf '\n'
      bad "$(jq -r --arg abs "$abs" '.failures[0] | ltrimstr($abs + ": ")' <<<"$report")"
      [ -z "$reason" ] || {
        printf '\n'
        dim "Nix says: $reason"
      }
    }
    exit 2
    ;;
  desktop)
    render_desktop
    [ "$(jq -r .ok <<<"$report")" = true ] && exit 0
    exit 1
    ;;
esac
