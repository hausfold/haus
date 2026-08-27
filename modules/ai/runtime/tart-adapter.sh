#!/usr/bin/env bash
# scruff's tart runtime adapter (SPEC.md §5.5 in hausfold/holt) — the "real
# tart backend" hausfold/holt#52 deliberately left as a follow-up in this repo.
# scruff execs a runtime adapter's setup/enter/teardown as ONE argv, no shell, so
# the multi-step tart dance (clone, boot headless with a shared dir, wait
# for an IP, ssh in) lives here instead of in tart.toml, which just calls
# this script with a subcommand. $1/$2/$3 arrive as separate argv elements
# from scruff's own template rendering, so a lane name with shell
# metacharacters in it is still just a string here, never re-parsed.
set -euo pipefail

cmd="${1:?usage: tart-adapter.sh <setup|enter|teardown> <lane-name> [lane-path]}"
lane="${2:?usage: tart-adapter.sh <setup|enter|teardown> <lane-name> [lane-path]}"
vm="scruff-$lane"
user="${SCRUFF_TART_USER:-admin}"

case "$cmd" in
setup)
  path="${3:?tart-adapter.sh setup needs the lane path as \$3}"
  base="${SCRUFF_TART_BASE:?set SCRUFF_TART_BASE to a tart image already on this machine — build one with the script/build-golden-vm.sh in haus (a bare \`tart pull ghcr.io/cirruslabs/macos-tahoe-base:latest\` works, but has no haus in it), then export SCRUFF_TART_BASE=that image}"
  if tart list --quiet 2>/dev/null | grep -qx "$vm"; then
    echo "tart VM $vm already exists — \`tart delete $vm --force\` to reset it" >&2
    exit 1
  fi
  tart clone "$base" "$vm"
  # Headless, backgrounded: `tart run` blocks in the foreground until the VM
  # stops, and scruff's setup step is meant to return once the VM is reachable,
  # not once it shuts down. `--dir` shares the lane's worktree in over
  # virtiofs rather than copying it — mirrors scruff's own reflink-not-copy
  # bias (SPEC.md §6.3) for the same COW reason.
  tart run "$vm" --no-graphics --dir="work:$path" &
  disown
  ip=$(tart ip "$vm" --wait 60)
  echo "$vm is up at $ip — the lane is mounted at /Volumes/My Shared Files/work — \`scruff runtime enter\` to ssh in"
  ;;
enter)
  ip=$(tart ip "$vm" --wait 10) || {
    echo "$vm has no IP — is it running? \`scruff runtime up\` first" >&2
    exit 1
  }
  exec ssh "$user@$ip"
  ;;
teardown)
  # `tart delete` takes no --force (measured against tart 2.30.6: it exits 64,
  # "Unknown option"). It deletes a stopped VM and refuses a running one, so
  # the stop above IS the force — best-effort, because a VM that is already
  # stopped makes it fail, which is not a reason to leave the clone on disk.
  tart stop "$vm" 2>/dev/null || true
  tart delete "$vm"
  ;;
*)
  echo "unknown tart-adapter.sh subcommand: $cmd — want setup, enter, or teardown" >&2
  exit 1
  ;;
esac
