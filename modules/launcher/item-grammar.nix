# The item-key grammar — pounce's address space, mirrored on our side of the
# repo boundary.
#
# It lives in `ItemTarget` (pkgs/pounce/ItemSettings.swift). Only the MODE LIST
# is single-sourced there — pounce's own comment ("so the daemon's dispatch, the
# CLI's validation and the error text can't drift") sits on `static let modes`
# and covers that line alone. The prefix grammar is not: `parse` branches on
# `hasPrefix` literals and `problem` restates them in a hand-written sentence, so
# pounce holds two copies of it and this file is a third. `nix flake check`'s
# `pounce-item-grammar` diffs all of it against the LOCKED pounce — the one this
# layer actually installs — including `parse` separately from the sentence,
# because a prefix added to one and not the other leaves both repos wrong in
# agreement.
#
# It exists because the copy already did drift, silently and in the direction
# that costs the user a build: pounce added `shortcut:<uuid>` (pounce#80,
# 2026-08-14 21:03), the lock moved to it two minutes later, and this module
# went on asserting that a valid key "is not an item key". The lock bump is
# mechanical and the mirror was prose; that asymmetry is the whole reason for
# the check.
#
# One thing this file does NOT own, and should be read beside: `modeCaptions` in
# ./default.nix is a second list keyed by mode name, with a silent `or itemKey`
# fallback. A new mode needs a line there too, and the module asserts it does.
#
# Data only — no `lib`, no `config` — so both the module and the flake's check
# can import it without a fixed point.
let
  # The shapes `ItemTarget.parse` accepts, in the order its error text lists
  # them. The order is load-bearing: `expectedText` is compared to pounce's own
  # string byte for byte.
  shapes = [
    "cmd:<id>"
    "app:<path>"
    "shortcut:<uuid>"
    "setting:<pane>[?<anchor>]"
    "mode:<name>"
  ];
in
{
  inherit shapes;

  # The prefixes those shapes name, which is what `ItemTarget.parse` actually
  # branches on — checked separately from `expectedText`, because pounce's error
  # string is a hand-written literal beside the parser rather than derived from
  # it. A prefix added to `parse` and forgotten in that string would leave both
  # repos wrong in agreement, which is this file's own bug recurring green.
  prefixes = map (s: builtins.head (builtins.match "([a-z]+:).*" s)) shapes;

  # One key per shape, real enough to run through the module's validator. The
  # module asserts that every shape has a sample and that every sample is
  # ACCEPTED, which is what stops the cheap green: without it, the next prefix
  # pounce adds is "fixed" by appending one string here — turning the check green
  # while `itemKeyProblem` still rejects the key, with an error listing the very
  # shape it just refused.
  samples = {
    "cmd:<id>" = "cmd:emoji";
    "app:<path>" = "app:/Applications/Ghostty.app";
    "shortcut:<uuid>" = "shortcut:0ECC8F7A-3A52-467A-84C0-511CCE1CB9B7";
    # A pane on its own; `pane?anchor` is the same shape with one setting named
    # inside it, and both go down the same length-only branch in the validator.
    "setting:<pane>[?<anchor>]" = "setting:com.apple.Appearance-Settings.extension";
    "mode:<name>" = "mode:clipboard";
  };

  # `ItemTarget.modes`: the built-in windows a `mode:` key may name. A name
  # pounce doesn't know binds NOTHING, with no error anywhere, which is why this
  # small mirror is worth its risk.
  modes = [
    "launcher"
    "clipboard"
    "emoji"
    "screenshots"
    "camera"
    "filesearch"
  ];

  # `ItemTarget.problem`'s fallback text, built rather than restated so the
  # module's assertion and the check compare the same bytes.
  expectedText =
    let
      n = builtins.length shapes;
      init = builtins.genList (i: builtins.elemAt shapes i) (n - 1);
    in
    "(expected " + builtins.concatStringsSep ", " init + " or " + builtins.elemAt shapes (n - 1) + ")";
}
