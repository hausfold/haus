# The declarative source of truth for what a `defaults write` can reach — the
# sibling of ./restart-map.nix, in the same shape, answering the question that
# comes one step earlier.
#
# restart-map.nix says what has to happen AFTER a `defaults write` for anyone to
# feel it. This says whether the write can happen AT ALL, and what it does when
# it does. Both are "the fact that makes an option a lie if you don't know it" —
# §5.6's "what second key or precondition makes the first one a lie", except here
# the precondition isn't a second key, it's a TCC grant held by a *different app
# than the one the user is thinking about*.
#
# Why it is a table and not a comment: the answer had SIX hand-copies before this
# file existed — core's warning, core's typed-domain list, terminal's skill section,
# `haus rebuild`'s guard, `haus doctor`'s permission row, and the REACHABILITY
# paragraph pasted into each option's description. Six copies of one fact is the
# fourteenth pass's "a table plus a filter over that table is two sources of truth
# wearing one name", six times over. core derives from this; everything downstream
# reads what core rendered into the BUILT activation script (the §5.11 discipline:
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
# ---- route: how haus writes an FDA-gated domain -----------------------------
#   guardedBy = "<option namespace>"
#     — haus offers its own writer for this domain, one that tolerates a
#       refusal: on failure it says why and activation carries on. A missing grant
#       costs you the setting and nothing else. That is the ONLY acceptable way to
#       write a `needs-fda` domain, and the reason those options exist at all.
#   guardedBy = null
#     — no safe route; the domain is reachable only through nix-darwin's own
#       generator, which emits an UNGUARDED `defaults write` into an activation
#       script running under `set -e`, roughly two thirds of the way in. Without
#       the grant that write exits 1 and takes the REST OF ACTIVATION with it —
#       every launchd daemon and user agent haus installs (the bar, the
#       tiling, the palette) is silently skipped, with the symptom nowhere near
#       the cause. nix-darwin#1049.
#
# ---- effect: does the write mean anything? ----------------------------------
# Per key for a domain that has a mixed answer, or once for the whole domain via
# `effect` when every key shares one. Swept 2026-07-25 on real hardware from an
# FDA-holding Ghostty, run twice with byte-identical results and a clean restore
# both times (`docs/macos-settings.md`).
#   "effective"   — the write lands AND `NSWorkspace` confirms macOS honours it.
#                   `hausax` is the oracle that keeps it honest (`haus diff`
#                   compares against the NSWorkspace read, not the plist).
#   "by-eye"      — the write lands and a HUMAN watched it take effect on real
#                   hardware; no programmatic oracle exists, so nothing can
#                   re-check it on your machine. Added 2026-08-14, and it is a
#                   separate class rather than a second `effective` for one
#                   reason: `haus diff` must not claim to have verified these.
#                   It compares the plist and says that is all it did.
#                   Options MAY be built on this — an eyeball on real hardware is
#                   evidence, and refusing to ship what only a human can confirm
#                   is how three working keys sat unusable for three weeks. What
#                   it costs is per-machine confirmation, which is a real cost:
#                   `effective` proves it on YOUR Mac, `by-eye` proves it on the
#                   one it was watched on. Say which in the option's description.
#   "unconfirmed" — the plist holds the value; the effect was never measured,
#                   because no programmatic oracle exists for it. Needs an eyeball
#                   before it becomes an option. Not a synonym for "probably fine".
#                   The difference from `by-eye` is only that somebody looked.
#   "gui-only"    — the write lands in the plist and posts no change notification,
#                   so no running app ever re-reads it and System Settings renders
#                   a desynced view of its own rows. Only the slider works.
#   "noop"        — writes, changes nothing, ever. The worst of the five: a
#                   read-back check reports "applied" on a machine that did not
#                   move. Any option built on this ships a lie.
#
# ---- the routes NOT taken, and why -----------------------------------------
# Two ways to reach a `needs-fda` domain WITHOUT the grant. Both are real; one is
# measured and rejected, one is still open. Written down because the FDA gate is
# the first thing anybody reading this file wants out of, and the obvious escapes
# cost an afternoon each to re-derive.
#
# A CONFIGURATION PROFILE — spiked 2026-08-18, since bypassing TCC is precisely
# what a managed preference is for. It works. A System-scope
# `com.apple.ManagedClient.preferences` payload forcing com.apple.universalaccess
# writes /Library/Managed Preferences/<user>/com.apple.universalaccess.plist —
# the per-user path under a device-scope payload, which is MCX compositing for
# the logged-in user rather than a typo — leaves the user domain untouched
# (`defaults read` still answers "does not exist"), and macOS honours the result:
# `hausax` read NSWorkspace TRUE for both `reduceTransparency` and `reduceMotion`
# from a shell holding no Full Disk Access at all.
#
# Rejected on DELIVERY, not on effect. macOS has had no command-line install path
# since Big Sur — `profiles install` answers "profiles tool no longer supports
# installs" — so an unmanaged Mac approves each profile by hand in System
# Settings with an admin password, and that cost is per profile VERSION: an
# in-place update, same PayloadIdentifier and same PayloadUUID with
# PayloadVersion bumped, prompted for the entire flow a second time. A rebuild
# that moves one accessibility value would therefore nag every time, where the
# guarded `defaults write` above is silent forever after a single grant. Forced
# prefs also grey the switch out of System Settings, which is a strange thing to
# hand someone on their own Mac. The route survives only where MDM delivers it —
# which is also the only channel that can pre-grant TCC itself (PPPC), so the two
# halves of "no clicking left" turn out to be one half.
#
# THE ANY-USER LEVEL — /Library/Preferences/<domain>.plist, root-owned and, for
# THIS domain, outside TCC. (Not for the directory as a whole: com.apple.TimeMachine
# lives there and is FDA-gated. Reachability is a property of the domain, not the
# folder.) modules/terminal/zen.nix already writes a file there from activation,
# installing Zen's policy domain wholesale rather than through `defaults`.
#
# MEASURED 2026-08-18, and it WORKS. With the user domain empty, a root write to
# /Library/Preferences/com.apple.universalaccess plus a `killall universalaccessd`
# reads back TRUE through `hausax` — `effective` by this table's own oracle, with
# no Full Disk Access anywhere, no profile, and nothing clicked. Activation is
# already root, so this is the one escape a rebuild could drive unattended.
#
# The mechanism is nothing exotic: it is CFPreferences' ordinary search list —
# managed, then the current user, then any-user. Saying that plainly matters,
# because it collapses two apparent surprises into one fact:
#   - the user domain SHADOWS the any-user level BY CONSTRUCTION. Feature and
#     trap at once: a person keeps the last word in System Settings, and the
#     moment they use it a haus write here goes inert forever, with nothing
#     anywhere to say so.
#   - so `needs-fda` above is a property of (domain, LEVEL) rather than of the
#     domain alone. com.apple.universalaccess is FDA-gated at the user level and
#     open at the any-user level, and the table's key names only the first.
#
# What a route built on it would still owe, none of it fatal:
#   - The daemon has to be restarted before anyone feels it — including for
#     `reduceTransparency`, which is live IMMEDIATELY when written at the user
#     level. modules/core/default.nix's `a11yRestartKeys` gate deliberately
#     bounces universalaccessd only for the `by-eye` keys, because the four
#     oracle-backed ones were already live; that gate would have to become
#     level-aware and not merely key-aware. ./restart-map.nix already maps the
#     domain to the daemon, so it is core's per-key filter that moves, not the map.
#   - Only `reduceTransparency` was measured this way. The other three
#     `effective` keys are untested at this level, and so is survival across a
#     reboot.
#   - The first run of this measurement was a FALSE POSITIVE and cost a
#     retraction: write, an immediate `killall cfprefsd universalaccessd`, an
#     oracle reading true — and minutes later no plist on disk and the oracle
#     back to false. The mechanism is UNEXPLAINED, and it sits awkwardly beside
#     zen.nix's own measured "cfprefsd flushes on SIGTERM, which is what makes
#     that safe rather than lossy", so reconcile those two before trusting either
#     account. The operating rule needs no mechanism at all: an oracle read is
#     not evidence until the plist is ON DISK.
{
  # ---- com.apple.universalaccess ---------------------------------------------
  # The reason this file exists. Real, useful, TCC-gated, and mixed: four keys
  # work, three are unmeasured and one lies.
  #
  # The `effective` four are exactly `haus.accessibility`'s option surface, and
  # that is not a coincidence anyone maintains by hand: modules/core/options.nix
  # GENERATES those options from this list. The third place the same names appear
  # — `classify_key` in modules/core/haus.sh, which decides how `haus diff`
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
  # that had no safer way to say what it meant.
  #
  # ★ That used to carry one deliberate exception — nix-darwin also types the
  # three keys this table left `unconfirmed`, so the raw, activation-aborting
  # form genuinely reached settings the safe form didn't, and the guard refused
  # it anyway. **The exception is gone as of 2026-08-14.** nix-darwin types
  # exactly five keys here (`mouseDriverCursorSize`, `reduceMotion`,
  # `reduceTransparency`, `closeViewScrollWheelToggle`,
  # `closeViewZoomFollowsFocus`); `haus.accessibility` now covers all five and
  # two more. So the guard no longer costs anyone a setting — there is nothing
  # left that only the dangerous route can say. Worth noticing HOW that
  # happened: nobody removed the exception, somebody watched a cursor. The
  # friction was never really about the guard's strictness, it was about three
  # unmeasured keys, and it went away when they stopped being unmeasured.
  "com.apple.universalaccess" = {
    reachability = "needs-fda";
    guardedBy = "haus.accessibility";
    keys = {
      reduceMotion = "effective";
      reduceTransparency = "effective";
      increaseContrast = "effective";
      differentiateWithoutColor = "effective";

      # Watched 2026-08-14 on 26.6.1, after three weeks at `unconfirmed`: all
      # three work, and all three do nothing until `universalaccessd` restarts —
      # which is why they looked dead. ./restart-map.nix carries that half; the
      # kill and these three promotions have to ship together or the options
      # write a plist their user sees nothing come of until the next logout.
      #
      # `by-eye` rather than `effective` because there is no oracle for any of
      # them and there is not going to be one: NSWorkspace exposes no pointer
      # size and no zoom state. What was watched, precisely, so a re-check knows
      # what to reproduce:
      #   mouseDriverCursorSize      3.0 → pointer visibly larger
      #   closeViewScrollWheelToggle ⌃+scroll magnifies the display
      #   closeViewZoomFollowsFocus  ⇥ to an input outside the zoomed viewport
      #                              snaps the view to it. Isolating this one
      #                              needs the POINTER parked — pushing the
      #                              pointer at a screen edge pans the view with
      #                              this key off, which is not evidence.
      mouseDriverCursorSize = "by-eye";
      closeViewScrollWheelToggle = "by-eye";
      closeViewZoomFollowsFocus = "by-eye";

      # The dict-valued one, and the heuristic it produced: in this domain the
      # SCALAR keys work and notify, the STRUCTURED one lands and lies. It also
      # only ever reached apps that adopted Dynamic Type (a short all-Apple list),
      # so even working it would have under-delivered. Treat any future
      # dict-valued accessibility key as GUI-only until measured otherwise.
      FontSizeCategory = "gui-only";
    };

    # ---- value type, for the keys that aren't booleans ----------------------
    # Every key above was a bool until `mouseDriverCursorSize` became shippable,
    # and both consumers had that assumption baked in: core's writer emitted
    # `defaults write … -bool` unconditionally, and core/options.nix generated
    # `nullOr bool`. A float key promoted without this would have produced an
    # option that accepts `true` and writes `-bool true` into a size field.
    #
    # Kept BESIDE `keys` rather than folded into it so a class stays one string:
    # `haus diff`'s shell copy, the option generator and this table all read the
    # class, and only the two Nix-side consumers care about the type. Absent
    # means bool, which is what the domain mostly is.
    #
    # `range` is documentation with teeth — core/options.nix builds the option's
    # type from it, so macOS's "1 for normal, 4 for maximum" is enforced at eval
    # instead of being a sentence someone can write 40 past.
    keyTypes = {
      mouseDriverCursorSize = {
        type = "float";
        range = {
          min = 1.0;
          max = 4.0;
        };
      };
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
