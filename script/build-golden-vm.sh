#!/usr/bin/env bash
# build-golden-vm.sh — bake the macOS image agent lanes clone from.
#
#   ./script/build-golden-vm.sh [--base tahoe-base] [--name haus-golden]
#                               [--ref v2026.08.22] [--desktop hacker] [--keep]
#
# `scruff runtime up <lane> --backend tart` clones an image and boots it headless
# (modules/ai/runtime/tart-adapter.sh). Which image is the whole question: a
# bare cirruslabs base has no Nix and no haus in it, so a lane that clones one
# has nothing to test. This script produces the other end — a stopped VM with
# the desktop already raised, the permission prompts already answered and the
# first-run alerts already cleared — so a clone is testable the second it boots.
#
# Run it on a Mac with `tart` on PATH and the base image already pulled. It is
# slow (a full Nix install plus a darwin-rebuild inside a VM) and unattended.
#
# ---------------------------------------------------------------------------
# The one thing to understand before changing this
#
# Everything here works because the cirruslabs base ships with **SIP disabled**
# (`csrutil status: disabled`) and an auto-login console session. That is what
# lets `screencapture` and `osascript` run over SSH at all, and what lets the
# quiet pass WRITE a TCC grant rather than merely request one. Build the golden
# image from some other macOS — a hand-installed one, an MDM-managed one — and
# every step below dies on a modal nobody can click.
#
# Measured on a Tahoe 26.6.2 guest, 2026-08-22 (the workshop's `docs/agent-vm.md`):
#
#   - A TCC prompt does not BLOCK. The row is written `auth_value = 2` at the
#     same instant the dialog appears, so the command returns real data while
#     the modal sits there unanswered forever. One prompt per (service, client)
#     on first use, not per call.
#   - So the cost of skipping the quiet pass is not a broken VM — it is a
#     desktop with nine unanswered dialogs stacked on it, in front of whatever
#     the agent was sent to look at.
set -euo pipefail

BASE="${HAUS_VM_BASE:-tahoe-base}"
NAME="${HAUS_VM_NAME:-haus-golden}"
REF="${HAUS_VM_REF:-}"
DESKTOP="${HAUS_VM_DESKTOP:-hacker}"
GUEST_USER="${HAUS_VM_USER:-admin}"
KEEP=

# ${VAR} inside these, never $VAR, whenever the next character is one of this
# file's ellipses or em dashes. bash reads a multi-byte character as part of the
# identifier, so `say "… haus $REF…"` looks up a variable named REF… — which
# under `set -u` is an unbound-variable death forty minutes into a build, and
# without it a silently empty word. Cost one real run to find.
say()  { printf '\033[38;5;103m≋  %s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m⚠  %s\033[0m\n' "$*"; }
die()  { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base)    BASE="${2:?--base needs an image name}"; shift 2 ;;
    --name)    NAME="${2:?--name needs an image name}"; shift 2 ;;
    --ref)     REF="${2:?--ref needs a git tag or rev}"; shift 2 ;;
    --desktop) DESKTOP="${2:?--desktop needs a name}"; shift 2 ;;
    --keep)    KEEP=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown flag $1 — try --help" ;;
  esac
done

# ---- preflight -------------------------------------------------------------
# Every check here is one a failure 40 minutes into a build would have made
# for us anyway, at 40 minutes' cost.
command -v tart >/dev/null 2>&1 || die "tart isn't on PATH — nix shell nixpkgs#tart, or install it"

tart list --quiet 2>/dev/null | grep -qx "$BASE" \
  || die "no base image $BASE — \`tart pull ghcr.io/cirruslabs/macos-tahoe-base:latest\` then \`tart rename\` it, or pass --base"

if tart list --quiet 2>/dev/null | grep -qx "$NAME"; then
  die "$NAME already exists — \`tart delete $NAME\` to rebuild it (the old image is the only copy; export it first if you want it)"
fi

# A full clone plus a Nix store lands around 25-30 GB. Refusing here beats
# filling the disk of the machine the user is sitting at.
free_gb=$(df -g /System/Volumes/Data | awk 'NR==2 {print $4}')
[ "${free_gb:-0}" -ge 40 ] \
  || die "only ${free_gb}GB free — a golden image needs ~30GB plus room to write. \`tart list\` and delete something first"

