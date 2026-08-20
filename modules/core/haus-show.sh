#!/usr/bin/env bash
# haus show — read one desktop or room and say what it is.
#
#   haus show ./writer.nix                 a local file, about to be published
#   haus show github:ada/writer-desktop    a stranger's, about to be trusted
#   haus show --json ./writer.nix          the same thing for CI and agents
#
# It is the publisher's pre-share check and the consumer's first look: the
# origin, the class, the checker's verdict with every rule broken, what the
# file sets and what it leaves alone. It writes nothing to your machine and
# activates nothing — a remote source is fetched into the store and read there,
# and your config is never part of the evaluation.
#
# Acquisition steps A and B in the workshop's notes/rooms-desktops.md. The
# what-your-machine-becomes diff (C) comes later, and the place it slots into
# this frame is marked below so a later step extends it rather than reinventing
# it.
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
haus show — inspect a desktop or room. Reads only; nothing on your machine is
written or applied, and a remote source is fetched into the store, never into
your config.

  haus show <file>            a local .nix: what it is, whether it is a valid
                              desktop, what it sets and what it leaves alone
  haus show <source>          the same, for a source you have not got yet:
                                github:ada/writer-desktop
                                git+https://git.example.org/ada/desktop
                                file+https://example.org/writer.nix
  haus show --file <p> <src>  which file inside a fetched repo to read
  haus show --room <src>      you are telling haus this is CODE; it prints the
                              trust warning and does not evaluate anything
  haus show --json <src>      the same report as JSON on stdout

exit codes
  0  it is a desktop and it passed — or it is a room and you said --room
  1  it was checked as a desktop and it failed; every rule is listed
  2  it could not be fetched or read, or the arguments were wrong
  3  it is code and you did not say --room, so nothing was checked

A desktop is data: a closed `{ haus = { … }; }` value whose every leaf is a
public option a shared desktop may set. A room is a nix-darwin module — code,
which haus cannot vet. `haus show` PROVES the first and only ever REPORTS the
second; it never infers that something is safe.

Under --json, `class` is one of desktop, room or unreadable, and `checked`
says whether anything was verified. `ok` is true ONLY when the checker passed;
it is null when nothing was checked, so `.ok == true` never means "we didn't
look". `origin` is null for a local file, and for a source records what it was
typed as, what it resolved to and when this run fetched it.

Fetching and reading are two acts, and neither can do the other's job. The
fetch reaches the network and runs nothing: it is a `git clone` or an HTTP GET
over the URL you typed, and `show` fetches a TREE rather than locking a flake,
so not even a room's own flake.nix is evaluated. The read reaches nothing: it
runs restricted, with no fetch of any scheme resolving and only the checker's
own directory and the source you named readable. An attempt to reach anything
else fails loudly and names what it reached for.

Restricted-eval's unit is the store path, so a fetched repo's desktop can read
its own siblings — the tree its publisher shipped, and nothing of yours. A
value in the report may therefore come from anywhere in that tree rather than
from the file named; the report says so.
EOF
}

json="" asroom="" subject="" pick=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) json=1 ;;
    --room) asroom=1 ;;
    --file) shift; [ $# -gt 0 ] || die "--file needs a path inside the source"; pick="$1" ;;
    --file=*) pick="${1#--file=}" ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown flag $1 — try 'haus show --help'" ;;
    *)  [ -z "$subject" ] || die "one source at a time (got '$subject' and '$1')"; subject="$1" ;;
  esac
  shift
done

[ -n "$subject" ] || { usage >&2; exit 2; }
[ -d "$CHECK" ] || die "no desktop checker at $CHECK — this machine's haus predates 'haus show'; run 'haus update' first."

# The subject's path goes into a Nix expression, so it is escaped as a Nix
# string rather than pasted. A `"` or a `${` in a directory name is enough to
# break the parse on an ordinary file — and the same hole would let a crafted
# path, or a crafted URL, inject Nix into an expression this command is about
# to evaluate.
nix_string() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g'; }

# Nix's own sentence out of a captured stderr, not a guess.
#
# Step A used the last non-blank line, which is right for a parse error and
# wrong for a FETCH error: Nix prints its message and then appends the server's
# response body underneath it, so a 404 from GitHub came back as `}` — the last
# line of a JSON blob. The message is the last `error: …` line instead, and the
# response body is cut off first so a server cannot choose the sentence we
# print by putting `error:` in its own output.
lasterror() {
  local body
  body="$(sed '/^[[:space:]]*response body:/,$d' "$1")"
  {
    printf '%s\n' "$body" | grep -E '^[[:space:]]*error: .' | tail -n 1 |
      sed -e 's/^[[:space:]]*//' -e 's/^error: //'
  } || true
}
# The last non-blank line, for the paths where there is no `error:` line at all.
lastline() { { grep -v '^[[:space:]]*$' "$1" | tail -n 1 | sed 's/^[[:space:]]*//'; } || true; }
whynot() { local m; m="$(lasterror "$1")"; [ -n "$m" ] || m="$(lastline "$1")"; printf '%s' "$m"; }

