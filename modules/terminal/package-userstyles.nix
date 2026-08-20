# The Nebelung userstyles, compiled — the sheet that puts the rice's palette on
# github.com without an extension and without a click.
#
# ---- why this can exist at all, which is a Gecko-only fact ------------------
#
# `userContent.css` with `@-moz-document` styles real websites, in the browser,
# with no add-on involved. It is a USER sheet, so the restriction that turned
# `@-moz-document` off for page-authored CSS doesn't reach it. Chromium deleted
# user stylesheets in Chrome 33 and never brought them back, so the Blink
# equivalent of this file would have to be a self-built extension packed as a
# CRX and force-installed by policy. That asymmetry is why haus's browser story
# is a Gecko one, and it is the opposite of the way the signing story runs.
#
# terminal/default.nix already copies nebelung's own userContent.css into
# every Zen profile and flips `toolkit.legacyUserProfileCustomizations.stylesheets`
# on. That file is entirely `@-moz-document url-prefix("about:")` rules — the
# browser's own pages. This one is the other half: the sites you actually read.
#
# ---- and the Gecko fact it is NOT: the cascade ------------------------------
#
# Being able to MATCH the page is only half of it. A user sheet's normal
# declarations sit BELOW the page's own in the cascade, so everything compiled
# here has to be raised to `!important` or it renders as nothing — see
# userstyles-important.py, which does that and explains where it can't. This
# cost two releases of `haus.zen.userStyles` that looked right in the profile
# and changed no pixels, because the check was "is the file there" and the file
# was always there.
#
# ---- what stays with Stylus -------------------------------------------------
#
# Everything a sheet can't do. No per-site toggle, no auto-update, no adding a
# style without a rebuild. `haus.zen.extensions.stylus` still deploys the
# extension and zen.nix still stamps the importable bundle; this is for the
# handful of sites you want themed on every machine, every rebuild, with no
# state to carry. The two coexist by accident of scope rather than by design,
# and they are NOT symmetric: Stylus injects author-origin CSS, this sheet is
# user `!important`, and user `!important` outranks anything an author sheet
# can say. So on a site both theme, this one wins and Stylus's copy is dead
# weight — keep a site in one place or the other.
#
# ---- the size cost, which is why the option is a list and not a bool --------
#
# Every style nebelung ships is ~2.5 MB of LESS and 7.1 MB compiled (measured,
# the whole set). A user sheet is applied to EVERY document, so shipping the lot
# would be a tax on every page load to theme sites you don't visit. github +
# youtube is ~320 KB. Keep the list short on purpose.
{
  lib,
  runCommand,
  fetchurl,
  lessc,
  python3,

  # nebelung's Stylus export — the RAW one, straight off the variant root.
  # Deliberately not the accent-stamped copy zen.nix builds for the import
  # dialog: this path does its own stamping (userstyles.py), so the two are
  # independent renderings of the same three axes rather than a chain where one
  # silently depends on the other's jq.
  bundle,
  styles,
  accent,
  flavor,
}:

let
  # The catppuccin standard library, vendored because a Nix build has no
  # network and every style imports it. Pinned at the VERSIONED file rather
  # than at `lib/lib.less`, which is a two-line shim whose only job is to
  # forward to this one — pinning the shim would mean pinning nothing.
  #
  # It does carry a full four-flavour `@catppuccin` map of its own, and that map
  # is NOT what you see: each style redefines `@catppuccin` inline with
  # nebelung's greys after the import, and LESS takes the last definition. What
  # the lib is actually here for is the mixins those definitions are fed
  # through — which is why the output is #202020 rather than #1e1e2e.
  stdlib = fetchurl {
    url = "https://userstyles.catppuccin.com/lib/std/v1.less";
    hash = "sha256-XK9Oqan7Kz81DNyE3+ryl5sPi/OpvV+EkgL7WuLoGfM=";
  };
in

# The name carries the two axes worth reading in a `ls -l` of the profile's
# chrome dir; the SELECTION is in the store hash like everything else, so a
# changed list still moves the path the activation symlinks. Unlike zen.nix's
# stamped bundle, nothing here compares the name against recorded state — this
# side has no announcement to keep honest, only a symlink to repoint.
runCommand "nebelung-userstyles-${flavor}-${accent}.css"
  {
    nativeBuildInputs = [
      python3
      lessc
    ];
    inherit styles;
  }
  ''
    mkdir -p less
    python3 ${./userstyles.py} \
      ${bundle} ${stdlib} less \
      ${lib.escapeShellArg accent} ${lib.escapeShellArg flavor} \
      $styles

    # One file per style, concatenated in the order the script settled on. The
    # CALLER sorts and dedupes, which is what makes that order the only one this
    # derivation can be asked for — `styles` reaches this build through the
    # environment in the order it is given, so sorting only in python would
    # leave two spellings of one selection hashing apart. Each block is
    # labelled: the output is a few hundred KB of generated CSS, and the next
    # person to open it in a profile deserves to know which style they're in.
    : > "$out"
    while read -r slug; do
      printf '\n/* ==== %s (nebelung %s / %s) ==== */\n' "$slug" ${lib.escapeShellArg flavor} ${lib.escapeShellArg accent} >> "$out"
      # Piped through the important pass, NOT written straight out: a user
      # sheet's normal declarations lose to the page's own, so unstamped CSS
      # here renders as nothing at all. userstyles-important.py has the
      # measurement and the three places it deliberately doesn't stamp.
      lessc "less/$slug.less" | python3 ${./userstyles-important.py} >> "$out"
    done < less/order
  ''