# Pin the ref: an image built from "whatever main was" cannot be rebuilt, and
# the whole point of a golden image is that a lane's failure is the lane's.
if [ -z "$REF" ]; then
  REF=$(git -C "$(dirname "$0")/.." describe --tags --abbrev=0 2>/dev/null || true)
  [ -n "$REF" ] || die "couldn't resolve a tag — pass --ref v2026.08.22"
  say "no --ref given; pinning to this checkout's latest tag: $REF"
fi

# BatchMode matters more than it looks: without it a key that stopped working
# turns this into an ssh password prompt nobody is at the keyboard to answer,
# and the "unattended" build hangs until it is noticed. Same reasoning puts
# `sudo -n` in every guest heredoc below — sudo's stdin here IS the script, so
# a sudo that decided to prompt would eat the remaining lines as passwords.
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=10 -o BatchMode=yes)

# guest — run a script on the VM, reading it from stdin. A heredoc rather than
# an argument so nothing goes through two rounds of shell quoting: a lane name
# or a store path with a space in it is a string here, never re-parsed.
guest() { ssh "${SSH_OPTS[@]}" "$GUEST_USER@$IP" bash -s; }

cleanup_on_fail() {
  [ -n "${BUILT:-}" ] && return 0
  warn "build did not finish — $NAME is left in place for inspection"
  warn "  tart ip $NAME · ssh $GUEST_USER@\$(tart ip $NAME) · tart delete $NAME --force"
}
trap cleanup_on_fail EXIT

# ---- 1. clone and boot -----------------------------------------------------
say "cloning $BASE → $NAME (APFS copy-on-write, seconds)…"
tart clone "$BASE" "$NAME"

say "booting $NAME headless…"
# --no-graphics gives a full WindowServer with nothing rendered to the host
# display — the entire reason this is safe to run while someone is using the
# Mac. Backgrounded because `tart run` blocks until the VM stops.
tart run "$NAME" --no-graphics &
TART_PID=$!
# NOT disowned, unlike tart-adapter.sh's copy of this line. That script has to
# return while the VM keeps running; this one has to WAIT for the VM to finish
# shutting down before it says the image is ready, or the next thing anyone
# does is clone a disk that is still being written.

IP=$(tart ip "$NAME" --wait 120) || die "$NAME never got an IP"
say "$NAME is up at $IP"

say "waiting for sshd…"
for _ in $(seq 1 60); do
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$GUEST_USER@$IP" true 2>/dev/null && break
  sleep 5
done
ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$GUEST_USER@$IP" true 2>/dev/null \
  || die "no passwordless SSH to $GUEST_USER@$IP — the base image is meant to carry the key"

# ---- 2. raise the house ----------------------------------------------------
# The PINNED raw URL, never hausfold.co/hacker.sh: the worker resolves the
# latest release tag, which drifts, and an image nobody can rebuild is not
# golden.
say "running bootstrap.sh @ $REF (--defaults --desktop $DESKTOP) — this installs Nix; expect a long quiet stretch…"
guest <<EOS
set -euo pipefail
curl -fsSL "https://raw.githubusercontent.com/hausfold/haus/$REF/bootstrap.sh" -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh --defaults --desktop "$DESKTOP"
EOS

# --defaults scaffolds and stops: bootstrap only offers to raise the house when
# it has a terminal to ask on. So the build and the switch are ours.
#
# The pin is written into the guest's own flake rather than passed as
# --override-input, which would be the obvious thing and is the wrong thing:
# --override-input implies --no-write-lock-file, so the image would ship with
# NO flake.lock and bootstrap's unpinned `github:hausfold/haus`. The system
# would be $REF and the first `haus rebuild` inside a clone would resolve
# whatever main is by then — the exact drift --ref exists to prevent.
say "pinning the guest's config to haus ${REF}…"
guest <<EOS
set -euo pipefail
cd ~/.config/nix
sed -i '' 's|github:hausfold/haus"|github:hausfold/haus/$REF"|' flake.nix
grep -q 'github:hausfold/haus/$REF' flake.nix || { echo "pin did not take — bootstrap's flake.nix shape changed" >&2; exit 1; }
EOS

# Two things an unattended first switch trips over that an interviewed one
# does not. Both were found by running this script, not by reading it.
say "building and switching the guest…"
guest <<'EOS'
set -euo pipefail

