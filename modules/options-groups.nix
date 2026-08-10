# Reading order and a one-line blurb for each `haus.*` room.
#
# Everything else about an option — type, default, example, description, the
# file that declares it — comes out of the module system itself (options-doc.nix)
# and must never be restated by hand. Two things can't: the order a person should
# meet the rooms in, and what a room IS in one sentence. The module system has no
# notion of "identity first, policy last", and no place to hang a sentence that
# describes a whole namespace rather than a leaf.
#
# So that, and only that, lives here — once, as data, read by every renderer:
#
#   host-template.jq            the annotated host file a fresh install gets
#   web/scripts/gen-options.mjs nebelhaus.com's options reference (via groups.json)
#
# It used to live inside the web renderer alone, where it covered 16 of the 23
# rooms — the other seven (agents, collar, developer, displays, keys, perch, ui)
# silently fell off the end of the page in alphabetical order with no blurb.
#
# A room missing from this file is NOT an error. Renderers sort unlisted rooms
# alphabetically AFTER the listed ones, so a newly added room appears somewhere
# sensible the day it lands, and picks up its blurb whenever someone writes one.
# `order` values are spaced by ten so a room can be slotted between two others
# without renumbering the file.
#
# Blurbs are MARKDOWN — the docs page renders them as-is, and host-template.jq
# flattens `[text](link)` down to `text` on its way into a Nix comment. Written
# the other way round (plain text plus a separate link field) the page would
# have lost sentences it already had, for a link the comment can't click anyway.
{
  # ---- who you are ----------------------------------------------------------
  git = {
    order = 10;
    blurb = "Your commit identity, plus the GitHub owner this machine's work lives under — set your own. It stays in [your host file](/internals/flakes/#your-config-is-a-thin-consumer).";
  };
  roster = {
    order = 20;
    blurb = "One list of everything this machine has — apps, fonts, command-line tools. Each entry drives its launcher key, cheatsheet row, and installs it from whichever source it names: a Homebrew cask or formula, a Nixpkgs package, or the Mac App Store.";
  };
  workspaces = {
    order = 21;
    blurb = "The named AeroSpace workspaces this machine declares, and which roster apps live on each. A workspace, not an app, owns its bar pill and leader throw — so several apps (a whole \"comms\" role) can share one.";
  };
  appStore = {
    order = 22;
    blurb = "Whether a rebuild may install the roster's `appStoreId` entries. Off by default: it reaches the network and acts on your Apple Account, and it can never be complete — `mas` cannot sign in, and cannot buy a paid app.";
  };
  apps = {
    order = 23;
    blurb = "The apps the rice picks for you, and the file types they claim — the ones a finished machine has rather than the ones a room needs to work. Each is one switch you can turn off; what it installs is a roster entry like any other, so you can retune or replace it by app id.";
  };

  # ---- how it looks ---------------------------------------------------------
  theme = {
    order = 30;
    blurb = "Colour: the palette's flavour and contrast, the accent every themed tool spends, and whether macOS's own Light/Dark follows it.";
  };
  wallpaper = {
    order = 35;
    blurb = "The desktop behind everything. `minimal` is generated on this machine — a flat field at whatever depth you pick out of the palette, the haus mark ⌂ at its centre, a bloom in your accent, and enough grain that none of it bands. The other looks are the hand-made Nebelung ones.";
  };
  fonts = {
    order = 40;
    blurb = "The terminal font. The bar keeps its own font at its own tuned sizes.";
  };
  ui = {
    order = 50;
    blurb = "One number for \"make the interface bigger\", applied across the rice's own surfaces.";
  };
  displays = {
    order = 60;
    blurb = "Per-display overrides, keyed by which screen you mean.";
  };

  # ---- the terminal, and who else drives this machine -----------------------
  hearth = {
    order = 70;
    blurb = "The shell and terminal experience.";
  };
  agents = {
    order = 80;
    blurb = "Which coding-agent clients this machine installs, and which one the agent keybinding spawns.";
  };
  claude = {
    order = 90;
    blurb = "Claude Code integration.";
  };

  # ---- reach ----------------------------------------------------------------
  accessibility = {
    order = 100;
    blurb = "macOS accessibility keys the rice can actually apply. These write to a TCC-protected domain, so they take effect only when the app you run the rebuild from holds Full Disk Access — otherwise the rice warns and moves on.";
  };
  keys = {
    order = 110;
    blurb = "The keys the rice owns — the leader, the palette, the window-chord modifier — and anything extra you hang off the leader.";
  };
  # ---- macOS settings groups (options-roadmap §5.6) -------------------------
  # Dense on purpose: this block ran out of the file's usual ten-wide spacing
  # when the last three groups landed, and `prowl` at 120 is the next fixed
  # point. `animations` then took 111 — the last free slot, and the last
  # squeeze available: the block is now 111–119 with no gaps, so the NEXT group added
  # here has to renumber it, from `prowl` at 120 downwards.
  animations = {
    order = 111;
    blurb = "How much motion macOS spends on its own Dock and windows: the slide, the launch bounce, minimise, Mission Control, window open/close. Unset by default like the rest of this block — `\"fast\"` opts in, and going back only stops writing rather than restoring. Deliberately not the Accessibility \"Reduce motion\" switch, which every browser also reads as `prefers-reduced-motion`.";
  };
  hotCorners = {
    order = 112;
    blurb = "What each corner of the screen does when the pointer reaches it. Every corner is unset by default, so the rice never overwrites one you set yourself.";
  };
  screenshots = {
    order = 113;
    blurb = "Where ⇧⌘4 puts its files, in what format, and whether it draws a window shadow or a preview thumbnail. Unset by default, so macOS's own choices stand.";
  };
  lock = {
    order = 114;
    blurb = "Whether waking this Mac needs a password, and how long the grace period is. Worth setting on any laptop that leaves the house.";
  };
  menuBar = {
    order = 115;
    blurb = "The stock menu bar: what the clock shows, and which Control Center glyphs sit beside it. (The nebelhaus bar itself is `sill`.)";
  };
  security = {
    order = 116;
    blurb = "Security posture: the built-in application firewall and how strict it is. Off on a fresh Mac; the setting to turn on for a laptop that joins networks you don't own.";
  };
  sound = {
    order = 117;
    blurb = "Alert volume and sound, interface sound effects, and the boot chime. Volume is 0–100 the way the slider reads it — macOS stores a curve, and the rice does the conversion.";
  };
  locale = {
    order = 118;
    blurb = "Language, region, units and keyboard layouts. What a rice in any language other than English needs — and the one room whose settings reach apps you already have open, because the rice posts the change notification macOS itself posts.";
  };
  power = {
    order = 119;
    blurb = "Sleep timers and Low Power Mode, said separately for battery and charger — which is the whole point, and why this is built on `pmset` rather than on nix-darwin's own power options.";
  };

  # ---- the rooms ------------------------------------------------------------
  prowl = {
    order = 120;
    blurb = "Tiling window management and the Caps-Lock leader launcher.";
  };
  sill = {
    order = 130;
    blurb = "The menu bar, and which pills it draws.";
  };
  pounce = {
    order = 140;
    blurb = "The ⌘Space command palette.";
  };
  perch = {
    order = 160;
    blurb = "The notch file shelf.";
  };
  hush = {
    order = 170;
    blurb = "One quiet switch: Do Not Disturb, optional Slack status, and your hooks.";
  };
  snippets = {
    order = 180;
    blurb = "Text expansion via espanso.";
  };
  tour = {
    order = 190;
    blurb = "The first-run tutor.";
  };

  # ---- policy ---------------------------------------------------------------
  developer = {
    order = 200;
    blurb = "The developer pack: the CLI toolbelt, Git tooling, coding-agent tooling, and language runtimes. Off is a nebelhaus machine for someone who never opens a terminal by choice.";
  };
  collar = {
    order = 210;
    blurb = "Touch ID for sudo — including inside a terminal multiplexer — and the passwordless-rebuild rule.";
  };
  secrets = {
    order = 220;
    blurb = "Where secret values come from on this machine.";
  };
  homebrew = {
    order = 230;
    blurb = "How rebuilds treat Homebrew packages you did not declare.";
  };
}
