#!/usr/bin/env bash
# scruff's tart runtime adapter (SPEC.md §5.5 in hausfold/scruff) — the "real
# tart backend" hausfold/scruff#52 deliberately left as a follow-up in this repo.
# scruff execs a runtime adapter's setup/enter/teardown as ONE argv, no shell, so
# the multi-step tart dance (clone, boot headless with a shared dir, wait
# for an IP, ssh in) lives here instead of in tart.toml, which just calls
# this script with a subcommand. $1/$2/$3 arrive as separate argv elements
# from scruff's own template rendering, so a lane name with shell
# metacharacters in it is still just a string here, never re-parsed.
set -euo pipefail

cmd="${1:?usage: tart-adapter.sh <setup|enter|teardown|screenshot> <lane-name> [lane-path|dest.png]}"
lane="${2:?usage: tart-adapter.sh <setup|enter|teardown|screenshot> <lane-name> [lane-path|dest.png]}"
user="${SCRUFF_TART_USER:-admin}"

# ⚠️ One name, and setup refuses rather than clones when it is taken. Getting
# this wrong costs real resources rather than a message: `runtime down` on a
# name that does not exist exits non-zero and leaves a live headless macOS VM
# (tens of GB of disk, real CPU) with nothing on the machine that will ever
# reap it, and the next `runtime up` clones a SECOND one beside it. Silent
# unless you `tart list`.
vm_exists() { tart list --quiet 2>/dev/null | grep -qx "$1"; }

# ⚠️ Every ssh and scp into a guest carries these, and both options are
# consequences of the clone being disposable rather than of anything about
# security. vmnet hands the same 192.168.64.x addresses out again from one lane
# to the next, so an address is a DIFFERENT host, with a different key, every
# time a clone is made; an entry for it in the user's known_hosts turns the next
# lane's first ssh into a REMOTE HOST IDENTIFICATION HAS CHANGED refusal, and
# that wedge outlives the VM that caused it — every later lane that lands on the
# address inherits it. So these hosts are never written to known_hosts at all.
# The far end is a VM this machine cloned itself, minutes ago, on a private
# bridge it also owns; there is nothing else that could be answering.
ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
# The non-interactive form: never stop for a password prompt, and give up on an
# unreachable address in seconds rather than on TCP's own timetable. Used by
# `screenshot` and by setup's readiness probe; `enter` is a person's shell and
# takes neither.
ssh_quiet=(-o BatchMode=yes -o ConnectTimeout=5)

