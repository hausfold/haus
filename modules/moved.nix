# Options that moved ROOM inside `haus.*`.
#
# Hand-written on purpose: each entry has a reason worth writing down and no
# enumeration can produce it. There is no deletion condition for the file
# itself — a room move can happen again. Entries do age out: drop one when no
# consumer can plausibly still be pinned to a revision that predates the move.
#
# What an alias buys: the old name keeps evaluating (with an obsolete-option
# warning naming the new one), so `~/.config/nix` moves on its own schedule
# instead of in a lockstep PR pair with the layer.
{ lib, ... }:
{
  imports = [
    # 2026-08-11 — the `claude` room became part of `agents`.
    #
    # Both options describe a file haus ships into a coding agent's home:
    # the always-on instructions, and the `haus` skill. Neither is about Claude
    # Code — haus installs three clients (`haus.ai.clients`) and every
    # one of them reads both kinds of file, at its own path. Named for the
    # client, they wrote only Claude's copy, which made `ai.default =
    # "codex"` a half-truth: the pane spawned with none of the operating context
    # or option knowledge the same machine hands Claude.
    #
    # `globalMd` -> `instructions` is a rename as well as a move: "global
    # memory" is Claude Code's word for the slot, and the file the other two
    # clients read is called AGENTS.md.
    (lib.mkRenamedOptionModule [ "haus" "claude" "globalMd" ] [ "haus" "ai" "instructions" ])
    (lib.mkRenamedOptionModule [ "haus" "claude" "skill" ] [ "haus" "ai" "skill" ])

    # 2026-08-16 — the room code names are GONE rather than deprecated:
    # `hearth` -> `terminal`, `prowl` -> `windows`, `sill` -> `bar`,
    # `pounce` -> `launcher`, `perch` -> `shelf`, `hush` -> `focus`, and
    # `collar` -> `security.touchId.*` (folding into the namespace the firewall
    # already had, so the one Security room has one address). `den` was never a
    # namespace; its module and export are `core`.
    #
    # No aliases, for the reason the agents -> ai move gives below: the layer
    # has one consumer, its host moved in the same sweep, and an alias set here
    # would be permanent furniture protecting nobody. It would also defeat the
    # point — the whole change is that those words stop appearing.

    # 2026-08-26 — `haus.trill.enable` -> `haus.notifications.compositor`, and
    # `modules/trill` -> `modules/notifications`. The room landed 2026-08-25,
    # nine days after the sweep above, and was the only one left named for the
    # app rather than for the subject — exactly the shape `pounce` -> `launcher`
    # and `perch` -> `shelf` were rewritten out of. The leaf changed too:
    # `enable` would have claimed the room decides whether this Mac draws haus
    # notifications, and it doesn't — ../core/haus-notify.sh is unconditional and
    # falls back to Apple's banner. `compositor` is the question the room
    # actually answers.
    #
    # No entry, for the same reason the sweep above took none and the `agents` ->
    # `ai` move spells out: the layer has one consumer, its host moves in the
    # same sweep, and an alias for a one-day-old spelling is permanent furniture
    # protecting nobody. It would also defeat the point — the whole change is
    # that `haus.trill` stops appearing.

    # 2026-08-19 — `jcode` is no longer a coding-agent client the layer knows
    # about, so it leaves modules/lib/agents.nix and with it the enums of
    # `haus.ai.clients`, `haus.ai.default` and `haus.bar.aiUsage.provider`.
    # A host still naming it gets the module system's own enum error.
    #
    # No entry, for the same renderer reason the zellij removal gives below —
    # and a narrower one besides: this is a removed VALUE, not a removed
    # option. `mkRemovedOptionModule` has nothing to point at; the option is
    # still here, it just accepts three names instead of four. Nothing shipped
    # ever set it: no desktop named jcode, and the one consumer's host had it
    # commented out.

    # 2026-08-19 — zellij is gone, and the two options that described its
    # in-pane behaviour go with it: `terminal.zellijStartLocked` (boot into
    # Locked input mode) and `terminal.rightClickFullscreen` (a bare
    # right-click zooms a pane, which was a zellij-unwrapped patch rather than
    # a config toggle). Both were public and desktop-safe, and both shipped
    # desktops set them.
    #
    # No entry, and not for want of trying: `mkRemovedOptionModule` — which
    # would turn "unknown option" into a sentence saying what happened — defines
    # `config.assertions`, and this file is imported by
    # modules/options-modules.nix into the PURE-LIB evals that render the
    # options reference and the agent skill. Those have no nixpkgs module behind
    # them and therefore no `assertions` option, so the whole options surface
    # stops evaluating on Linux CI. A removal notice is not worth breaking the
    # renderer for, and it would be the only entry here that isn't a rename.
    #
    # Neither has a successor to rename to anyway: Ghostty has no input modes,
    # and a window is the pane now, so "fullscreen" is haus.windows' own chord.

    # 2026-08-31 — haus no longer picks a video player. `haus.apps.videoPlayer`
    # and its `claimFileTypes` half are gone, and so is everything the pick
    # carried: the `iina` roster entry, the thirteen duti bindings it re-asserted
    # on every activation, and the lsregister pass that kept them resolving. The
    # only file types haus claims now are the editor hijack's
    # (`haus.terminal.hijackFileAssociations`), which is what the exclusion list
    # in modules/apps was written around.
    #
    # No entry, for the renderer reason the zellij removal spells out above:
    # `mkRemovedOptionModule` defines `config.assertions`, and this file is
    # imported into pure-lib evals that have none. A host still setting either
    # leaf gets the module system's own unknown-option error, which names the
    # file and the line.
    #
    # This one DOES take the app with it, unlike a cask pick, and the difference
    # is worth knowing before removing the next one: the entry carried
    # `package = pkgs.iina`, so modules/roster routed it to `home.packages` and
    # home-manager linked it into ~/Applications/Home Manager Apps. Drop the
    # entry and the next generation drops the symlink. "haus never deletes apps"
    # is `haus.homebrew.cleanup = "none"`, a promise about CASKS, and it does not
    # reach a nixpkgs install. What outlives the rebuild is the thirteen
    # associations — they are the ordinary user default, now pointing at a bundle
    # that is going away — so Finder's Get Info ▸ Change All is the one by-hand
    # step, and reinstalling is the palette's Install App (VLC is on that shelf)
    # or a roster entry of your own.

    # 2026-08-13 — the whole coding-agent capability became `haus.ai.*`, and
    # deliberately got NO alias here. `haus.agents.*` and
    # `haus.developer.agents.enable` are gone rather than deprecated: haus
    # has one consumer, its host moved in the same change, and an alias set for
    # a five-day-old spelling would be permanent furniture bought to protect
    # nobody.
  ];
}
