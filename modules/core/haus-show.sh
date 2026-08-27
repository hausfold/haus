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
# The what-your-machine-becomes diff comes later, and the place it slots into
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

# ---- palette ----------------------------------------------------------------
# The same gate, spelled the same way, as haus.sh and `bench`: escapes only when
# stdout is a TTY and NO_COLOR is unset, CLICOLOR_FORCE=1 to force them through a
# pipe, every C_* empty when off so the same printf falls back to clean text. It
# matters more here than anywhere else in the family, because this command's
# whole audience is a publisher's CI log and an agent reading a report — the two
# places a raw \033[38;5;103m is pure noise. The family standard is
# docs/cli-presentation.md in the workshop.
#
# Colour lives OUTSIDE every %-Ns width below, so alignment is identical with it
# off. Those widths are still hardcoded (44 and 46 cells, plus their gutter):
# this report is not a live region, so a narrow window soft-wraps it rather than
# corrupting it, and folding them is the shared painter's job.
if { [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; } && [ -z "${NO_COLOR:-}" ]; then
  C_OFF=$'\033[0m'
  C_FOG=$'\033[38;5;103m'   # primary accent — the fog itself
  C_OK=$'\033[38;5;108m'    # sage — current / healthy
  C_WARN=$'\033[38;5;179m'  # amber — stale / wants attention
  C_ERR=$'\033[38;5;167m'   # rose — failure
  # One grey for one role, family-wide. haus used 243 and `bench` 245 for the
  # same "secondary detail" — the closest thing to a real drift in the palette
  # audit, and two greys where the tools sit side by side on one screen.
  C_MUT=$'\033[38;5;245m'   # muted grey — secondary detail
else
  C_OFF=; C_FOG=; C_OK=; C_WARN=; C_ERR=; C_MUT=
fi

# `scrub` (defined below, beside the reasoning) strips C0 controls. It is
# applied in the HELPERS rather than at each call site: every one of these takes
# a message that can carry a source's bytes — a path, a URL, a diagnostic, a
# value — and a rule that has to be remembered per call is a rule with a hole in
# it. On haus's own ASCII literals it does nothing.
say()   { printf '%s🌫  %s%s\n' "$C_FOG" "$(printf '%s' "$*" | scrub)" "$C_OFF"; }
die()   { printf '%s✗  %s%s\n' "$C_ERR" "$(printf '%s' "$*" | scrub)" "$C_OFF" >&2; exit 2; }
field() { printf '  %s%-9s%s %s\n' "$C_FOG" "$1" "$C_OFF" "$(printf '%s' "$2" | scrub)"; }
good()  { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
bad()   { printf '  %s✗%s %s\n' "$C_ERR" "$C_OFF" "$(printf '%s' "$*" | scrub)"; }
note()  { printf '  %s⚠%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
dim()   { printf '  %s%s%s\n' "$C_FOG" "$*" "$C_OFF"; }
plural() { [ "$1" = 1 ] || printf s; }
# `leaf` is the one word in this report with an irregular plural, and the
# obvious `leaf$(plural n)` spells it "leafes".
leaves() { if [ "$1" = 1 ]; then printf leaf; else printf leaves; fi; }

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
  haus show --no-diff <src>   skip the "what your machine becomes" section

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
typed as, what it resolved to and when this run fetched it. `machine` is null
whenever this machine could not be asked — no config, a lock that needs
changes, `--no-diff`, or a file that is not a passing desktop — and otherwise
carries one verdict per leaf: changes, unchanged, overridden (your config
outranks a desktop), unranked (a recursive container's leaf, which has no
option node to rank), unknown (your haus has no such option), plus the leaves
your current desktop sets and this one does not.

The schema version does not move for it, by the rule `origin` set: a bump is
owed when an existing input's ANSWER changes, and every key a reader already
had still answers exactly what it did.

Fetching and reading are two acts, and neither can do the other's job. The
fetch reaches the network and runs nothing: it is a `git clone` or an HTTP GET
over the URL you typed, and `show` fetches a TREE rather than locking a flake,
so not even a room's own flake.nix is evaluated. The read reaches nothing: it
runs restricted, with no fetch of any scheme resolving and only the checker's
own directory and the source you named readable. An attempt to reach anything
else fails loudly and names what it reached for.

When there is a haus config at ~/.config/nix (or $HAUS_CONSUMER), a passing
desktop is also compared against THIS machine, leaf by leaf: what changes, what
your own config already outranks so the desktop cannot move it, and what the
desktop you have now sets that this one does not. That comparison evaluates YOUR
flake and never the stranger's — what crosses over is the list of option names,
not their file and not their values. It writes nothing, refuses rather than
updating your lock, and never changes the exit code: it is a leaf diff, not a
rebuild preview, and `haus plan` is still the command that builds one.

Restricted-eval's unit is the store path, so a fetched repo's desktop can read
its own siblings — the tree its publisher shipped, and nothing of yours. A
value in the report may therefore come from anywhere in that tree rather than
from the file named; the report says so.
EOF
}

json="" asroom="" subject="" pick="" nodiff=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) json=1 ;;
    --room) asroom=1 ;;
    --no-diff) nodiff=1 ;;
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
# …and then PHYSICALLY, for the same reason the subject below is resolved that
# way: `restrict-eval` judges the path Nix resolved, not the one you typed. On a
# real Mac the checker is reached through two symlinks — `/run` →
# `private/var/run`, and `sw/share/haus/desktop-check` → the store — so `-I`
# allowed the logical spelling while the interpolated `${CHECK}/read.nix`
# resolved to `/private/var/run/…` and was refused. That killed EVERY
# invocation on a machine, local source and remote alike, while the suite
# stayed green: it runs the packaged wrapper, whose checker is already a store
# path with no symlink in it. Resolved after the guard above, so the error a
# person reads still names the path they configured.
# `cd --`, and stdout discarded: a value starting with `-` would otherwise be
# read as a `cd` option, and a relative one under a set CDPATH makes `cd` echo
# the directory it landed in, which the substitution would capture as a second
# line of the path.
CHECK="$(cd -- "$CHECK" >/dev/null && pwd -P)"

