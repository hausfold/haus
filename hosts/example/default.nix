# Your machine. Copy this to hosts/<hostname>/ and make it yours, then wire it
# up in flake.nix:
#
#   darwinConfigurations.<hostname> = mkNebelhaus {
#     username = "you";
#     hostname = "<hostname>";
#     host = ./hosts/<hostname>;
#   };
#
# This is a plain nix-darwin module — anything nix-darwin or home-manager
# accepts goes here, and it merges with what the rice modules already declare.
# `pkgs` is here for nebelhaus.roster entries that install from Nixpkgs.
{ username, pkgs, ... }:

{
  # ---- your identity ----
  nebelhaus.git.name = "Your Name";
  nebelhaus.git.email = "you@example.com";
  # GPG key id for commit signing; leave "" to disable signing.
  nebelhaus.git.signingKey = "";
  # Hearth ships a compact, framework-independent set of Git shell aliases
  # (gst, gco, gp, grbi, gwt, …). Extend/override them here, or set one to null
  # to remove it:
  # nebelhaus.git.shellAliases = {
  #   gst = "git status --short --branch";
  #   gsync = "git pull --rebase --autostash";
  #   gco = null;
  # };

  # pounce signing. Find your identity's SHA-1 with:
  #   security find-identity -v -p codesigning
  # Leave "" to run pounce unsigned (palette works; Accessibility features off).
  nebelhaus.pounce.signingIdentity = "";

  # Where secretspec finds secret VALUES on this machine. Default "keyring" is
  # the local macOS keychain (no accounts, values re-entered once per Mac —
  # `secretspec check` lists what's missing). A cloud provider ("gcsm",
  # "awssm", "bws", "onepassword", …) makes values follow you to the next Mac;
  # you configure its credentials outside Nix. WHICH secrets exist is each
  # project's committed secretspec.toml, not an option here.
  # nebelhaus.secrets.provider = "keyring";

  # Text expansion (espanso): type a trigger, get the expansion, in any app —
  # terminal included. Opt-in: installs the Espanso.app cask and needs a
  # one-time Accessibility grant the first time it runs (System Settings →
  # Privacy & Security → Accessibility → enable Espanso). Grant survives reboots
  # + updates because it runs the signed app bundle, not a nix-store binary.
  # nebelhaus.snippets = {
  #   enable = true;
  #   matches = [
  #     { trigger = "@@"; replace = "you@example.com"; }
  #   ];
  # };

  # Obsidian keeps appearance per vault. List home-relative vault paths here to
  # install/select the full Nebelung theme on every rebuild; empty leaves all
  # vaults untouched. The vault must already contain a .obsidian directory.
  # nebelhaus.hearth.obsidianVaults = [
  #   "Library/Mobile Documents/iCloud~md~obsidian/Documents/notes"
  # ];

  # The rice's own app picks. IINA ships as the video player and takes over the
  # video types QuickTime, TV and your browser would otherwise get (audio, gifs
  # and playlists are left alone). Turn either half off if you'd rather bring
  # your own player, or keep it and leave your associations untouched:
  # nebelhaus.apps.videoPlayer.enable = false;
  # nebelhaus.apps.videoPlayer.claimFileTypes = false;

  # Trill, the family's Messages client, is opt-in: it reads and sends, but the
  # rest is out of reach of Messages.app's automation surface and it isn't
  # actively developed, so it isn't part of a default machine. Uncomment and it
  # installs and themes exactly like the other rooms:
  # nebelhaus.trill.enable = true;

  # Your apps — ONE list, whatever the source. An entry with a `key` joins the
  # Caps-Lock launcher (and a `workspace` gives it a tiling workspace + a bar
  # pill); an entry with neither is simply installed. So the app you reach for
  # by keyboard and the font you never think about live in the same place.
  # nebelhaus.roster = {
  #   slack = {
  #     key = "s";                              # Caps Lock, then s
  #     name = "Slack";                         # as `open -a` spells it
  #     workspace = "S";                        # owns this workspace + a pill
  #     appId = "com.tinyspeck.slackmacgap";    # osascript -e 'id of app "Slack"'
  #     barIcon = ":slack:";
  #     cask = "slack";                         # declaring it installs it
  #   };
  #
  #   # No key, no workspace: installed and left alone.
  #   google-chrome = { name = "Google Chrome"; cask = "google-chrome"; };
  #   ical-buddy = { brew = "ical-buddy"; };            # a formula, not an app
  #   orbstack = { name = "OrbStack"; package = pkgs.orbstack; };
  #   ripgrep = { package = pkgs.ripgrep; scope = "system"; };  # machine-wide
  #   xcode = { name = "Xcode"; appStoreId = 497799835; };      # see appStore.install
  # };
  #
  # The plain lists still work and still merge, for the rare thing that isn't
  # an app at all:
  #   homebrew.casks = [ "some-cask" ];

  # The shell/terminal layer ships in the `hearth` module (zsh, starship, git,
  # yazi, zellij, ghostty — all Nebelung-themed). To add YOUR personal bits on
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
