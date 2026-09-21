#!/usr/bin/env bats
# `haus set`'s ADDRESS: which option path the verb can name, how that path
# becomes Nix, and what it says when a write takes more than it was given.
#
# What this suite is FOR. All three halves fail quietly, and the first two
# failed quietly for real (hausfold/ops `todo/launch-phase-1.md`, the Launcher
# room's S1):
#
#   * the path grammar refusing a `:`. Every `haus.launcher.items` key is a
#     palette address — `cmd:copy-text`, `mode:emoji`, `shortcut:<uuid>` — so a
#     grammar built for `[A-Za-z0-9_-]` locked every leaf of that option out of
#     the verb while the comment above it promised an `attrsOf` key is the
#     user's. The refusal names the path, not the colon, so it reads as a typo.
#   * `settings_attrpath` leaving one BARE. Its identifier test was the glob
#     `[A-Za-z_]*` — a leading letter and then anything at all — which is also
#     the shape of every palette address, so the file `haus set` had just
#     written was a Nix syntax error, reported against a generated file the
#     reader never opened.
#   * a whole-attrset write saying nothing. An overlay is `lib.mkForce`, so
#     naming the enclosing set replaces it: `haus set launcher.items '{…}'`
#     withdrew the five items haus defines and the command printed the new
#     value and stopped. Nothing warns at eval either — that mkForce is
#     perfectly valid Nix.
#
# Pure bash: no nix, no Mac. The end-to-end half (a real consumer evaluated,
# the file on disk, the value read back) is test/haus-settings.sh, which CI
# runs in the `acquire` job — the one with a real nix in it. ⚠️ This comment
# used to say CI "cannot run" it "because it evaluates a darwinConfiguration".
# That was never true: evaluating one is what the Linux runner does all day.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"
  # haus.sh refuses to load without a config flake. Nothing here evaluates it.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  echo '{ outputs = _: { }; }' >"$HAUS_CONSUMER/flake.nix"
}

# The same shape test/agent-surface.bats and three other suites carry: source
# the subject as a library and run one snippet against it.
haus_sh() { # haus_sh <VAR=val…> <snippet>
  local snippet="${!#}"
  run env HAUS_CONSUMER="$HAUS_CONSUMER" "${@:1:$#-1}" HAUS_LIB=1 "$BASH" -c "
    set -uo pipefail
    source '$SUBJECT'
    host_name() { echo testhost; }
    $snippet"
}

# ---- the path grammar --------------------------------------------------------

@test "an attrsOf key may be a palette address, bare or quoted" {
  # Both spellings land on the SAME path: the quoted one is what the docs show
  # and what a reader copies out of them.
  haus_sh 'settings_path launcher.items.cmd:copy-text.listed'
  [ "$output" = "haus.launcher.items.cmd:copy-text.listed" ] || fail "$output"

  haus_sh 'settings_path '"'"'launcher.items."cmd:copy-text".listed'"'"''
  [ "$output" = "haus.launcher.items.cmd:copy-text.listed" ] || fail "$output"

  haus_sh 'settings_path haus.launcher.items.mode:emoji.hotkey'
  [ "$output" = "haus.launcher.items.mode:emoji.hotkey" ] || fail "$output"
}

@test "the keys that were already legal still are" {
  haus_sh 'settings_path theme.accent'
  [ "$output" = "haus.theme.accent" ] || fail "$output"
  # A display UUID starts with a digit as often as not — the reason a component
  # may, and the worked example the grammar's comment names.
  haus_sh 'settings_path displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale'
  [ "$output" = "haus.displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale" ] || fail "$output"
}

@test "a key holding a . or a / is sent to the host file BY NAME" {
  # The one shape no widening reaches: `.` is the separator here, and
  # settings_file turns the path into a filename. `app:<path>` and
  # `setting:<pane>[?<anchor>]` (modules/launcher/item-grammar.nix) hold both.
  # Saying which beats "not writable" about a key that is legal in a host file.
  local p
  for p in 'launcher.items."app:/Applications/Foo.app".listed' \
           'launcher.items.app:/Applications/Foo.app.listed' \
           'launcher.items."setting:com.apple.Appearance-Settings.extension".listed'; do
    haus_sh "settings_path '$p'"
    [ "$status" -ne 0 ] || fail "accepted a key it cannot address: $p"
    [[ "$output" == *"host-file-only"* ]] || fail "the wrong refusal for $p: $output"
  done
}