# The subject's path goes into a Nix expression, so it is escaped as a Nix
# string rather than pasted. A `"` or a `${` in a directory name is enough to
# break the parse on an ordinary file — and the same hole would let a crafted
# path, or a crafted URL, inject Nix into an expression this command is about
# to evaluate.
nix_string() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g'; }

# ---- everything a stranger wrote passes through here -------------------------
# `toJSON` escapes quotes, backslashes and the three whitespace controls, and
# nothing else — so ESC survives a desktop's own values and its own attribute
# NAMES all the way to `jq -r`, which decodes it back to a raw byte. Measured:
# an accent of "\u001b[7A\u001b[2K…" reaches the terminal intact.
#
# That is not cosmetic here. `sets` is printed AFTER the class line and after
# the list of broken rules, so a file that can move the cursor can repaint
# "not a desktop — it breaks the rules below" as "a desktop — data only, and
# haus checked it". The exit code stays honest; the screen is what the audience
# reads. Step A shipped this hole with an input that had been handed to you by
# someone; a source arrives from a stranger, which is what makes it bite.
#
# Tab survives, because it is the field separator the render loops read on.
# `--json` needs none of this: jq re-escapes controls on the way out.
scrub() { LC_ALL=C tr -d '\000-\010\013\014\016-\037\177'; }

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
# Scrubbed for the same reason the report is: this text can contain a remote
# server's own bytes, quoted by Nix into an error it then prints.
whynot() {
  local m; m="$(lasterror "$1")"; [ -n "$m" ] || m="$(lastline "$1")"
  printf '%s' "$m" | scrub
}

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
  #
  # `tarball-ttl 0` is the difference between a provenance report and a stale
  # one. Nix caches a resolved ref for an hour by default, so without it a
  # `show` run minutes after a publisher pushes a fix reports the PREVIOUS rev
  # and the previous date — under a `fetched` line stamped from the clock, in
  # the freshest language the report has. Every other command here can afford a
  # cache; the one whose whole output is "where did this come from, and how old
  # is it" cannot.
  [ -n "$json" ] || printf '%s🌫  fetching %s …%s\n' "$C_FOG" "$subject" "$C_OFF" >&2
  fetched="$(
    NIX_PATH='' nix eval --impure --json \
      --option tarball-ttl 0 \
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
    # promised not to answer from the contents. `--file` is still refused
    # rather than ignored: a path that goes unvalidated because "nothing reads
    # it anyway" is a guard waiting for the day something does.
    [ -z "$pick" ] || die "--file has nothing to name in a room: --room reads nothing at all"
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

  # Three-way, because "has no revision" and "is one file" are different facts
  # and a `path:` or `tarball+` source is the pair that separates them: a
  # directory with no rev came back labelled `file`, and the report then warned
  # about a raw URL over a tree. `shape` is a documented JSON key, so a consumer
  # branches on it.
  shape="file"
  [ -d "$tree" ] && shape="tree"
  [ "$(jq -r '.rev // ""' <<<"$fetched")" = "" ] || shape="repo"
  origin="$(jq --arg typed "$subject" --arg pick "$pick" --arg shape "$shape" \
    --argjson at "$(date +%s)" \
    '{ typed: $typed, shape: $shape,
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
      --expr "import \"$(nix_string "$CHECK")/read.nix\" \"$(nix_string "$abs")\"" 2>"$err"
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

