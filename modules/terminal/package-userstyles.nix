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
# ---- what this gave up, which used to be Stylus's half ----------------------
#
# Everything a sheet can't do: no per-site toggle, no auto-update, no adding a
# style without a rebuild. haus deployed the Stylus extension and stamped an
# importable bundle for exactly those, and that path is retired (2026-08-20) —
# measured off a live profile first, where no style carried an `updateUrl` and
# nothing had been toggled since the import. This is now the whole of haus's
# web theming: the handful of sites you want themed on every machine, every
# rebuild, with no state to carry.
#
# Installing Stylus by hand still works and the two do NOT tie: an extension
# injects author-origin CSS, this sheet is user `!important`, and user
# `!important` outranks anything an author sheet can say. So on a site both
# theme, this one wins and the extension's copy is dead weight — keep a site in
# one place or the other.
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
  writeText,

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

  # The code-block highlighting 29 of the styles reach for with
  # `@import url(...)`. FOUR files serve all 29, every one version-pinned
  # upstream, which is what makes vendoring them a table rather than a policy.
  #
  # They are fetched so they can be INLINED, not so they can be pointed at:
  # `@import` is invalid inside `@-moz-document` wherever it points, so a store
  # path would be dropped exactly like the URL was. userstyles-inline.py does
  # the substitution and explains the rest. Three of the four are upstream's
  # own `.important.css` builds — the same cascade problem, solved the same way,
  # which is a decent check that the reading of it here is right.
  #
  # A fifth URL appearing upstream breaks the build with the prefetch command
  # to run. That is deliberate: the alternative is a style that installs and
  # renders its code blocks stock, which is the failure this whole thing removes.
  vendoredImports = {
    "https://unpkg.com/@catppuccin/highlightjs@1.0.0/css/catppuccin-variables.important.css" =
      fetchurl
        {
          url = "https://unpkg.com/@catppuccin/highlightjs@1.0.0/css/catppuccin-variables.important.css";
          hash = "sha256-bj/nJEOBpOnecprel/lBXDY3bBu7EmgsjJJUW4bR1Ts=";
        };
    "https://unpkg.com/@catppuccin/highlightjs@1.0.0/css/catppuccin-variables.css" = fetchurl {
      url = "https://unpkg.com/@catppuccin/highlightjs@1.0.0/css/catppuccin-variables.css";
      hash = "sha256-Dw6A0CRpZrZ7Cc+lQiGoX406ZzlZCH4A/TVh7D+gXj4=";
    };
    "https://python.catppuccin.com/pygments/catppuccin-variables.important.css" = fetchurl {
      url = "https://python.catppuccin.com/pygments/catppuccin-variables.important.css";
      hash = "sha256-XVji5jYxl8Cj6zqhHX/249O7x0pQh9/1ZDdNNO/IKws=";
    };
    "https://prismjs.catppuccin.com/variables.important.css" = fetchurl {
      url = "https://prismjs.catppuccin.com/variables.important.css";
      hash = "sha256-YuheYDpqJ/FfPOxPdD+XioxyVGqlmkrPip7d6THoUrc=";
    };
  };

  importMap = writeText "userstyle-imports.json" (
    builtins.toJSON (lib.mapAttrs (_: drv: "${drv}") vendoredImports)
  );
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
      # Two passes over lessc's output, in this order and not the other one.
      # Inline first: it pastes in upstream CSS, and one of the four files is
      # NOT an `.important.css`, so it has to arrive before the stamp to get
      # stamped. Then important: a user sheet's normal declarations lose to the
      # page's own, so unstamped CSS here renders as nothing at all. Each
      # script's header carries its own measurement.
      lessc "less/$slug.less" \
        | python3 ${./userstyles-inline.py} ${importMap} \
        | python3 ${./userstyles-important.py} >> "$out"
    done < less/order
  ''
