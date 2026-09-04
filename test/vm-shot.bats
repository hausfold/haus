#!/usr/bin/env bats
# Hermetic tests for `tart-adapter.sh screenshot` — the subcommand behind
# `haus-vm-shot`, which lifts a frame out of a lane's headless guest so it can
# be attached to a pull request (`gh … --attach`, gh 2.99.0+).
#
# The failure modes worth pinning are the ones a human never sees, because this
# script's output is not read by a person — it is read by `$( )` and then
# published:
#
#   * a stray line on stdout does not land in a terminal, it lands in a PR body,
#     and the guest's own login chatter is the likeliest source of one
#   * `screencapture` without `-x` flashes the display it is capturing, and is
#     the exact shape `agent-desktop-guard` refuses
#   * the wrong VM name silently photographs another lane's guest
#   * a failure that still printed a path would attach a stale or absent file
#   * a fetch that failed after the capture would leave the PNG on a guest whose
#     disk is the real cap on how many VMs a machine can hold
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
  OUT="$BATS_TEST_TMPDIR/out.png"
  mkdir -p "$STUB"
  : >"$LOG"

  # Each stub records its full argv, one call per line, then does the least
  # thing that keeps the script moving. `scp` is the only one that has to have
  # an effect: it is what puts the file on the host.
  cat >"$STUB/tart" <<EOF
#!/usr/bin/env bash
echo "tart \$*" >>"$LOG"
[ "\$1" = ip ] || exit 0
[ -n "\${TART_NO_IP:-}" ] && exit 1
echo 192.168.64.5
EOF

  cat >"$STUB/ssh" <<EOF
#!/usr/bin/env bash
echo "ssh \$*" >>"$LOG"
EOF

  cat >"$STUB/scp" <<EOF
#!/usr/bin/env bash
echo "scp \$*" >>"$LOG"
printf 'PNG' >"\${@: -1}"
EOF

  chmod +x "$STUB"/*
  PATH="$STUB:$PATH"
}

# stdout is a contract, not a report: the caller is an agent writing
# `--attach "$(haus-vm-shot lane)"`, so one line, and that line is the path.
@test "screenshot prints the destination path and nothing else" {
  run -0 --separate-stderr bash "$SUBJECT" screenshot my-lane "$OUT"
  [ "$output" = "$OUT" ]
  [ -s "$OUT" ]
}

# The guest's shell prints on login often enough that this is the realistic way
# the contract above breaks: an echo in .zshenv, straight into a PR body.
@test "screenshot keeps the guest's own chatter off stdout" {
  cat >"$STUB/ssh" <<'EOF'
#!/usr/bin/env bash
echo "hello from the guest's .zshenv"
EOF
  chmod +x "$STUB/ssh"
  run -0 --separate-stderr bash "$SUBJECT" screenshot my-lane "$OUT"
  [ "$output" = "$OUT" ]
}

@test "screenshot captures silently — screencapture always carries -x" {
  run -0 bash "$SUBJECT" screenshot my-lane "$OUT"
  grep -q 'screencapture -x ' "$LOG"
}

@test "screenshot addresses this lane's VM, under scruff's naming" {
  run -0 bash "$SUBJECT" screenshot my-lane "$OUT"
  grep -qx 'tart ip scruff-my-lane --wait 10' "$LOG"
}

@test "screenshot removes the file it made on the guest" {
  run -0 bash "$SUBJECT" screenshot my-lane "$OUT"
  grep -q 'rm -f /tmp/haus-vm-shot\.' "$LOG"
}

# `set -e` after a failed fetch would otherwise walk straight past the cleanup.
@test "screenshot still reaps the guest file when the fetch fails" {
  printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB/scp"
  chmod +x "$STUB/scp"
  run bash "$SUBJECT" screenshot my-lane "$OUT"
  [ "$status" -ne 0 ]
  grep -q 'rm -f /tmp/haus-vm-shot\.' "$LOG"
}

@test "screenshot's default destination is under TMPDIR, named for the VM" {
  TMPDIR="$BATS_TEST_TMPDIR" run -0 --separate-stderr bash "$SUBJECT" screenshot my-lane
  [ "$output" = "$BATS_TEST_TMPDIR/scruff-my-lane.png" ]
}

# The important half is stdout being EMPTY. A caller substituting this into
# `--attach` must get an empty string, never a plausible filename that happens
# to hold last week's screenshot.
@test "screenshot fails loudly when the VM has no IP, and prints no path" {
  TART_NO_IP=1 run -1 --separate-stderr bash "$SUBJECT" screenshot my-lane "$OUT"
  [ -z "$output" ]
  [[ "$stderr" == *"has no IP"* ]]
  [ ! -e "$OUT" ]
}

# scp would land the file inside the directory and this would then echo the
# directory, which `--attach` cannot use.
@test "a directory destination is refused rather than echoed back" {
  mkdir -p "$BATS_TEST_TMPDIR/shots"
  run -2 --separate-stderr bash "$SUBJECT" screenshot my-lane "$BATS_TEST_TMPDIR/shots"
  [ -z "$output" ]
  [[ "$stderr" == *"is a directory"* ]]
}

@test "an unknown subcommand names screenshot among the four" {
  run -1 --separate-stderr bash "$SUBJECT" nonsense my-lane
  [[ "$stderr" == *screenshot* ]]
}

# vmnet hands the same 192.168.64.x addresses out again from one clone to the
# next, so a known_hosts entry written by one lane refuses every later lane that
# lands on that address — here that is a pull request that never gets its
# picture. test/vm-runtime.bats holds the same rule for `setup` and `enter`.
@test "the capture path keeps disposable guests out of known_hosts" {
  run -0 bash "$SUBJECT" screenshot my-lane "$OUT"
  while read -r line; do
    case "$line" in
      ssh\ * | scp\ *) [[ "$line" == *"UserKnownHostsFile=/dev/null"* ]] || {
        echo "writes known_hosts: $line" >&2
        return 1
      } ;;
    esac
  done <"$LOG"
}