# ---- act three: ask the machine. The stranger is not in this evaluation ------
# Steps A and B answered "what is this file?". This answers "what would it do
# HERE", and it is the first thing `show` does that looks at the reader's own
# config. The rule that keeps it honest is that the candidate is not part of the
# evaluation: what crosses over from the source is a list of option NAMES — never
# the file, never a module, never a value. Its values stay on this side and are
# compared in the shell against what the machine says about those same names.
#
# Only for a desktop that PASSED. A failing file's leaf names are names the
# registry has not vouched for, and "what would this become" is not the answer to
# "this is not a desktop" anyway.
#
# `--no-update-lock-file`, not `--no-write-lock-file`. Both leave the directory
# alone; they differ on a lock that needs changes. `--no-write-lock-file`
# resolves the missing inputs in memory and answers anyway, describing a machine
# the reader has not got against pins nobody chose. `--no-update-lock-file`
# refuses and says which. That is the right answer for a command whose whole
# output is "what your machine becomes" — the same instinct as `tarball-ttl 0`
# above. (Measured: a plain `nix eval` on a consumer flake WRITES that consumer's
# lock file. This is the first act here that evaluates one, so step B's
# writes-nothing gate could not have caught it.)
#
# Advisory, always. A failure here is a line in the report and never an exit
# code: the exit code is the publisher's contract with their CI, and their CI has
# no machine to compare against.
CONSUMER="${HAUS_CONSUMER:-$HOME/.config/nix}"
machine='null'
machine_why=""
if [ -z "$nodiff" ] && [ "$class" = desktop ] && [ "$(jq -r .ok <<<"$report")" = true ] \
   && [ -f "$CONSUMER/flake.nix" ]; then
  # Values are rendered on BOTH sides by the same `toPretty`, so "did this move?"
  # is one string comparison rather than a guess about how two renderers spell a
  # list. It also sidesteps `toJSON`, which would try to copy a path-typed value
  # into the store to answer.
  #
  # The expression is a quoted heredoc with two placeholders, and not an
  # interpolated string: Nix's own `${…}` is on nearly every line of it, and a
  # shell that expanded those would be reading the reader's environment into the
  # query. The two things that ARE substituted go in as Nix STRING literals,
  # escaped exactly like the subject path is — an attrsOf key carrying a `"` or a
  # `${` is otherwise Nix, running in the reader's own evaluation.
  q="$(cat <<'NIXQ'
cfgs:
let
  wanted = "@HOST@";
  names = builtins.attrNames cfgs;
  host = if wanted != "" then wanted else (if names == [ ] then "" else builtins.head names);
in
if host == "" || !(cfgs ? ${host}) then
  { error = "this config declares no darwinConfiguration called '${if wanted == "" then "<any>" else wanted}'"; }