@test "a plain / is a typo, not a key, and is told so" {
  # `haus set theme/accent teal` is a misspelling. Answering it with
  # instructions for writing a key in a host file sends the reader looking for a
  # key that does not exist, so the host-file sentence is reserved for a
  # surviving quote or a `/` beside a `:` — the shape of a palette address.
  local p
  for p in 'theme/accent' 'displays.a/b.uiScale'; do
    haus_sh "settings_path '$p'"
    [ "$status" -ne 0 ] || fail "accepted '$p' -> $output"
    [[ "$output" != *"host-file-only"* ]] || fail "host-file advice for a typo: $output"
    [[ "$output" == *"only haus.* option paths are writable"* ]] || fail "$output"
  done
}

@test "the widening did not open the grammar to anything else" {
  # A trailing separator is the one a normalising walk drops by accident: strip
  # the empty last component and `haus.theme.` reads as `haus.theme`.
  local p
  for p in 'theme.' 'theme..accent' 'theme.acc ent' 'launcher.items.:leading.listed' \
           'theme.accent"' 'theme.$accent'; do
    haus_sh "settings_path '$p'"
    [ "$status" -ne 0 ] || fail "accepted '$p' -> $output"
  done
}

# ---- the path as Nix ---------------------------------------------------------

@test "everything that is not a bare identifier is quoted" {
  haus_sh 'settings_attrpath haus.launcher.items.cmd:copy-text.listed'
  [ "$output" = 'haus.launcher.items."cmd:copy-text".listed' ] || fail "$output"

  # A Nix keyword is all letters and still not an identifier; a UUID starts
  # with a digit; a plain path keeps its plain spelling.
  haus_sh 'settings_attrpath haus.displays.with.uiScale'
  [ "$output" = 'haus.displays."with".uiScale' ] || fail "$output"
  haus_sh 'settings_attrpath haus.displays.37D8832A-2D66.uiScale'
  [ "$output" = 'haus.displays."37D8832A-2D66".uiScale' ] || fail "$output"
  haus_sh 'settings_attrpath haus.bar.items.aiUsage'
  [ "$output" = 'haus.bar.items.aiUsage' ] || fail "$output"
  # `-` is legal inside a Nix identifier, so a key that is one stays bare.
  haus_sh 'settings_attrpath haus.apps.packs.writing'
  [ "$output" = 'haus.apps.packs.writing' ] || fail "$output"
}

@test "a colon survives into the filename, and the overlap guard sees it" {
  # One override per path is the model, and the guard finds an ancestor by
  # walking the dotted name and a descendant by globbing it. A colon is in
  # neither character class, so this is the case that proves the file the verb
  # writes is the file the guard reads.
  haus_sh 'settings_file haus.launcher.items.cmd:copy-text.listed'
  [ "$output" = "$HAUS_CONSUMER/hosts/testhost/settings/launcher.items.cmd:copy-text.listed.nix" ] \
    || fail "$output"

  mkdir -p "$HAUS_CONSUMER/hosts/testhost/settings"
  : >"$HAUS_CONSUMER/hosts/testhost/settings/launcher.items.cmd:copy-text.listed.nix"
  haus_sh 'settings_overlap haus.launcher.items'
  [ "$status" -eq 0 ] || fail "the guard missed a descendant override: $output"
  [ "$output" = "haus.launcher.items.cmd:copy-text.listed" ] || fail "$output"

  haus_sh 'settings_overlap haus.theme.accent'
  [ "$status" -ne 0 ] || fail "the guard invented an overlap: $output"
}

# ---- what a whole-attrset write takes with it --------------------------------

@test "a key nothing defines any more is GONE, and says so" {
  haus_sh '
    settings_report_force_losses haus.launcher.items \
      '"'"'{"cmd:copy-text":{"hotkey":"cmd+shift+2"},"mode:emoji":{"hotkey":"fn"},"cmd:lane-here":{"listed":true}}'"'"' \
      '"'"'{"cmd:copy-text":{"hotkey":null}}'"'"' \
      '"'"'{"cmd:copy-text":{"listed":false}}'"'"' 2>&1'
  [[ "$output" == *"nothing defines these any more"* ]] || fail "$output"
  [[ "$output" == *"mode:emoji"* && "$output" == *"cmd:lane-here"* ]] || fail "$output"
  # The key the caller NAMED is not a loss, however much it changed.
  [[ "$output" != *"cmd:copy-text,"* ]] || fail "reported a key the caller named: $output"
  [[ "$output" == *"haus reset launcher.items"* ]] || fail "no way back: $output"
}