# 1. home-manager BACKS UP files, it does not clobber them, so a dotfile the
#    base image already shipped aborts the whole switch. bootstrap.sh's
#    preflight prints these and tells a human to move them — nobody is here to
#    read that. The cirruslabs base ships ~/.zprofile (Homebrew's shellenv) and
#    a ~/.profile symlink to it, which is exactly the pair it names.
for f in .profile .zprofile .zshrc .zshenv .bashrc .bash_profile; do
  if [ -e ~/"$f" ] || [ -L ~/"$f" ]; then mv ~/"$f" ~/"$f.pre-haus"; fi
done

source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
host=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
cd ~/.config/nix
nix build ".#darwinConfigurations.$host.system"

# 2. HOMEBREW_MAKE_JOBS=1 — felixkratz/formulae's sketchybar has no bottle for
#    macOS 26, so a fresh Tahoe machine builds it from source, and its parallel
#    make races on a bin/ dir that another job is still creating:
#      error: unable to open output file 'bin/background.o'
#    Serially it builds in 13 seconds. This is a REAL haus install bug, not a
#    VM artifact — a person running the installer on a fresh Tahoe Mac hits it
#    too — and the workaround lives here only so a forty-minute image build
#    doesn't die at the last step while that is fixed properly upstream.
sudo -n HOMEBREW_MAKE_JOBS=1 ./result/sw/bin/darwin-rebuild switch --flake ".#$host"
EOS

# ---- 3. the quiet pass -----------------------------------------------------
# What the first boot leaves on the desktop, and what each part of this
# removes, is in the workshop's `docs/agent-vm.md`. Order matters: grant first
# (so nothing new is posted), then click what is already up, then wipe the
# notification store.
say "quiet pass — pre-granting TCC, clearing first-run alerts…"

# 3a. TCC. Written directly because there is no other way: the sleepwatcher
# prompt's only dismissing button is "Deny", which is the wrong answer, and a
# grant that has to be clicked is a grant a headless image cannot have.
#
# `sshd-keygen-wrapper` is the client for anything an agent runs over SSH.
# sleepwatcher is haus's own (AeroSpace's on-wake watcher, modules/windows/
# default.nix:698) and it asks for keystroke access on first login.
#
# ⚠️ The sleepwatcher row is keyed to a /nix/store path, so it is valid only
# for the haus rev this image was built from — exactly like a TCC grant keyed
# to a Homebrew Cellar path. That is survivable here and only here: the image
# is a snapshot, and moving haus means rebuilding it, which re-runs this.
guest <<'EOS'
set -euo pipefail
db="/Library/Application Support/com.apple.TCC/TCC.db"

# Never fatal. A schema that moved under us is worth a warning and a dirty
# image reported by step 4 — not throwing away a build that is already forty
# minutes deep and otherwise good.
grant() { # $1 service, $2 client path, $3 optional Apple-Events target bundle id
  local target="${3:-UNUSED}" ttype=NULL
  [ "$target" = UNUSED ] || ttype=0
  sudo -n sqlite3 "$db" "INSERT OR REPLACE INTO access
    (service, client, client_type, auth_value, auth_reason, auth_version,
     indirect_object_identifier_type, indirect_object_identifier, boot_uuid)
    VALUES ('$1', '$2', 1, 2, 0, 1, $ttype, '$target', 'UNUSED');" \
    || echo "⚠ could not grant $1 to $2" >&2
}
for s in kTCCServiceScreenCapture kTCCServicePostEvent kTCCServiceAccessibility; do
  grant "$s" /usr/libexec/sshd-keygen-wrapper
done

# AppleEvents is the odd one, in two ways that each cost an hour to find.
#
# Its rows key on (client, TARGET bundle id), not on the client alone — so a
# grant for System Events does nothing when the next line drives Terminal, and
# you get a fresh prompt per app you touch. Grant every target this image will
# ever be driven through.
#
# And the CLIENT is not who you would guess. The dialog macOS puts up says
# "bash" — the shell the ssh session spawned — not sshd-keygen-wrapper and not
# osascript. Grant all of them; a row that turns out to be inert costs nothing,
# a missing one costs a hung build.
for client in /bin/bash /bin/zsh /usr/bin/osascript \
              /usr/libexec/sshd-keygen-wrapper /usr/libexec/sshd-session; do
  for target in com.apple.systemevents com.apple.Terminal com.apple.finder; do
    grant kTCCServiceAppleEvents "$client" "$target"
  done
done
sw=$(pgrep -fl sleepwatcher | awk '{print $2}' | head -1 || true)
if [ -n "$sw" ]; then
  grant kTCCServiceAccessibility "$sw"
  grant kTCCServiceListenEvent   "$sw"
  echo "granted sleepwatcher at $sw"