else
  let
    cfg = cfgs.${host};
    lib = cfg.pkgs.lib;
    pretty = lib.generators.toPretty { multiline = false; };
    render = v: let t = builtins.tryEval (pretty v); in if t.success then t.value else null;
    split = p: builtins.filter (x: builtins.isString x && x != "") (builtins.split "\\." p);
    descend =
      node: ps:
      if ps == [ ] then node
      else if !(builtins.isAttrs node) then null
      else if !(node ? ${builtins.head ps}) then null
      else descend node.${builtins.head ps} (builtins.tail ps);
    isOption = x: builtins.isAttrs x && (x._type or null) == "option";

    # The longest prefix of a path that IS an option. A leaf under one of the
    # registry's recursive containers — haus.roster.<app>.key and its siblings —
    # has no option node of its own (measured), so without this a desktop that
    # ships a scene this machine has never had would be reported as "your haus
    # has no such option", which is false and sends the reader to `haus update`
    # for a version gap that does not exist. The container is what the machine
    # actually knows about, so that is what gets named.
    container =
      ps:
      if ps == [ ] then
        null
      else
        let
          o = descend cfg.options ps;
        in
        if o != null && isOption o then ps else container (lib.lists.init ps);

    # An option node answers with a PRIORITY, and that is the whole arbitration:
    # below 900 something on this machine outranks any desktop, 900 is the
    # desktop currently selected, above it nothing is in the way. A leaf inside a
    # container can be compared by value and never by rank, which the report says
    # out loud rather than guessing. A path with neither is one this machine's
    # haus has never heard of.
    look =
      p:
      let
        ps = split p;
        o = descend cfg.options ps;
        c = descend cfg.config ps;
        holder = container ps;
      in
      if o != null && isOption o then
        {
          path = p;
          ranked = true;
          prio = o.highestPrio;
          value = render o.value;
          type = o.type.name or null;
          files = o.files;
        }
      else
        {
          path = p;
          ranked = false;
          prio = null;
          value = if c == null then null else render c;
          type = null;
          files = [ ];
          inside = if holder == null then null else builtins.concatStringsSep "." holder;
        };

    # The desktop this machine has now, read INSIDE the evaluation that named it.
    # Under lazy trees the store path handed back is a name for an
    # evaluation-time object rather than a location — three evaluations give
    # three of them and none is on disk — so reading it anywhere else would be
    # reading nothing. It is the machine's own file, so it needs no guard.
    sources = cfg.config.haus._desktop.sources or [ ];
    isBranch = x: builtins.isAttrs x && !(x ? _type);
    flat =
      pre: val:
      if isBranch val then
        builtins.concatLists (map (k: flat "${pre}.${k}" val.${k}) (builtins.attrNames val))
      else
        [ pre ];
    current =
      if sources == [ ] then
        { success = true; value = [ ]; }
      else
        builtins.tryEval (flat "haus" ((import (builtins.head sources)).haus or { }));
  in
  let
    wanted = builtins.fromJSON "@PATHS@";
    has = if current.success then current.value else [ ];
    # The leaves the desktop you HAVE sets and the candidate does not. Looked up
    # in the same pass, because "this goes back to whatever haus decides" is only
    # useful beside the value it is leaving.
    dropped = builtins.filter (p: !(builtins.elem p wanted)) has;
  in
  {
    inherit host has dropped;
    desktop = if sources == [ ] then null else builtins.baseNameOf (builtins.head sources);
    leaves = map look (wanted ++ dropped);
  }
NIXQ
)"
  q="${q//@HOST@/$(nix_string "${HAUS_HOST:-}")}"
  q="${q//@PATHS@/$(nix_string "$(jq -c '[.sets[].path]' <<<"$report")")}"
  if machine="$(
      nix eval --no-update-lock-file --json "$CONSUMER#darwinConfigurations" --apply "$q" 2>"$err"
    )"; then
    machine_why="$(jq -r '.error // ""' <<<"$machine")"
    [ -z "$machine_why" ] || machine='null'
  else
    machine_why="$(whynot "$err")"
    machine='null'
  fi
fi

