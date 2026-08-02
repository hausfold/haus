# Reading order and a one-line blurb for each `nebelhaus.*` room.
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
    blurb = "Your commit identity — set your own. It stays in [your host file](/internals/flakes/#your-config-is-a-thin-consumer).";
  };
  roster = {
    order = 20;
    blurb = "One list of everything this machine has — apps, fonts, command-line tools. Each entry drives its launcher key, workspace, bar pill and cheatsheet row, and installs it from whichever source it names: a Homebrew cask or formula, a Nixpkgs package, or the Mac App Store.";
  };
  appStore = {
    order = 21;
    blurb = "Whether a rebuild may install the roster's `appStoreId` entries. Off by default: it reaches the network and acts on your Apple Account, and it can never be complete — `mas` cannot sign in, and cannot buy a paid app.";
  };

  # ---- how it looks ---------------------------------------------------------
  theme = {
    order = 30;
    blurb = "Colour and wallpaper.";
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
  trill = {
    order = 150;
    blurb = "The Messages client.";
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