@test "a key the option still has, holding something else, fell back to a DEFAULT" {
  # The second half of the same defect, one level down: a partial attrset over a
  # submodule leaves every key in place and takes the ones it didn't name back
  # to their defaults, which is how the item that WAS named lost its hotkey.
  haus_sh '
    settings_report_force_losses haus.launcher.items.cmd:copy-text \
      '"'"'{"hotkey":"cmd+shift+2","listed":true,"alias":null}'"'"' \
      '"'"'{"hotkey":null,"listed":false,"alias":null}'"'"' \
      '"'"'{"listed":false}'"'"' 2>&1'
  [[ "$output" == *"fell back to their defaults"* ]] || fail "$output"
  [[ "$output" == *hotkey* ]] || fail "$output"
  [[ "$output" != *"nothing defines these any more"* ]] || fail "a reset read as gone: $output"
}

@test "a leaf reset INSIDE the key you named is a loss too" {
  # The half the first cut of this missed. A whole-map write is a partial
  # attrset per key as well as over the map, so the item that WAS named loses
  # the `hotkey` it had — a keybind that silently stops firing — while the key
  # itself is obviously one the caller knows about. Excluding every named key
  # hid exactly the defect the fix was for.
  haus_sh '
    settings_report_force_losses haus.launcher.items \
      '"'"'{"cmd:copy-text":{"hotkey":"cmd+shift+2","listed":true},"mode:emoji":{"hotkey":"fn"}}'"'"' \
      '"'"'{"cmd:copy-text":{"hotkey":null,"listed":false}}'"'"' \
      '"'"'{"cmd:copy-text":{"listed":false}}'"'"' 2>&1'
  [[ "$output" == *"cmd:copy-text.hotkey"* ]] || fail "the named key's own leaf went unsaid: $output"
  [[ "$output" == *"nothing defines these any more"*"mode:emoji"* ]] || fail "$output"

  # One level and no deeper, and only where BOTH sides are attrsets: a
  # scalar-valued attrsOf (`windows.workspaceMonitors`) has no leaves to walk.
  haus_sh '
    settings_report_force_losses haus.windows.workspaceMonitors \
      '"'"'{"T":"main","9":"secondary"}'"'"' '"'"'{"T":"other"}'"'"' '"'"'{"T":"other"}'"'"' 2>&1'
  [[ "$output" == *"nothing defines these any more: 9"* ]] || fail "$output"
  [[ "$output" != *"fell back"* ]] || fail "walked into a scalar: $output"
}

@test "nothing to say is said with nothing" {
  # A scalar cannot carry a key away, an unchanged map has not, and an option
  # with no previous value has nothing to lose. A warning on any of these would
  # teach the reader to ignore the one that matters.
  haus_sh 'settings_report_force_losses haus.theme.accent '"'"'"mauve"'"'"' '"'"'"teal"'"'"' teal 2>&1'
  [ -z "$output" ] || fail "warned about a scalar: $output"
  haus_sh 'settings_report_force_losses haus.x '"'"'{"a":1}'"'"' '"'"'{"a":2}'"'"' '"'"'{"a":2}'"'"' 2>&1'
  [ -z "$output" ] || fail "warned about a key the caller named: $output"
  haus_sh 'settings_report_force_losses haus.x "" '"'"'{"a":2}'"'"' '"'"'{"a":2}'"'"' 2>&1'
  [ -z "$output" ] || fail "warned with no previous value: $output"
  # A named key whose leaves all stayed put, and a key that is new on both
  # sides: the nested walk must find nothing in either.
  haus_sh '
    settings_report_force_losses haus.x \
      '"'"'{"a":{"k":1}}'"'"' '"'"'{"a":{"k":1},"new":{"k":2}}'"'"' '"'"'{"a":{"k":1},"new":{"k":2}}'"'"' 2>&1'
  [ -z "$output" ] || fail "invented a loss: $output"
}