else
  echo "sleepwatcher not running — its prompt will appear on a later boot" >&2
fi
sudo -n killall tccd 2>/dev/null || true

# The order of this pass is not cosmetic. A prompt that is ALREADY on screen
# blocks every later request from the same client — writing the grant row
# underneath it does not dismiss it, and the next `osascript` hangs forever
# rather than failing. So the grants go first, and if one slipped through
# anyway, the pending dialog has to be taken out by killing the process that
# draws it. (Kill the blocked requester too: while it lives, the request is
# still queued and the dialog comes straight back.)
pkill -f /usr/bin/osascript 2>/dev/null || true
killall UserNotificationCenter 2>/dev/null || true
sleep 2
EOS

# 3b. Click away whatever is already on screen. Six of the nine alerts on the
# first VM to get this far were document-type and permission dialogs owned by
# these two processes, and every one of them is reachable this way.
guest <<'EOS'
set -euo pipefail
/usr/bin/osascript <<'AS' || true
on sweep(procName, prefs)
  tell application "System Events"
    if not (exists process procName) then return
    tell process procName
      repeat 10 times
        set clicked to false
        repeat with w in windows
          repeat with p in prefs
            try
              -- `contents of p`: `repeat with p in prefs` binds a REFERENCE
              -- into the list, and `button p of w` wants the string. Inside a
              -- try, getting that wrong is zero clicks and no error.
              set pname to contents of p
              if exists (button pname of w) then
                click button pname of w
                set clicked to true
                exit repeat
              end if
            end try
          end repeat
        end repeat
        delay 0.6
        if not clicked then exit repeat
      end repeat
    end tell
  end tell
end sweep
sweep("UserNotificationCenter", {"Allow"})
sweep("CoreServicesUIAgent", {"Keep “QuickTime Player”", "Keep “Zen”", "Keep “TV”", "Keep"})
AS
EOS

# 3c. Notification banners. They survive a `killall NotificationCenter` —
# they are re-rendered from the delivered-notification store — so the store is
# what has to go. Verified: this is what took the last two banners off the
# desktop when clicking could not.
guest <<'EOS'
set -euo pipefail
rm -f ~/Library/Group\ Containers/group.com.apple.usernoted/db2/db*
killall usernoted 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true

# The base image boots with a Terminal window full of somebody else's
# scrollback (cirruslabs' own provisioning, restored by Terminal's
# resume-windows). `killall` rather than an AppleScript `close every window`:
# quitting an app needs no Apple Events, so this works even if every grant
# above turned out to be inert.
defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true
killall Terminal 2>/dev/null || true
sleep 4
EOS

# ---- 4. prove it, then park it ---------------------------------------------
say "verifying — anything still holding a window?"
leftovers=$(guest <<'EOS'
/usr/bin/osascript <<'AS' 2>/dev/null || true
tell application "System Events"
  set out to ""
  repeat with p in every process
    try
      repeat with w in windows of p
        if (description of w) contains "dialog" or (subrole of w as text) is "AXSystemDialog" then
          set out to out & (name of p) & " · " & (description of w) & linefeed
        end if
      end repeat
    end try
  end repeat
  return out
end tell
AS
EOS
)
if [ -n "$leftovers" ]; then
  warn "dialogs still on the guest's screen:"
  printf '%s\n' "$leftovers" | sed 's/^/    /'
  warn "every clone of this image inherits them — see the workshop's docs/agent-vm.md"
else
  say "clean desktop"
fi

BUILT=1
if [ -n "$KEEP" ]; then
  say "leaving $NAME running at $IP (--keep)"
else
  say "stopping ${NAME}…"
  tart stop "$NAME" 2>/dev/null || true
  wait "$TART_PID" 2>/dev/null || true
fi

cat <<EOF

$(say "$NAME is built, from haus $REF.")

  Hand a lane its own copy:
      scruff runtime up   <lane> --backend tart
      scruff runtime enter <lane> --backend tart
      scruff runtime down <lane> --backend tart

  Point the adapter at this image:
      export SCRUFF_TART_BASE=$NAME

  Look at a lane's screen without touching your own:
      ip=\$(tart ip scruff-<lane>)
      ssh $GUEST_USER@\$ip '/usr/sbin/screencapture -x /tmp/s.png'
      scp $GUEST_USER@\$ip:/tmp/s.png ./shot.png
EOF