# ⚠️ `ConnectTimeout` bounds the TCP connect and NOTHING after it, and the gap
# is exactly where setup's readiness probe lives: macOS's sshd is launchd
# socket-activated, so early in a boot the connect succeeds instantly against a
# socket launchd is holding while the daemon behind it is not serving yet. A
# probe that stalls in the banner or auth exchange there has no client-side
# timeout to end it, and would sit past the deadline for as long as the guest
# felt like — a silent hang inside the wait that exists to prevent one. So each
# probe gets a wall of its own, and its stderr is kept: `BatchMode` turns "this
# image wants a password" into a probe that can never succeed, and without the
# text nothing anywhere would say so.
ssh_probe() {
  local pid waited=0
  ssh "${ssh_opts[@]}" "${ssh_quiet[@]}" "$user@$1" true 2>"$probe_err" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 15 ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

vm="scruff-$lane"

case "$cmd" in
setup)
  path="${3:?tart-adapter.sh setup needs the lane path as \$3}"
  base="${SCRUFF_TART_BASE:?set SCRUFF_TART_BASE to a tart image already on this machine — build one with the script/build-golden-vm.sh in haus (a bare \`tart pull ghcr.io/cirruslabs/macos-tahoe-base:latest\` works, but has no haus in it), then export SCRUFF_TART_BASE=that image}"
  if vm_exists "$vm"; then
    echo "tart VM $vm already exists — \`tart delete $vm\` to reset it" >&2
    exit 1
  fi
  tart clone "$base" "$vm"
  # Headless, backgrounded: `tart run` blocks in the foreground until the VM
  # stops, and scruff's setup step is meant to return once the VM is reachable,
  # not once it shuts down. `--dir` shares the lane's worktree in over
  # virtiofs rather than copying it — mirrors scruff's own reflink-not-copy
  # bias (SPEC.md §6.3) for the same COW reason.
  #
  # ⚠️ The redirect is the load-bearing half of that, not `disown`. `disown`
  # takes the job out of this shell's table; it does not take our stdout and
  # stderr away from a child that has already inherited them, and this child
  # outlives the script by the entire life of the VM. A caller that reads this
  # step through a pipe or a `$( )` — which is what an agent running `scruff
  # runtime up` always is — then waits on a pipe the guest holds open for
  # hours, with the VM up and reachable the whole time and nothing anywhere
  # saying so. Measured 2026-09-04: `scruff runtime up … | tail` never
  # returned, `scruff` itself long gone, `lsof` showing `tart run` still on fds
  # 1 and 2 of that pipe. To a FILE and not /dev/null, because a guest that
  # never takes an address explains itself nowhere else.
  boot_log="${TMPDIR:-/tmp}/$vm.boot.log"
  tart run "$vm" --no-graphics --dir="work:$path" >"$boot_log" 2>&1 &
  disown
  if ! ip=$(tart ip "$vm" --wait 60); then
    echo "$vm never took an address — its boot log is $boot_log" >&2
    echo "stopping it; \`tart delete $vm\` reclaims the disk" >&2
    tart stop "$vm" 2>/dev/null || true
    exit 1
  fi
  # ⚠️ An address is not a shell. `tart ip` answers the moment the guest takes a
  # DHCP lease, which is most of a minute before sshd accepts anything, so a
  # setup that returned here would hand its caller a guest that refuses every
  # command sent to it — which is exactly what hausfold/haus#663 looks like from
  # the outside ("reported the clone booted and got a DHCP lease, but ssh never
  # reached it"). Wait for the thing the caller actually needs, and report the
  # address only once something on the far end has answered on it.
  ssh_wait="${SCRUFF_TART_SSH_WAIT:-180}"
  case "$ssh_wait" in
  '' | *[!0-9]*)
    echo "SCRUFF_TART_SSH_WAIT is seconds, and \`$ssh_wait\` is not a number" >&2
    exit 2
    ;;
  esac
  probe_err="${TMPDIR:-/tmp}/$vm.probe.log"
  # Said out loud, because a minute of `tart ip` and up to three of this with
  # nothing on either stream is the same dead terminal the leak above produced —
  # the symptom, arrived at honestly. fd 2, so `screenshot`'s stdout contract is
  # untouched by it.
  echo "waiting up to ${ssh_wait}s for sshd on $ip …" >&2
  deadline=$((SECONDS + ssh_wait))
  until ssh_probe "$ip"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "$vm is at $ip but sshd did not answer inside ${ssh_wait}s — its boot log is $boot_log" >&2
      if [ -s "$probe_err" ]; then
        echo "the last attempt said: $(tail -n 1 "$probe_err")" >&2
      fi
      # ⚠️ `tart delete` is NOT the recovery here, and this is the one message
      # where getting that wrong costs most. The guest is deliberately left
      # RUNNING so it can be looked at, and `tart delete` refuses a running VM
      # (no --force; see teardown below, where the stop IS the force). So the
      # verb that works is the one that stops it first.
      echo "it is still running: \`scruff runtime down $lane --backend tart\` reclaims the disk" >&2
      exit 1
    fi
    sleep 2
  done
  rm -f "$probe_err"
  echo "$vm is up at $ip — the lane is mounted at /Volumes/My Shared Files/work — \`scruff runtime enter\` to ssh in"
  ;;
enter)
  ip=$(tart ip "$vm" --wait 10) || {
    echo "$vm has no IP — is it running? \`scruff runtime up\` first" >&2
    exit 1
  }
  exec ssh "${ssh_opts[@]}" "$user@$ip"
  ;;
