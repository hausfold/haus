#!/bin/bash
# zreload — bounce the current zellij server without losing its workspace.
#
# Zellij can dump tabs/panes/cwds, but killing its server necessarily kills the
# programs inside those panes. Claude Code is the important exception we can
# make seamless: a generation-scoped pane manifest records pane id -> transcript,
# so each live Claude pane becomes `claude --resume <session-id>` in the dumped
# layout even while an LSP/tool is in the foreground. Ordinary shell panes
# reopen immediately; any unclassified command pane makes the reload fail safe.
set -euo pipefail
umask 077

STATE_ROOT="${ZRELOAD_STATE_ROOT:-${HOME}/Library/Caches/org.nebelhaus.zellij-reload}"
PANE_MAP_ROOT="${ZRELOAD_PANE_MAP_ROOT:-${HOME}/.cache/claude-statusline/pane-transcripts-v2}"
LEGACY_PANE_MAP="${ZRELOAD_LEGACY_PANE_MAP:-${HOME}/.cache/claude-statusline/pane-transcripts.tsv}"
ZELLIJ_BIN="${ZRELOAD_ZELLIJ_BIN:-zellij}"
PRINT=0
ADOPT=0

usage() {
    cat <<'EOF'
usage: zreload [--print|--adopt]

Delete and recreate the current zellij session with the same tabs, panes and
working directories. Live Claude Code panes resume their exact conversations.

  --print   print the generated restart layout without reloading
  --adopt   record verified UUIDs for the current live Claude panes
EOF
}

die() {
    local message="$*"
    printf 'zreload: %s\n' "$message" >&2
    /usr/bin/osascript - "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
    display notification (item 1 of argv) with title "Zellij reload failed"
end run
APPLESCRIPT
    exit 1
}

# Runs as org.nebelhaus.zellij-reload, owned by launchd rather than by a zellij
# pane. Literally quitting and reopening Ghostty is deliberate: reload_config
# only reparses Ghostty's settings, while this workflow must also replace the
# outer launcher process that owns the terminal tty.
finish_reload() {
    local session=main
    local state_dir="${STATE_ROOT}/${session}"
    local request="${state_dir}/request"
    local layout

    [ -f "$request" ] || exit 0
    layout="$(cat "$request")"
    [ -f "$layout" ] || die "requested restart layout is missing: $layout"

    printf '[%s] quitting Ghostty before zellij reload\n' "$(date '+%H:%M:%S')" >&2
    /usr/bin/osascript -e 'tell application id "com.mitchellh.ghostty" to quit' \
        || die "Ghostty refused the quit request; zellij was left untouched"

    local stopped=0
    local _
    for _ in $(seq 1 200); do
        if ! /usr/bin/pgrep -x ghostty >/dev/null 2>&1; then
            stopped=1
            break
        fi
        sleep 0.05
    done
    [ "$stopped" = 1 ] || die "Ghostty did not quit within 10 seconds; zellij was left untouched"

    # No terminal client or old launch.sh remains now, so deleting the server
    # cannot strand the user in a raw shell. The new Ghostty process starts the
    # newly-installed launcher, which consumes REQUEST before a normal attach.
    "$ZELLIJ_BIN" delete-session --force "$session" >/dev/null 2>&1 || true

    # LaunchServices can briefly return -600 immediately after an app finishes
    # quitting even though a fresh launch is valid. Retry until the new process
    # appears instead of stranding the saved layout on that transient race.
    local reopened=0
    for _ in $(seq 1 50); do
        /usr/bin/open -a Ghostty >/dev/null 2>&1 || true
        if /usr/bin/pgrep -x ghostty >/dev/null 2>&1; then
            reopened=1
            break
        fi
        sleep 0.1
    done
    [ "$reopened" = 1 ] || die "could not reopen Ghostty; the saved layout remains at $layout"
}

if [ "${1:-}" = "_finish" ]; then
    finish_reload
    exit 0
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --print) PRINT=1 ;;
        --adopt) ADOPT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

[ -n "${ZELLIJ_SESSION_NAME:-}" ] || die "run this from inside the zellij session to reload"
SESSION="$ZELLIJ_SESSION_NAME"
case "$SESSION" in
    *[!A-Za-z0-9_.-]*) die "unsupported session name: $SESSION" ;;
esac
[ "$SESSION" = main ] || die "automatic reload is only available in the launcher-owned 'main' session"

