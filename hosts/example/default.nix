# Your machine. Copy this to hosts/<hostname>/ and make it yours, then wire it
# up in flake.nix:
#
#   darwinConfigurations.<hostname> = mkHaus {
#     username = "you";
#     hostname = "<hostname>";
#     host = ./hosts/<hostname>;
#   };
#
# This is a plain nix-darwin module — anything nix-darwin or home-manager
# accepts goes here, and it merges with what the rice modules already declare.
# `pkgs` is here for haus.roster entries that install from Nixpkgs.
{ username, pkgs, ... }:

{
  # ---- your identity ----
  haus.git.name = "Your Name";
  haus.git.email = "you@example.com";
  # GPG key id for commit signing; leave "" to disable signing.
  haus.git.signingKey = "";
  # The GitHub owner your work lives under — an org, or your own account. Only
  # gh-dash reads it today: with haus.terminal.ghDash.enable it fills ⌘G's PR tabs
  # with that owner's open / green / red / just-shipped work. Leave "" and those
  # tabs aren't written at all.
  # haus.git.org = "your-org";
  # Terminal ships a compact, framework-independent set of Git shell aliases
  # (gst, gco, gp, grbi, gwt, …). Extend/override them here, or set one to null
  # to remove it:
  # haus.git.shellAliases = {
  #   gst = "git status --short --branch";
  #   gsync = "git pull --rebase --autostash";
  #   gco = null;
  # };

  # pounce signing. Find your identity's SHA-1 with:
  #   security find-identity -v -p codesigning
  # Leave "" to run pounce unsigned (palette works; Accessibility features off).
  haus.launcher.signingIdentity = "";

  # Where secretspec finds secret VALUES on this machine. Default "keyring" is
  # the local macOS keychain (no accounts, values re-entered once per Mac —
  # `secretspec check` lists what's missing). A cloud provider ("gcsm",
  # "awssm", "bws", "onepassword", …) makes values follow you to the next Mac;
  # you configure its credentials outside Nix. WHICH secrets exist is each
  # project's committed secretspec.toml; what the ROOMS on this machine need is
  # declared by the rooms themselves — `haus-secret --list` after a rebuild.
  # haus.secrets.provider = "keyring";

  # Text expansion (espanso): type a trigger, get the expansion, in any app —
  # terminal included. Opt-in: installs the Espanso.app cask and needs a
  # one-time Accessibility grant the first time it runs (System Settings →
  # Privacy & Security → Accessibility → enable Espanso). Grant survives reboots
  # + updates because it runs the signed app bundle, not a nix-store binary.
  # haus.snippets = {
  #   enable = true;
  #   matches = [
  #     { trigger = "@@"; replace = "you@example.com"; }
  #   ];
  # };

  # Obsidian keeps appearance per vault. List home-relative vault paths here to
  # install/select the full Nebelung theme on every rebuild; empty leaves all
  # vaults untouched. The vault must already contain a .obsidian directory.
  # haus.terminal.obsidianVaults = [
  #   "Library/Mobile Documents/iCloud~md~obsidian/Documents/notes"
  # ];

  # The rice's own app picks — a GUI editor, or a whole saved collection in one
  # line. Each is a roster entry like any other once it's on, so you can give it
  # a leader letter or pin a different build from here:
  # haus.apps.vscode.enable = true;
  # haus.apps.packs.writing.enable = true;

  # Your apps — ONE list, whatever the source. An entry with a `key` joins the
  # Caps-Lock launcher; an entry with neither key nor workspace membership is
  # simply installed. So the app you reach for by keyboard and the font you
  # never think about live in the same place.
  # haus.roster = {
  #   slack = {
  #     key = "s";                              # Caps Lock, then s
  #     name = "Slack";                         # as `open -a` spells it
  #     appId = "com.tinyspeck.slackmacgap";    # osascript -e 'id of app "Slack"'
  #     cask = "slack";                         # declaring it installs it
  #   };
  #
  #   # No key: installed and left alone.
  #   google-chrome = { name = "Google Chrome"; cask = "google-chrome"; };
  #   ical-buddy = { brew = "ical-buddy"; };            # a formula, not an app
  #   orbstack = { name = "OrbStack"; package = pkgs.orbstack; };
  #   ripgrep = { package = pkgs.ripgrep; scope = "system"; };  # machine-wide
  #   xcode = { name = "Xcode"; appStoreId = 497799835; };      # see appStore.install
  # };
  #
  # Which WORKSPACE an app owns is the workspace's call, not the app's — so
  # several apps (a "comms" role: Slack + Mail + Messages) can share one pill
  # and one leader throw instead of "one app, one workspace":
  # haus.workspaces.S = {
  #   key = "s";                     # leader ⇧s throws a window here and follows;
  #                                  # leader ⌥⇧s throws it and stays
  #   icon = ":slack:";              # falls back to the workspace id ("S")
  #   apps = [ "slack" ];            # roster ids that herd here
  # };
  #
  # The plain lists still work and still merge, for the rare thing that isn't
  # an app at all:
  #   homebrew.casks = [ "some-cask" ];

  # The shell/terminal layer ships in the `terminal` module (zsh, starship, git,
  # yazi, ghostty, helix — all Nebelung-themed). To add YOUR personal bits on
  # top (extra packages, private aliases, the rare env var every shell needs),
  # extend home-manager — per-project secrets belong in secretspec instead:
  #
  #   home-manager.users.${username} = {
  #     home.packages = with pkgs; [ /* your tools */ ];
  #     programs.zsh.initContent = lib.mkAfter ''
  #       alias deploy="ssh you@yourserver"
  #     '';
  #   };
}