screenshot)
  # The half of the VM loop that is not scruff's business: pixels out of the
  # guest and onto THIS machine's disk, where `gh pr create --attach` (gh
  # 2.99.0+) can upload them into a PR body. A subcommand rather than its own
  # script because the fact it needs — a lane's VM is named `scruff-<lane>` —
  # is this file's, and a second copy of that naming rule is a drift shape
  # (`docs/drift.md`) waiting to happen. `haus-vm-shot` on PATH is one `exec`
  # into here.
  #
  # ⚠️ This verb is HAUS's, outside scruff's adapter contract: scruff only ever
  # execs setup/enter/teardown, and the generated tart.toml lists only those
  # three. Spelled `screenshot` rather than `shot` so it cannot be mistaken for
  # a future scruff-defined `snapshot` — VM snapshots being the obvious verb
  # for that backend to grow.
  #
  # ⚠️ Opt-in, per PR, and only where a human would otherwise have to feel it.
  # The screenshot is seconds; making it show your change means `haus rebuild`
  # INSIDE the guest first, which is minutes — that rebuild, not this, is what
  # a "screenshot every PR" habit would actually cost.
  out="${3:-${TMPDIR:-/tmp}/$vm.png}"
  # A directory would let scp land the file inside it and then leave this
  # script echoing the directory, which `--attach` cannot use.
  if [ -d "$out" ]; then
    echo "$out is a directory — give haus-vm-shot a file path, or no path at all" >&2
    exit 2
  fi
  ip=$(tart ip "$vm" --wait 10) || {
    echo "$vm has no IP — is it running? \`scruff runtime up\` first" >&2
    exit 1
  }
  # A path this script chooses, on the guest's own /tmp — never the caller's
  # "$out", which routinely names a host directory the guest does not have.
  remote="/tmp/haus-vm-shot.$$.png"
  # Reaped on the way out however this ends. `set -e` on a failed scp would
  # otherwise skip the cleanup and leave the PNG on a guest whose disk is the
  # real cap on VMs per machine.
  trap 'ssh "${ssh_opts[@]}" "${ssh_quiet[@]}" "$user@$ip" "rm -f $remote" >/dev/null 2>&1 || true' EXIT
  # `-x` is not politeness: without it screencapture plays the shutter and
  # flashes the display it is capturing, and `agent-desktop-guard` refuses the
  # unpaired form for exactly that reason. Call the binary by absolute path —
  # a non-interactive ssh gets a minimal PATH — and do NOT wrap it in
  # `launchctl asuser`, which fails here with "Could not switch to audit
  # session"; the guest is auto-logged-in at its console, so this is enough.
  #
  # Both ssh stdouts go to /dev/null, not to ours: whatever the guest's shell
  # prints on login (the classic .zshenv echo) would otherwise land inside the
  # `$( )` a caller wraps this in, and end up in a pull request.
  ssh "${ssh_opts[@]}" "${ssh_quiet[@]}" "$user@$ip" "/usr/sbin/screencapture -x $remote" >/dev/null
  scp "${ssh_opts[@]}" "${ssh_quiet[@]}" -q "$user@$ip:$remote" "$out"
  # stdout is the path and NOTHING else. The caller is an agent composing
  # `gh pr comment --attach "$(haus-vm-shot lane)"`, so a stray line here does
  # not go to a terminal — it goes into a pull request.
  echo "$out"
  ;;
teardown)
  # `tart delete` takes no --force (measured against tart 2.30.6: it exits 64,
  # "Unknown option"). It deletes a stopped VM and refuses a running one, so
  # the stop above IS the force — best-effort, because a VM that is already
  # stopped makes it fail, which is not a reason to leave the clone on disk.
  tart stop "$vm" 2>/dev/null || true
  tart delete "$vm"
  # The clone's own paper trail goes with it. Neither file outlives the guest it
  # describes, and `$TMPDIR` is where a lane's next `setup` will write them again.
  rm -f "${TMPDIR:-/tmp}/$vm.boot.log" "${TMPDIR:-/tmp}/$vm.probe.log"
  ;;
*)
  echo "unknown tart-adapter.sh subcommand: $cmd — want setup, enter, teardown, or screenshot" >&2
  exit 1
  ;;
esac