STATE_DIR="${STATE_ROOT}/${SESSION}"
REQUEST="${STATE_DIR}/request"
LAYOUT="${STATE_DIR}/layout.kdl"
RAW="${STATE_DIR}/layout.raw.kdl"
PANES="${STATE_DIR}/panes.json"
ROLES="${STATE_DIR}/pane-roles.json"
RESTART_ROLES="${STATE_DIR}/restart-pane-roles.json"
GENERATION_FILE="${STATE_DIR}/generation"
MANIFEST="${STATE_DIR}/claude-panes.tsv"

mkdir -p "$STATE_DIR"
[ ! -e "$REQUEST" ] || die "a reload of '$SESSION' is already pending"

# Capture both views before touching the session. list-panes carries stable pane
# ids; dump-layout carries the actual tab/pane geometry. Their Claude panes are
# emitted in the same tab/pane order, which lets the transformer join them.
"$ZELLIJ_BIN" --session "$SESSION" action list-panes --all --json >"${PANES}.tmp"
"$ZELLIJ_BIN" --session "$SESSION" action dump-layout >"${RAW}.tmp"
mv -f "${PANES}.tmp" "$PANES"
mv -f "${RAW}.tmp" "$RAW"

# Never infer pane identity from `terminal_command`: zellij reports Claude's
# deepest foreground child there, so an active Swift tool can look exactly like
# a pane launched as `sourcekit-lsp`. A Claude pane is trusted only when one of
# these durable sources provides its UUID:
#   1. its command already contains `claude --resume UUID`;
#   2. the current zellij generation's explicit pane-id manifest;
#   3. claude-statusline's generation-scoped pane/transcript map.
#
# Any other active command pane is ambiguous and aborts the whole reload. Shell
# panes have terminal_command=null in list-panes and are safe to recreate. This
# deliberately prefers refusing a reload over ever replacing a Claude session
# with one of its foreground children again.
GENERATION=""
[ -f "$GENERATION_FILE" ] && GENERATION="$(cat "$GENERATION_FILE")"
MANIFEST_INPUT="$MANIFEST"
[ -f "$MANIFEST_INPUT" ] || MANIFEST_INPUT=/dev/null
MAP_INPUT=/dev/null
if [ -n "$GENERATION" ] && [ -d "${PANE_MAP_ROOT}/${GENERATION}/${SESSION}" ]; then
    MAP_INPUT="${STATE_DIR}/reported-pane-transcripts.tsv"
    : >"${MAP_INPUT}.tmp"
    for pane_file in "${PANE_MAP_ROOT}/${GENERATION}/${SESSION}/"*; do
        [ -f "$pane_file" ] || continue
        printf '%s\t%s\n' "$(basename "$pane_file")" "$(cat "$pane_file")" \
            >>"${MAP_INPUT}.tmp"
    done
    mv -f "${MAP_INPUT}.tmp" "$MAP_INPUT"
fi