# BSD takes an epoch after -r, GNU takes one after -d @; -r first because GNU's
# -r wants a FILE and fails loudly on a number, while BSD's -d is a different
# flag entirely and would silently print something else.
human_date() {
  date -r "$1" '+%Y-%m-%d' 2>/dev/null || date -d "@$1" '+%Y-%m-%d' 2>/dev/null || printf '%s' "$1"
}

err="$(mktemp)"
trap 'rm -f "$err"' EXIT

# ---- local path, or a source to fetch? --------------------------------------
# An explicit path spelling is always a path, even when it does not exist —
# `haus show ./typo.nix` must say "no such file", never try to fetch it. A
# scheme or a flakeref prefix is always a source. A bare word is neither, so it
# is treated as a filename and gets the file error, which is what someone who
# mistyped a path is looking at.
remote=""
case "$subject" in
  ./*|../*|/*|~/*) ;;
  http://*|https://*)
    # A bare https URL is a TARBALL flakeref to Nix, so pointing one at a .nix
    # fails with "Failed to open archive (Unrecognized archive format)" —
    # measured, and it says nothing about the prefix that is missing. Refused
    # with the spellings rather than silently rewritten: the string you type
    # here is the string `haus add` writes into flake.nix, so guessing it for
    # you would put an origin in a lock that nobody chose.
    die "a bare URL is fetched as a tarball, which is almost never what a desktop is.
   Say which shape it has:
     file+$subject      one .nix file at that URL
     git+$subject       a git repository
     tarball+$subject   an archive to unpack" ;;
  *://*|github:*|gitlab:*|sourcehut:*|flake:*|path:*) remote=1 ;;
esac

origin='null'
tree=""
if [ -z "$remote" ]; then
  [ -z "$pick" ] || die "--file names a file inside a fetched source; for a local one, point at it directly"
  [ -e "$subject" ] || die "no such file: $subject"
  [ -f "$subject" ] || die "$subject is not a file — point at the desktop's .nix, not the directory holding it"
  # Absolute, because the expression below is evaluated with no working
  # directory of its own and a relative path in it would resolve against the
  # store. PHYSICAL (`pwd -P`), because the sandbox below allows paths by name:
  # on macOS `/var` is a symlink to `/private/var`, and the logical spelling of
  # a file under it is a path Nix then refuses as out of bounds.
  abs="$(cd "$(dirname "$subject")" && pwd -P)/$(basename "$subject")"
else
  # ---- act one: fetch. Unguarded, and that is the design ---------------------
  # The read below runs under `restrict-eval` with `allowed-uris` empty, and
  # that guard refuses a fetch BY URI — measured: `builtins.fetchTree` inside it
  # dies with "access to URI … is forbidden in restricted mode". So the fetch
  # cannot happen inside the guard, and it does not need to: this expression is
  # a literal `fetchTree` over the string the user typed and imports nothing, so
  # there is nothing of the publisher's to run. A tree fetch is a clone or a
  # GET.
  #
  # `fetchTree`, deliberately, and never `nix flake lock`. Locking a source that
  # IS a flake evaluates its flake.nix to discover its own inputs — measured, a
  # room whose `inputs` throws fires at lock time — so a command that locked
  # would run a stranger's code before printing a word about it. Fetching a tree
  # does not, for a room as much as for a desktop. That is what keeps `--room`
  # honest at a remote source, and it is exactly what `haus add --room` will not
  # be able to borrow: adding means locking.
  #
  # --impure is not a weakening we chose. `fetchTree` on an unpinned ref is
  # refused outright in pure mode, and NIX_PATH is cleared because nothing here
  # should read a search path even though nothing here uses one.
  [ -n "$json" ] || printf '\033[38;5;103m🌫  fetching %s …\033[0m\n' "$subject" >&2
  fetched="$(
    NIX_PATH='' nix eval --impure --json \
      --expr "let t = builtins.fetchTree \"$(nix_string "$subject")\"; in {
        tree = t.outPath;
        rev = t.rev or null;
        lastModified = t.lastModified or null;
        narHash = t.narHash or null;
      }" 2>"$err"
  )" || die "could not fetch $subject. Nix says:
   $(whynot "$err")"

  tree="$(jq -r .tree <<<"$fetched")"

  # A `file` source's store path IS the file — a single blob named `…-source`,
  # not a directory and not called anything.nix. A repo's is a directory, and
  # then something has to say which file in it is the desktop.
  if [ -n "$asroom" ]; then
    # A room is never read, so there is no file to choose inside it. Asking
    # which .nix is the room would be asking a question this command has just
    # promised not to answer from the contents.
    abs="$tree"
  elif [ -d "$tree" ]; then
    if [ -n "$pick" ]; then
      # `..` and a leading `/` are refused rather than resolved. The guard below
      # allows the path it is handed, so a `--file ../../etc` would not escape
      # into a readable /etc so much as ASK to have it allowed.
      case "/$pick/" in
        */../*|//*) die "--file must stay inside the source: '$pick'" ;;
      esac
      [ -f "$tree/$pick" ] || die "$subject has no $pick"
      abs="$tree/$pick"
    else
      # Root-level .nix files and a conventional desktops/ directory. Exactly
      # one candidate is used and named; anything else refuses and lists, since
      # picking for someone among a publisher's desktops is the one guess with
      # a wrong answer.
      cands=()
      for f in "$tree"/*.nix "$tree"/desktops/*.nix; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = flake.nix ] && continue
        cands+=("${f#"$tree"/}")
      done
      case "${#cands[@]}" in
        1) pick="${cands[0]}" ;;
        0) die "no .nix file at the top of $subject, and no desktops/ in it — name one with --file" ;;
        *) die "$subject holds ${#cands[@]} of them — name one with --file:
$(printf '     %s\n' "${cands[@]}")" ;;
      esac
      abs="$tree/$pick"
    fi
  else
    abs="$tree"
  fi

  origin="$(jq --arg typed "$subject" --arg pick "$pick" --argjson at "$(date +%s)" \
    '{ typed: $typed, shape: (if .rev == null then "file" else "repo" end),
       file: (if $pick == "" then null else $pick end),
       tree: .tree, rev: .rev, lastModified: .lastModified, narHash: .narHash,
       fetchedAt: $at }' <<<"$fetched")"
fi

# ---- act two: read. Guarded, and why that is not optional --------------------
# Reading a stranger's file means EVALUATING it, and Nix evaluation is not inert:
# plain `builtins.readFile` and `builtins.fetchurl` run at eval time. Without the
# options below, `haus show` on a hostile "desktop" reads any file the user can
# read and can reach the network — during the very command they ran to decide
# whether to trust it. (Measured, not assumed: a fixture whose accent was
# `readFile ~/creds` had the secret read AND printed back in the report.)
#
#   restrict-eval   paths must be named on the search path. Both are named
#                   below, and NOTHING else is: the checker's own directory, and
#                   the one source being read.
#   allowed-uris    empty, so no fetch of any scheme resolves. Whatever was
#                   fetched has already been fetched; this act adds nothing.
#   IFD off         a file that can BUILD during evaluation runs code, which is
#                   the thing this whole command exists to avoid doing.
#   NIX_PATH=''      cleared, or the caller's own search path silently widens
#                   what "restricted" means.
#
# ⚠️ The UNIT of that allowance is the store path, not the file — measured. A
# local file gets exactly itself and not its parent, which is the point: a
# stranger's file in ~/Downloads must not read the rest of it. A file inside the
# store gets its whole store root, so a fetched repo's desktop CAN read the
# siblings its publisher shipped beside it. It still cannot read another store
# path, and it still cannot read anything outside the store, which was the
# load-bearing half. What it costs is attribution: a value in the report may
# have come from anywhere in that tree, so the report names the tree.
#
# What this buys, beyond the refusal itself: a blocked read is an ERROR naming
# the path the file reached for, so an attempt shows up in the report rather
# than in nobody's logs.
#
# `--room` skips all of it. You have said the source is code; evaluating it
# anyway to produce a report nobody will read would be the one thing this
# command refuses to do to a stranger's file.
report=""
class="room"
if [ -z "$asroom" ]; then
  report="$(
    NIX_PATH='' nix eval --impure --json \
      --option restrict-eval true \
      --option allowed-uris '' \
      --option allow-import-from-derivation false \
      -I "$CHECK" -I "$abs" \
      --expr "import ${CHECK}/read.nix \"$(nix_string "$abs")\"" 2>"$err"
  )" || {
    # Nix's own sentence, not a guess. This path is reached by a type error, a
    # blocked read, an infinite recursion and a missing input as well as by a
    # syntax error, and telling all of them "check it parses" sends the reader
    # looking in the wrong place — most misleadingly when the real answer is
    # "this file tried to read something it may not".
    die "$subject could not be evaluated. Nix says:
   $(whynot "$err")"
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
  reason="$(whynot "$err")"
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
  #
  # `origin` is new in step B and the version did NOT move with it. A bump is
  # owed when an existing input's answer changes; this is a key that is `null`
  # for every input schemaVersion 1 could accept, and non-null only for sources
  # that used to be an error. Nobody's reader breaks, so nobody is made to
  # update one.
  jq -n --arg class "$class" --arg file "$abs" --arg reason "$reason" \
     --argjson origin "$origin" \
     --argjson report "${report:-null}" '{
    schemaVersion: 1,
    file: ($report.file // $file),
    origin: $origin,
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

# Where it came from, and how old that is. A local file has no origin at all —
# whoever handed it to you is the whole provenance — and the two remote shapes
# differ in what they can even be asked.
render_origin() {
  local rev lm shape
  if [ "$origin" = null ]; then
    field "read" "$abs"
    return 0
  fi
  shape="$(jq -r .shape <<<"$origin")"
  rev="$(jq -r '.rev // ""' <<<"$origin")"
  lm="$(jq -r '.lastModified // ""' <<<"$origin")"

  field "origin" "$(jq -r .typed <<<"$origin")"
  if [ -n "$rev" ]; then
    field "revision" "$rev"
    # The SOURCE's date, said as the source's. `lastModified` on a git node is
    # the commit's own timestamp — measured, it equals the committer date to the
    # second — so it answers "how stale is this thing", never "how old is my
    # copy". Nothing in a lock file records the second question.
    field "changed" "$(human_date "$lm") — the source's own date, not this fetch's"
  else
    field "revision" "none — this shape has no revision and no date of any kind"
  fi
  field "fetched" "$(human_date "$(jq -r .fetchedAt <<<"$origin")") — stamped here, by the clock"
  if [ -n "$asroom" ]; then
    # Nothing was read, and saying which file WOULD have been read is the
    # inference this command refuses to make about code.
    field "read" "nothing — you said this is code, so nothing was evaluated"
  elif [ -n "$(jq -r '.file // ""' <<<"$origin")" ]; then
    field "read" "$(jq -r .file <<<"$origin"), out of the fetched tree"
  else
    field "read" "the fetched file"
  fi
  field "tree" "$tree"
  if [ "$shape" = file ]; then
    printf '\n'
    note "A raw URL pins content and nothing else. There is no revision to"
    printf '    compare and no date to age, and `nix flake update` on one prints the\n'
    printf '    same URL on both sides of its arrow while the content moves — a line\n'
    printf '    that reads as confirmation nothing changed. A repo source can be\n'
    printf '    diffed; this one can only be re-downloaded.\n'
  fi
}

render_room() {
  [ -n "$json" ] && return 0
  say "$subject"
  printf '\n'
  field "class" "a room — this is CODE, and haus cannot check it"
  render_origin
  printf '\n'
  note "A room is a nix-darwin module. It may install packages, write files"
  printf '    and run activation scripts as root. Nothing here vouches for it:\n'
  printf '    read it, or trust whoever wrote it.\n'
  printf '\n'
  if [ "$origin" = null ]; then
    dim "A local file has no origin and no revision — whoever handed it to you"
    dim "is the whole provenance."
  else
    dim "Fetched, not locked — nothing in it has been evaluated, not even its"
    dim "own flake.nix. Pinning it with 'haus add' would be: locking a flake"
    dim "input reads that flake. That is a different decision, and it will get"
    dim "a different prompt."
  fi
}

render_desktop() {
  [ -n "$json" ] && return 0
  local ok nsets nrooms nfail room silent

  ok="$(jq -r .ok <<<"$report")"
  nsets="$(jq -r '.sets | length' <<<"$report")"
  nrooms="$(jq -r '.rooms | length' <<<"$report")"

  say "$subject"
  printf '\n'
  if [ "$ok" = true ]; then
    field "class" "a desktop — data only, and haus checked it"
  else
    field "class" "not a desktop — it breaks the rules below"
  fi
  render_origin
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
    # Attribution, not decoration. The guard's unit is the store path, so a
    # fetched desktop could have read any file its publisher shipped beside it,
    # and a reader comparing this report against the one file on GitHub would
    # otherwise have no way to know that.
    [ -n "$tree" ] && [ -d "$tree" ] && {
      printf '\n'
      dim "Values are attributed to the fetched TREE, not to one file in it: a"
      dim "desktop may read its own siblings, and this one could have."
    }
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
      say "$subject"
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
