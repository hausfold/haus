# haus.sound.alertVolume (0–100, what the slider reads) → the number macOS
# actually stores in NSGlobalDomain's `com.apple.sound.beep.volume`.
#
# The key is NOT a fraction. Measured against CoreAudio's live alert volume on
# macOS 26.6.1 (workshop notes/probes/sound-sweep.sh, `osascript -e 'get volume
# settings'` as the oracle — not a plist read-back):
#
#   stored 1.0        → 100        stored 0.5        →  31
#   stored 0.7788008  →  75        stored 0.3678794  →   0
#   stored 0.6065307  →  50        stored 0.0        →   0
#   stored 0.4723665  →  25
#
# which is `stored = e^(slider − 1)`, with everything at or below e⁻¹ ≈ 0.3679
# collapsing to silence. nix-darwin's own docstring lists the 75/50/25 constants
# and never names the curve, so a host writing the obvious `0.5` gets 31% and a
# bug report about the rice.
#
# Nix has no `exp`, hence the series. `exp` is only ever called with x in
# [−1, 0) here, where the Taylor series about 0 converges fast: the n = 18 term
# is x¹⁸/18! ≤ 1.6e−16, which is past the precision of the double macOS keeps.
# Guarded to that interval on purpose — this is a conversion for one option, not
# a general-purpose math library, and a wider domain would need argument
# reduction nobody would remember to add.
{ lib }:
let
  factorial = n: if n <= 1 then 1 else n * factorial (n - 1);
  pow = x: n: if n == 0 then 1.0 else x * pow x (n - 1);
  exp =
    x:
    assert x >= (-1.0) && x <= 0.0;
    lib.foldl' (acc: n: acc + (pow x n) / (factorial n)) 0.0 (lib.range 0 18);
in
{
  # percent: an integer 0–100 (the option's own type enforces the range).
  # 0 is special-cased to exact silence rather than e⁻¹, which is where the
  # curve bottoms out anyway — a machine asked for 0 should hold 0, not
  # 0.3678794 that happens to sound like 0.
  fromPercent = percent: if percent == 0 then 0.0 else exp (percent / 100.0 - 1.0);
}