# Migration path for a server that predates generation-scoped reports. A
# prompt-launched pane has a visible `claude ...` command but no --resume UUID.
# The legacy pane-id map is accepted only when the mapped transcript's own most
# recent cwd exactly equals zellij's live pane cwd, preventing a reused pane id
# from adopting an unrelated stale transcript.
TRUSTED_LEGACY="${STATE_DIR}/trusted-legacy-pane-transcripts.tsv"
: >"${TRUSTED_LEGACY}.tmp"
if [ -f "$LEGACY_PANE_MAP" ]; then
    jq -r '
      .[]
      | select(.is_plugin == false)
      | select((.terminal_command // "")
               | test("(^|/)claude([[:space:]]|$)"))
      | [.id, (.pane_cwd // "")]
      | @tsv
    ' "$PANES" |
    while IFS="$(printf '\t')" read -r pane_id pane_cwd; do
        [ -n "$pane_cwd" ] || continue
        transcript="$(
            awk -F'\t' -v id="$pane_id" '$1==id{p=$2} END{print p}' \
                "$LEGACY_PANE_MAP"
        )"
        [ -n "$transcript" ] && [ -f "$transcript" ] || continue
        transcript_cwd="$(
            tail -n 200 "$transcript" |
                jq -Rr 'fromjson? | .cwd // empty' |
                tail -n 1
        )"
        [ "$transcript_cwd" = "$pane_cwd" ] || continue
        uuid="$(basename "$transcript" .jsonl)"
        printf '%s\n' "$uuid" |
            grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' \
            || continue
        printf '%s\t%s\n' "$pane_id" "$uuid"
    done >"${TRUSTED_LEGACY}.tmp"
fi
mv -f "${TRUSTED_LEGACY}.tmp" "$TRUSTED_LEGACY"

if [ "$ADOPT" = 1 ]; then
    # Recovery/migration must trust only UUIDs visible in the live command. A
    # stale manifest is exactly what --adopt exists to replace. A prompt-launched
    # Claude pane may also use the cwd-verified legacy mapping built above.
    GENERATION=""
    MANIFEST_INPUT=/dev/null
    MAP_INPUT=/dev/null
fi

jq -Rn \
  --slurpfile panes "$PANES" \
  --rawfile manifest "$MANIFEST_INPUT" \
  --rawfile map "$MAP_INPUT" \
  --rawfile trustedLegacy "$TRUSTED_LEGACY" \
  --arg generation "$GENERATION" '
  def rows($text):
    $text
    | split("\n")
    | map(select(length > 0) | split("\t"));

  (rows($manifest)
    | map(select(length >= 3 and .[0] == $generation)
          | {key: .[1], value: .[2]})
    | from_entries) as $known
  | (rows($map)
    | map(select(length >= 2)
          | {key: .[0], value: (.[1] | split("/")[-1] | sub("[.]jsonl$"; ""))})
    | from_entries) as $reported
  | (rows($trustedLegacy)
    | map(select(length >= 2) | {key: .[0], value: .[1]})
    | from_entries) as $legacy
  | [
      $panes[0][]
      | select(.is_plugin == false)
      | .id as $id
      | (.terminal_command // "") as $command
      | (
          if (($command | test("(^|/)claude([[:space:]]|$)"))
              and
              ($command | test("([[:space:]])--resume(=|[[:space:]])[0-9a-fA-F-]{36}([[:space:]]|$)")))
          then
            $command
            | capture("([[:space:]])--resume(=|[[:space:]])(?<id>[0-9a-fA-F-]{36})([[:space:]]|$)")
            | .id
          else
            ($known[($id | tostring)]
             // $reported[($id | tostring)]
             // $legacy[($id | tostring)]
             // "")
          end
        ) as $uuid
      | {
          id: $id,
          tab: .tab_name,
          cwd: (.pane_cwd // ""),
          command: $command,
          uuid: $uuid,
          kind:
            if .title == "zreload-helper" then "helper"
            elif ($command | test("(^|/|[[:space:]])zreload([[:space:]]|$)")) then "invoker"
            elif $uuid != "" then "claude"
            elif .terminal_command == null then "shell"
            else "unsafe"
            end
        }
    ]
' >"${ROLES}.tmp"
mv -f "${ROLES}.tmp" "$ROLES"

UNSAFE="$(
    jq -r '
      [.[] | select(.kind == "unsafe")
       | "pane \(.id) in tab \(.tab): \(.command)"]
      | join("; ")
    ' "$ROLES"
)"
[ -z "$UNSAFE" ] || die \
    "cannot prove every command pane is resumable (${UNSAFE}); session left untouched"

if [ "$ADOPT" = 1 ]; then
    ADOPTED="$(jq '[.[] | select(.kind == "claude")] | length' "$ROLES")"
    [ "$ADOPTED" -gt 0 ] || die "no live claude --resume UUIDs were available to adopt"
    GENERATION="adopted-$(date +%s)-$$"
    printf '%s\n' "$GENERATION" >"${GENERATION_FILE}.tmp"
    mv -f "${GENERATION_FILE}.tmp" "$GENERATION_FILE"
    jq -r --arg generation "$GENERATION" '
      .[]
      | select(.kind == "claude")
      | "\($generation)\t\(.id)\t\(.uuid)"
    ' "$ROLES" >"${MANIFEST}.tmp"
    mv -f "${MANIFEST}.tmp" "$MANIFEST"
    printf 'zreload: adopted %s Claude pane(s); no session was restarted\n' "$ADOPTED"
    exit 0
fi

# This is the pane sequence the recreated server will contain. The hotkey helper
# disappears; a shell that invoked zreload becomes an ordinary shell again.
jq '
  [
    .[]
    | select(.kind != "helper")
    | if .kind == "invoker"
      then .kind = "shell" | .uuid = "" | .command = ""
      else .
      end
  ]
' "$ROLES" >"${RESTART_ROLES}.tmp"
mv -f "${RESTART_ROLES}.tmp" "$RESTART_ROLES"

# Rewrite actual leaf panes in the same deterministic order list-panes and
# dump-layout emit them. This does not inspect the dumped command name at all:
# the classified role attached to that pane position decides what it becomes.
perl - "$RAW" "${LAYOUT}.tmp" "$ROLES" <<'PERL'
use strict;
use warnings;
use JSON::PP qw(decode_json);

my ($input, $output, $roles_file) = @ARGV;
open my $in, '<', $input or die "$input: $!";
my @lines = <$in>;
close $in;

open my $roles_in, '<', $roles_file or die "$roles_file: $!";
my $roles_json;
{
    local $/;
    $roles_json = <$roles_in>;
}
close $roles_in;
my $roles = decode_json($roles_json);

sub block_end {
    my ($start, $indent) = @_;
    for (my $j = $start + 1; $j < @lines; $j++) {
        return $j if $lines[$j] =~ /^\Q$indent\E\}\s*$/;
    }
    die "unterminated pane block at input line " . ($start + 1) . "\n";
}

my @out;
my $actual_tabs = 1;
my $role_index = 0;

for (my $i = 0; $i < @lines; $i++) {
    my $line = $lines[$i];

    # Everything after the live tab declarations is a reusable template. Its
    # placeholder panes do not appear in list-panes and must not consume roles.
    $actual_tabs = 0
        if $line =~ /^    (?:new_tab_template|swap_(?:tiled|floating)_layout)\b/;

    # Private viewport snapshots are not part of the restart contract and point
    # into zellij's versioned internal cache.
    $line =~ s/[ \t]+contents_file="[^"]*"//g;

    if ($actual_tabs && $line =~ /^([ \t]*)(pane\b.*)$/) {
        my ($indent, $declaration) = ($1, $2);
        $declaration =~ s/\r?\n$//;
        my $has_block = $declaration =~ /\{\s*$/;

        # Leaf command panes carry command=. Leaf shell panes have no block.
        # Plugin panes and split containers both have blocks and no command=.
        my $is_terminal = ($declaration =~ /\bcommand="/) || !$has_block;
        if ($is_terminal) {
            die "more terminal panes in layout than classified roles\n"
                unless defined $roles->[$role_index];
            my $role = $roles->[$role_index++];
            my $kind = $role->{kind} // '';
            my $end = $has_block ? block_end($i, $indent) : $i;

            if ($kind eq 'helper') {
                # The off-screen Run pane exists only to invoke this script.
                $i = $end;
                next;
            }

            if ($kind eq 'invoker') {
                # A command typed in a shell becomes the ordinary shell pane it
                # replaced, never a held recursive zreload command.
                $declaration =~ s/\s+command="[^"]*"//;
                $declaration =~ s/\s+name="[^"]*"//;
                $declaration =~ s/\s*\{\s*$//;
                $declaration =~ s/\s+$//;
                push @out, $indent . $declaration . "\n";
                $i = $end;
                next;
            }

            if ($kind eq 'claude') {
                my $uuid = $role->{uuid} // '';
                die "Claude role has no UUID\n" unless length $uuid;
                $declaration =~ s/\s+command="[^"]*"/ command="claude"/
                    or die "Claude pane declaration has no command attribute\n";
                if ($declaration =~ /\s+name="[^"]*"/) {
                    $declaration =~ s/\s+name="[^"]*"/ name="claude --resume"/;
                } else {
                    $declaration =~ s/(command="claude")/$1 name="claude --resume"/;
                }
                $declaration =~ s/\s*\{\s*$//;
                $declaration =~ s/\s+$//;
                push @out, $indent . $declaration . " {\n";
                push @out, $indent . "    args \"--resume\" \"$uuid\"\n";
                push @out, $indent . "}\n";
                $i = $end;
                next;
            }
        }
    }

    push @out, $line;
}

die "classified/layout terminal pane count mismatch\n"
    unless $role_index == scalar @$roles;

open my $out, '>', $output or die "$output: $!";
print {$out} @out;
close $out;
PERL
mv -f "${LAYOUT}.tmp" "$LAYOUT"

if [ "$PRINT" = 1 ]; then
    cat "$LAYOUT"
    exit 0
fi

# The external launch agent consumes this after it has gracefully quit Ghostty.
# Write the layout first, marker last: a visible request is therefore always
# complete and bootable.
printf '%s\n' "$LAYOUT" >"${REQUEST}.tmp"
mv -f "${REQUEST}.tmp" "$REQUEST"
rmdir "${STATE_DIR}/claim" 2>/dev/null || true

# launchd, not this pane, now owns the quit -> delete -> reopen sequence.
if ! /bin/launchctl kickstart -k "gui/$(id -u)/org.nebelhaus.zellij-reload"; then
    rm -f "$REQUEST"
    die "could not start the external reload agent; session left untouched"
fi
