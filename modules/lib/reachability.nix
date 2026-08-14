# The declarative source of truth for §5.12 of the workshop's
# notes/options-roadmap.md — the sibling of ./restart-map.nix, in the same shape,
# answering the question that comes one step earlier.
#
# restart-map.nix says what has to happen AFTER a `defaults write` for anyone to
# feel it. This says whether the write can happen AT ALL, and what it does when
# it does. Both are "the fact that makes an option a lie if you don't know it" —
# §5.6's "what second key or precondition makes the first one a lie", except here
# the precondition isn't a second key, it's a TCC grant held by a *different app
# than the one the user is thinking about*.
#
# Why it is a table and not a comment: the answer had SIX hand-copies before this
# file existed — den's warning, den's typed-domain list, hearth's skill section,
# `haus rebuild`'s guard, `haus doctor`'s permission row, and the REACHABILITY
# paragraph pasted into each option's description. Six copies of one fact is the
# fourteenth pass's "a table plus a filter over that table is two sources of truth
# wearing one name", six times over. den derives from this; everything downstream
# reads what den rendered into the BUILT activation script (the §5.11 discipline:
# grep what a rebuild actually runs, never a second copy of the map).
#
# Keyed by the plist domain exactly as `defaults write DOMAIN …` (and
# nix-darwin's `system.defaults.<domain>` / `CustomUserPreferences."<domain>"`)
# name it — the same spelling restart-map.nix uses, so a domain never needs two.
#
# ONLY THE EXCEPTIONS ARE LISTED. A domain absent from this table is `"open"`
# with `effect = "plain"`: any process can write it and the write means what it
# says. That is nearly every domain on the Mac, which is exactly why the handful
# that aren't need naming.
#
# ---- reachability: can the write land? --------------------------------------
#   "open"      — any process can write it. The default for an unlisted domain.
#   "needs-fda" — TCC-protected: the write succeeds only when the app RESPONSIBLE
#                 for the process holds Full Disk Access. Not the euid — root
#                 without the grant is refused too (measured 2026-07-25, and the
#                 retraction in the matrix is worth reading before assuming
#                 otherwise). The grant follows the terminal, the agent pane, or
#                 the .app that invoked the rebuild, which is what makes this the
#                 one property in the whole option surface that can differ between
#                 two machines running byte-identical config.
#
# ---- route: how the rice writes an FDA-gated domain -------------------------
#   guardedBy = "<option namespace>"
#     — the rice offers its own writer for this domain, one that tolerates a
#       refusal: on failure it says why and activation carries on. A missing grant
#       costs you the setting and nothing else. That is the ONLY acceptable way to
#       write a `needs-fda` domain, and the reason those options exist at all.
#   guardedBy = null
#     — no safe route; the domain is reachable only through nix-darwin's own
#       generator, which emits an UNGUARDED `defaults write` into an activation
#       script running under `set -e`, roughly two thirds of the way in. Without
#       the grant that write exits 1 and takes the REST OF ACTIVATION with it —
#       every launchd daemon and user agent the rice installs (the bar, the
#       tiling, the palette) is silently skipped, with the symptom nowhere near
#       the cause. nix-darwin#1049.
#
# ---- effect: does the write mean anything? ----------------------------------
# Per key for a domain that has a mixed answer, or once for the whole domain via
# `effect` when every key shares one. Swept 2026-07-25 on real hardware from an
# FDA-holding Ghostty, run twice with byte-identical results and a clean restore
# both times (workshop notes/macos-settings-matrix.md).
#   "effective"   — the write lands AND `NSWorkspace` confirms macOS honours it.
#                   This is the only class an option may be built on, and `hausax`
#                   is the oracle that keeps it honest (`haus diff` compares
#                   against the NSWorkspace read, not the plist).
#   "unconfirmed" — the plist holds the value; the effect was never measured,
#                   because no programmatic oracle exists for it. Needs an eyeball
#                   before it becomes an option. Not a synonym for "probably fine".
#   "gui-only"    — the write lands in the plist and posts no change notification,
#                   so no running app ever re-reads it and System Settings renders
#                   a desynced view of its own rows. Only the slider works.
#   "noop"        — writes, changes nothing, ever. The worst of the four: a
#                   read-back check reports "applied" on a machine that did not
#                   move. Any option built on this ships a lie.
{
  # ---- com.apple.universalaccess ---------------------------------------------
  # The reason this file exists. Real, useful, TCC-gated, and mixed: four keys
  # work, three are unmeasured and one lies.
  #
  # The `effective` four are exactly `haus.accessibility`'s option surface, and
  # that is not a coincidence anyone maintains by hand: modules/den/options.nix
  # GENERATES those options from this list. The third place the same names appear
  # — `classify_key` in modules/den/haus.sh, which decides how `haus diff`
  # verifies a declared key — genuinely is a hand copy, because a shell script
  # can't import a Nix table; flake.nix's `accessibility-surface` check seds that
  # arm out of the script and diffs it against this list, so a fifth key measured
  # tomorrow fails the build until both agree.
  #
  # Covering all four MATTERS beyond tidiness, and it is the §5.12 finding worth
  # carrying: the reason anybody writes the dangerous `system.defaults.universalaccess.*`
  # form is that the safe form didn't reach their key. `reduceMotion` and
  # `reduceTransparency` are nix-darwin-TYPED — so before they had guarded options
  # the documented way to set them was the one that aborts activation. Closing the
  # gap is what lets `haus rebuild`'s guard be strict without refusing a config
  # that had no safer way to say what it meant — with one deliberate exception,
  # worth stating plainly rather than glossing: nix-darwin also types the three
  # `unconfirmed` keys below, so the raw form does still reach something the
  # options don't, and the guard does still refuse it. That friction is in the
  # right place. It costs a rebuild from a granted terminal, and it is bought by
  # never shipping an option whose only claim is that the plist held the value.
  "com.apple.universalaccess" = {
    reachability = "needs-fda";
    guardedBy = "haus.accessibility";
    keys = {
      reduceMotion = "effective";
      reduceTransparency = "effective";
      increaseContrast = "effective";
      differentiateWithoutColor = "effective";

      # Persist at the value you write; nobody has watched the screen afterwards.
      # `ui.cursorScale` waits on the first of these — an option is not a place to
      # find out whether a key does anything.
      mouseDriverCursorSize = "unconfirmed";
      closeViewScrollWheelToggle = "unconfirmed";
      closeViewZoomFollowsFocus = "unconfirmed";

      # The dict-valued one, and the heuristic it produced: in this domain the
      # SCALAR keys work and notify, the STRUCTURED one lands and lies. It also
      # only ever reached apps that adopted Dynamic Type (a short all-Apple list),
      # so even working it would have under-delivered. Treat any future
      # dict-valued accessibility key as GUI-only until measured otherwise.
      FontSizeCategory = "gui-only";
    };
  };

  # ---- com.apple.Accessibility -----------------------------------------------
  # Not FDA-gated — this one you CAN write, from anywhere, which is precisely what
  # makes it dangerous. It holds the modern-looking spellings of the same settings
  # (ReduceMotionEnabled, DifferentiateWithoutColor, DarkenSystemColors,
  # EnhancedBackgroundContrastEnabled, InvertColorsEnabled, GrayscaleDisplay,
  # ButtonShapesEnabled, FullKeyboardAccessEnabled) and moves none of them:
  # measured, the plist reads `1` while NSWorkspace still reports false, unchanged
  # after a settle and after poking com.apple.accessibility.cache.ax.
  #
  # Listed here rather than merely avoided so that a host reaching it through
  # `haus capture` gets told, and so `haus diff` has a table to get its verdict
  # from instead of a hardcoded domain name. There is no option surface on this
  # domain and there must never be one; `com.apple.universalaccess` above is where
  # the working spellings live.
  "com.apple.Accessibility" = {
    reachability = "open";
    guardedBy = null;
    effect = "noop";
    keys = { };
  };
}