# The verdicts, computed once and rendered twice. `null` whenever the machine
# could not be asked, so both renderers have exactly one thing to test.
#
#   overridden  something on this machine outranks a desktop, so the file's value
#               does not land — the single most useful line in the report, and
#               the one a reader cannot get from either file alone
#   unranked    a leaf under a recursive container, which has no option node, so
#               the values can be compared and the winner cannot be named
#   unknown     this machine's haus has no such option: the desktop was written
#               against a different one than you have pinned
#   drops       the desktop you have sets it and this one does not
becomes='null'
if [ "$machine" != null ]; then
  becomes="$(jq -n --argjson m "$machine" --argjson r "$report" '
    ($r.sets | map({ key: .path, value: .value }) | from_entries) as $want
    | ($m.leaves | map({ key: .path, value: . }) | from_entries) as $have
    | {
        host: $m.host,
        desktop: $m.desktop,
        leaves: ($r.sets | map(
          . as $s | ($have[$s.path] // null) as $h | {
            path: $s.path,
            proposed: $s.value,
            current: ($h.value // null),
            prio: ($h.prio // null),
            type: ($h.type // null),
            inside: ($h.inside // null),
            verdict: (
              if $h == null or (($h.ranked | not) and $h.inside == null) then "unknown"
              elif $h.ranked and $h.prio < 900 then "overridden"
              elif $h.value == $s.value then "unchanged"
              elif ($h.ranked | not) then "unranked"
              else "changes"
              end)
          })),
        drops: ($m.dropped | map(. as $p | { path: $p, current: (($have[$p] // {}).value // null) }))
      }')"
fi

if [ -n "$json" ]; then
  # Data on stdout, diagnostics on stderr — the rule in the workshop's
# `docs/agent-surface.md`. This
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
     --argjson machine "$becomes" \
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
    silent: (if $class == "desktop" then $report.silent else [] end),
    machine: $machine
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

# What this machine would become — step C. The frame the section slots into is
# the one above: origin, class, verdict, sets, silent, and then this.
#
# The order is by consequence, not by option name. A reader is deciding whether
# to trust a file, and the two lines that decide it are "these do not move,
# whatever the file says" and "this one turns your bar off".
render_machine() {
  local n host desktop
  [ "$becomes" = null ] && {
    # Silence when there is nothing to compare against — a publisher's CI has no
    # machine and should not be told about one. A machine that HAS a config and
    # still could not be asked gets the reason, because that is a fact about
    # their config rather than about this command.
    [ -z "$machine_why" ] || {
      printf '\n'
      note "this machine could not be compared: $machine_why"
      # Nix's own sentence for the refusal is accurate and unreadable, and it is
      # the one failure here a reader can actually do something about.
      case "$machine_why" in
        *"lock file changes"*)
          dim "Your flake.lock is not the one this machine would rebuild from, so"
          dim "a diff against it would describe pins nobody chose. 'haus update'"
          dim "or 'nix flake lock' settles it; nothing above depends on this." ;;
      esac
    }
    return 0
  }

  host="$(jq -r .host <<<"$becomes")"
  desktop="$(jq -r '.desktop // "none"' <<<"$becomes")"
  printf '\n'
  field "becomes" "$CONSUMER · host $host · desktop $desktop"

  # Every field gets a non-empty placeholder, and that is not decoration: TAB is
  # an IFS *whitespace* character, so `IFS=$'\t' read` collapses a run of them
  # and an empty field silently shifts every later one left. A leaf with no type
  # (a container's entry has none) was handing its container's name to `$type`
  # and leaving `$inside` blank — which rendered as "(inside )".
  emit() {
    jq -r --arg v "$1" '.leaves[] | select(.verdict == $v)
      | "\(.path)\t\(.current // "not set")\t\(.proposed)\t\(.type // "-")\t\(.inside // "-")"' <<<"$becomes" | scrub
  }
  count() { jq -r --arg v "$1" '[.leaves[] | select(.verdict == $v)] | length' <<<"$becomes"; }

  # 1. What the file cannot do here. First, because it is the only section a
  #    reader has no other way to learn, and because it silently un-does part of
  #    whatever the rest of the report just promised.
  n="$(count overridden)"
  if [ "$n" -gt 0 ]; then
    printf '\n'
    note "$n $(leaves "$n") your own config outranks — the desktop does not move $(if [ "$n" = 1 ]; then printf it; else printf them; fi)"
    emit overridden | while IFS=$'\t' read -r path cur prop type inside; do
      printf '      %-44s %sstays %s%s   %s(it asks for %s)%s\n' \
        "$path" "$C_FOG" "$cur" "$C_OFF" "$C_MUT" "$prop" "$C_OFF"
    done
  fi

  # 2. The changes, with the one merge rule a reader cannot infer from either
  #    file: a list your machine already ranks above the desktop is REPLACED
  #    whole rather than merged, so a desktop's entries do not add to yours.
  n="$(count changes)"
  if [ "$n" -gt 0 ]; then
    printf '\n'
    field "changes" "$n $(leaves "$n")"
    emit changes | while IFS=$'\t' read -r path cur prop type inside; do
      printf '      %-44s %s%s → %s%s' "$path" "$C_FOG" "$cur" "$prop" "$C_OFF"
      case "$type" in listOf) printf '   %s⚠ a list: replaced whole, not merged%s' "$C_WARN" "$C_OFF" ;; esac
      printf '\n'
    done
  fi

  # 3. The container leaves, where the values compare and the winner cannot be
  #    named. Said out loud: "we cannot tell you who wins here" is information
  #    and silence is not.
  n="$(count unranked)"
  if [ "$n" -gt 0 ]; then
    printf '\n'
    field "unranked" "$n $(leaves "$n") inside a list-like option"
    emit unranked | while IFS=$'\t' read -r path cur prop type inside; do
      printf '      %-44s %s%s → %s%s   %s(inside %s)%s\n' \
        "$path" "$C_FOG" "$cur" "$prop" "$C_OFF" "$C_MUT" "$inside" "$C_OFF"
    done
    dim "Entries inside a container have no option of their own to rank, so haus"
    dim "can show you the values and not which one wins. 'haus plan' settles it."
  fi

  # 4. A desktop written against a haus you have not got. Not a failure of the
  #    file — it passed the checker, which ran against the registry YOUR pin
  #    ships — so it is reported as a version gap and not as a broken desktop.
  n="$(count unknown)"
  if [ "$n" -gt 0 ]; then
    printf '\n'
    note "$n $(leaves "$n") this machine's haus has never heard of"
    emit unknown | while IFS=$'\t' read -r path cur prop type inside; do
      printf '      %-44s %s%s%s\n' "$path" "$C_ERR" "$prop" "$C_OFF"
    done
    dim "The desktop was written against a different haus than you have pinned."
    dim "'haus update' moves your pin; nothing here changes the file."
  fi

  # 5. What stops being set. The value it goes back to is NOT knowable from this
  #    machine — the module system keeps only the winning definition, so the
  #    room default underneath the current desktop is not in the tree. Say that
  #    rather than print a number nobody can stand behind.
  n="$(jq -r '.drops | length' <<<"$becomes")"
  if [ "$n" -gt 0 ]; then
    printf '\n'
    field "turns off" "$n $(leaves "$n") the desktop you have sets and this one does not"
    jq -r '.drops[] | "\(.path)\t\(.current // "—")"' <<<"$becomes" | scrub |
      while IFS=$'\t' read -r path cur; do
        printf '      %-44s %s%s → whatever haus decides%s\n' "$path" "$C_FOG" "$cur" "$C_OFF"
      done
  fi

  n="$(count unchanged)"
  if [ "$n" -gt 0 ]; then
    printf '\n'
    field "unchanged" "$n $(leaves "$n") already say what this desktop says"
  fi
  printf '\n'
  dim "A leaf diff, not a rebuild preview: turning a room off moves packages,"
  dim "files and services nothing here counts. 'haus plan' builds that answer."
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
    jq -r --arg abs "$abs" '.failures[] | ltrimstr($abs + ": ")' <<<"$report" | scrub |
      while IFS= read -r line; do printf '    %s·%s %s\n' "$C_ERR" "$C_OFF" "$line"; done
  fi
  printf '\n'

  if [ "$nsets" -eq 0 ]; then
    field "sets" "nothing at all — this is the blank desktop's shape"
  else
    field "sets" "$nsets option$(plural "$nsets") across $nrooms room$(plural "$nrooms")"
    printf '\n'
    while IFS= read -r room; do
      printf '    %s%s%s\n' "$C_OK" \
        "$(jq -r --arg r "$room" '.rooms[] | select(.room == $r) | .title' <<<"$report" | scrub)" "$C_OFF"
      jq -r --arg r "$room" '.sets[] | select(.room == $r) | "\(.path)\t\(.value)"' <<<"$report" | scrub |
        while IFS=$'\t' read -r path value; do
          printf '      %-46s %s%s%s\n' "$path" "$C_FOG" "$value" "$C_OFF"
        done
    done < <(jq -r '.rooms[].room' <<<"$report")
    # A leaf no registry namespace owns cannot survive in a PASSING desktop —
    # the checker refuses it — but a failing one is exactly where a reader wants
    # to see it rather than have it silently dropped from the listing.
    jq -r '.sets[] | select(.room == null) | "\(.path)\t\(.value)"' <<<"$report" | scrub |
      while IFS=$'\t' read -r path value; do
        printf '      %-46s %s%s%s\n' "$path" "$C_ERR" "$value" "$C_OFF"
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
    printf '            %sthose rooms stay whatever your host and haus decide%s\n' "$C_FOG" "$C_OFF"
  else
    field "silent" "nothing — it has an opinion about every room"
  fi
  render_machine
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
      bad "$(jq -r --arg abs "$abs" '.failures[0] | ltrimstr($abs + ": ")' <<<"$report" | scrub)"
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
