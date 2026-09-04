#!/usr/bin/env bats
# Hermetic tests for `tart-adapter.sh setup` and `enter` — the half of the VM
# loop that stands a lane's guest up and gets you a shell in it. The companion
# suite, test/vm-shot.bats, covers `screenshot`.
#
# Everything here is a failure that looks like a working machine, which is what
# made hausfold/haus#663 cost two sessions:
#
#   * the guest inherits the caller's stdout and holds it for the life of the
#     VM, so `scruff runtime up … | …` — an agent's normal way of reading a
#     command — never returns, with the guest up and reachable the whole time
#   * setup reports an address the moment a DHCP lease appears, most of a minute
#     before sshd answers on it, so the caller's first ssh goes nowhere and the
#     loop looks like a network problem
#   * vmnet reuses 192.168.64.x across clones, so a known_hosts entry written by
#     one lane refuses every later lane that lands on the same address
#
# `tart`, `ssh` and `scp` are stubbed onto PATH, so this runs on the CI's Linux
# runner with no VM, no network and no macOS anywhere.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="${BATS_TEST_DIRNAME}/../modules/ai/runtime/tart-adapter.sh"
  [ -f "$SUBJECT" ] || {
    echo "subject missing: $SUBJECT" >&2
    return 1
  }

  STUB="$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/argv.log"
  LANE="$BATS_TEST_TMPDIR/lane"
  mkdir -p "$STUB" "$LANE"
  : >"$LOG"

  # `tart run` is the one that matters: it is the long-lived child, so it holds
  # whatever file descriptors setup handed it. GUEST_LIFE seconds of holding
  # them is the whole measurement in the first test below.
  cat >"$STUB/tart" <<EOF
#!/usr/bin/env bash
echo "tart \$*" >>"$LOG"
case "\$1" in
  list) exit 0 ;;
  run)  echo "a line the guest wrote"; sleep "\${GUEST_LIFE:-5}"; exit 0 ;;
  ip)   [ -n "\${TART_NO_IP:-}" ] && exit 1; echo 192.168.64.5 ;;
  *)    exit 0 ;;
esac
EOF

  # Answers straight away by default; SSH_REFUSES makes it a guest that has an
  # address but no sshd yet.
  cat >"$STUB/ssh" <<EOF
#!/usr/bin/env bash
echo "ssh \$*" >>"$LOG"
[ -n "\${SSH_REFUSES:-}" ] && exit 255
exit 0
EOF

  chmod +x "$STUB"/*
  PATH="$STUB:$PATH"
  export SCRUFF_TART_BASE=some-base
  export TMPDIR="$BATS_TEST_TMPDIR"
}

# The bug behind hausfold/haus#663's "waited 20 minutes": `disown` takes the job
# out of the shell's table but leaves the child holding our stdout, so a caller
# reading this step through a pipe waits on the GUEST, not on the command. The
# assertion is a clock, because that is the only thing that tells the two apart
# — the output is identical either way.
@test "setup returns as soon as the guest answers, not when it shuts down" {
  local start=$SECONDS
  run -0 bash -c "GUEST_LIFE=5 bash '$SUBJECT' setup my-lane '$LANE' | cat"
  [ $((SECONDS - start)) -lt 3 ]
  [[ "$output" == *"is up at 192.168.64.5"* ]]
}

# Same fd, the other half of what it costs: anything the guest prints would land
# in the caller's output, and setup's caller is a machine.
@test "the guest's own output goes to its boot log, not to the caller" {
  run -0 --separate-stderr bash "$SUBJECT" setup my-lane "$LANE"
  [[ "$output" != *"a line the guest wrote"* ]]
  grep -q "a line the guest wrote" "$TMPDIR/scruff-my-lane.boot.log"
}

# An address is not a shell. Reporting one the moment the lease lands is what
# makes the next command in the loop fail against a guest that is merely still
# booting.
@test "setup waits for sshd before it reports the address" {
  run -0 bash "$SUBJECT" setup my-lane "$LANE"
  grep -q '^ssh .*admin@192.168.64.5 true' "$LOG"
}

@test "a guest that never answers fails loudly and prints no address" {
  SSH_REFUSES=1 SCRUFF_TART_SSH_WAIT=0 run -1 --separate-stderr bash "$SUBJECT" setup my-lane "$LANE"
  [ -z "$output" ]
  [[ "$stderr" == *"sshd did not answer"* ]]
  [[ "$stderr" == *"$TMPDIR/scruff-my-lane.boot.log"* ]]
}

# A clone with no address is tens of GB of disk and real CPU with nothing on the
# machine that will ever reap it. Leaving it RUNNING is the expensive half.
@test "a guest that never takes an address is stopped, not abandoned" {
  TART_NO_IP=1 run -1 --separate-stderr bash "$SUBJECT" setup my-lane "$LANE"
  grep -qx 'tart stop scruff-my-lane' "$LOG"
  [[ "$stderr" == *"never took an address"* ]]
}

# vmnet reuses addresses across clones, so writing one to known_hosts poisons
# every later lane that lands on it — a wedge that outlives the VM that made it.
@test "no ssh into a guest writes to the user's known_hosts" {
  run -0 bash "$SUBJECT" setup my-lane "$LANE"
  run -0 bash "$SUBJECT" enter my-lane
  while read -r line; do
    case "$line" in
      ssh\ *) [[ "$line" == *"UserKnownHostsFile=/dev/null"* ]] || {
        echo "bare ssh: $line" >&2
        return 1
      } ;;
    esac
  done <"$LOG"
}

# `enter` is a person's shell: a batch-mode ssh there could not ask for a
# password, and a five-second connect timeout is not a person's patience.
@test "enter opens an interactive shell, not a batch one" {
  run -0 bash "$SUBJECT" enter my-lane
  grep -q '^ssh .*admin@192.168.64.5' "$LOG"
  ! grep -q '^ssh .*BatchMode.*admin@192.168.64.5$' "$LOG"
}
