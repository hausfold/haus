# `nebelhaus.*` -> `haus.*`, one alias per declared option leaf.
#
# GENERATED — do not hand-edit, and do not hand-extend. Regenerate by
# enumerating the option surface from the module system itself:
#
#   nix eval --impure --raw --expr '
#     let lib = (builtins.getFlake "nixpkgs").lib;
#         ev  = lib.evalModules {
#                 modules = (import ./modules/options-modules.nix)
#                           ++ [ { _module.check = false; } ];
#               };
#         go = p: o: lib.concatLists (lib.mapAttrsToList (n: v:
#                if !(lib.isAttrs v) then [ ]
#                else if v._type or "" == "option" then [ (p ++ [ n ]) ]
#                else go (p ++ [ n ]) v) o);
#     in lib.concatStringsSep "\n" (map (lib.concatStringsSep ".") (go [ ] ev.options.haus))'
#
# Regenerating is for keeping the RENAMED set honest, not for growing it: the
# command below enumerates every `haus.*` leaf, so an option added after the
# rename comes back with an alias it was never owed — `haus.git.org` (added
# 2026-08-08) never had a `nebelhaus.` name and must not acquire one, or this
# file outlives its own deletion condition. Drop any entry the rename didn't
# create, and don't read the count below as a target: the tree grows, this
# file doesn't.
#
# NOT from `nix build .#options-json`, which is the obvious source and the wrong
# one: `optionsDoc` drops every `internal = true` option, so five leaves are
# missing from it — `_roster`, `_workspaces`, `_appWorkspace`, `_launchers`, and
# `theme.ports.handled`, which is internal WITHOUT the underscore and so escapes
# any naming heuristic too. Those five are ours; they were renamed in place
# rather than aliased, and are the reason this file had 105 entries for the
# 110-leaf tree the rename found. The tree is 111 leaves now — see the
# paragraph above for why that gap is the healthy direction.
#
# What the aliases buy: `haus.*` is canonical today, a host or rice still
# written against `nebelhaus.*` keeps evaluating (with an obsolete-option
# warning), and `~/.config/nix` can move on its own schedule instead of in a
# lockstep PR pair. Delete this file — and narrow `checkRice` to `haus` alone —
# once the last consumer has moved. See workshop notes/hausfold-rename.md 1.1a.
#
# Two things an alias cannot carry, both learned the hard way:
#   - an option's DECLARATION. `doRename`'s alias has no `default`, so
#     `options.nebelhaus.x.default` throws. Reading a VALUE is fine.
#   - `checkRice`, which string-compares the rice file's top-level key.
{ lib, ... }:
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "accessibility" "differentiateWithoutColor" ]
      [ "haus" "accessibility" "differentiateWithoutColor" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "accessibility" "increaseContrast" ]
      [ "haus" "accessibility" "increaseContrast" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "agents" "clients" ] [ "haus" "ai" "clients" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "agents" "default" ] [ "haus" "ai" "default" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "appStore" "install" ] [ "haus" "appStore" "install" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "apps" "videoPlayer" "claimFileTypes" ]
      [ "haus" "apps" "videoPlayer" "claimFileTypes" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "apps" "videoPlayer" "enable" ]
      [ "haus" "apps" "videoPlayer" "enable" ]
    )
    # Two hops in one alias: these were renamed to `haus.claude.*` here, and the
    # `claude` room then folded into `agents` (see ./moved.nix). Pointed at the
    # final address rather than chained through the intermediate one, so a rice
    # still on `nebelhaus.*` gets one warning naming where the option lives now.
    (lib.mkRenamedOptionModule [ "nebelhaus" "claude" "globalMd" ] [ "haus" "ai" "instructions" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "claude" "skill" ] [ "haus" "ai" "skill" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "collar" "enable" ] [ "haus" "collar" "enable" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "collar" "passwordlessRebuild" ]
      [ "haus" "collar" "passwordlessRebuild" ]
    )
    # Another two-hop alias, like the `claude` pair above: renamed to
    # `haus.developer.agents.enable` here, then moved again when coding agents
    # became their own room on 2026-08-13. Pointed at the final address.
    (lib.mkRenamedOptionModule [ "nebelhaus" "developer" "agents" "enable" ] [ "haus" "ai" "enable" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "developer" "enable" ] [ "haus" "developer" "enable" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "developer" "git" "enable" ]
      [ "haus" "developer" "git" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "developer" "languages" ]
      [ "haus" "developer" "languages" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "developer" "toolbelt" "enable" ]
      [ "haus" "developer" "toolbelt" "enable" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "displays" ] [ "haus" "displays" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "fonts" "mono" "name" ] [ "haus" "fonts" "mono" "name" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "fonts" "mono" "package" ]
      [ "haus" "fonts" "mono" "package" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "fonts" "mono" "packageName" ]
      [ "haus" "fonts" "mono" "packageName" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "fonts" "mono" "size" ] [ "haus" "fonts" "mono" "size" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "git" "email" ] [ "haus" "git" "email" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "git" "name" ] [ "haus" "git" "name" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "git" "shellAliases" ] [ "haus" "git" "shellAliases" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "git" "signingKey" ] [ "haus" "git" "signingKey" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "hearth" "editor" ] [ "haus" "hearth" "editor" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hearth" "ghDash" "enable" ]
      [ "haus" "hearth" "ghDash" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hearth" "hijackFileAssociations" ]
      [ "haus" "hearth" "hijackFileAssociations" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hearth" "obsidianVaults" ]
      [ "haus" "hearth" "obsidianVaults" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hearth" "zellijStartLocked" ]
      [ "haus" "hearth" "zellijStartLocked" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "homebrew" "autoUpdate" ]
      [ "haus" "homebrew" "autoUpdate" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "homebrew" "cleanup" ] [ "haus" "homebrew" "cleanup" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "homebrew" "upgrade" ] [ "haus" "homebrew" "upgrade" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hotCorners" "bottomLeft" ]
      [ "haus" "hotCorners" "bottomLeft" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hotCorners" "bottomRight" ]
      [ "haus" "hotCorners" "bottomRight" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "hotCorners" "topLeft" ] [ "haus" "hotCorners" "topLeft" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hotCorners" "topRight" ]
      [ "haus" "hotCorners" "topRight" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "hush" "enable" ] [ "haus" "hush" "enable" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "hush" "hooks" ] [ "haus" "hush" "hooks" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hush" "slack" "enable" ]
      [ "haus" "hush" "slack" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hush" "slack" "snooze" ]
      [ "haus" "hush" "slack" "snooze" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hush" "slack" "statusEmoji" ]
      [ "haus" "hush" "slack" "statusEmoji" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hush" "slack" "statusText" ]
      [ "haus" "hush" "slack" "statusText" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "hush" "slack" "tokenCommand" ]
      [ "haus" "hush" "slack" "tokenCommand" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "keys" "leader" ] [ "haus" "keys" "leader" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "keys" "leaderExtras" ] [ "haus" "keys" "leaderExtras" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "keys" "palette" ] [ "haus" "keys" "palette" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "keys" "windowNav" ] [ "haus" "keys" "windowNav" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "lock" "requirePassword" ]
      [ "haus" "lock" "requirePassword" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "lock" "requirePasswordDelay" ]
      [ "haus" "lock" "requirePasswordDelay" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "clock" "analog" ]
      [ "haus" "menuBar" "clock" "analog" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "clock" "format" ]
      [ "haus" "menuBar" "clock" "format" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "clock" "showDate" ]
      [ "haus" "menuBar" "clock" "showDate" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "clock" "showDayOfWeek" ]
      [ "haus" "menuBar" "clock" "showDayOfWeek" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "clock" "showSeconds" ]
      [ "haus" "menuBar" "clock" "showSeconds" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "airdrop" ]
      [ "haus" "menuBar" "controlCenter" "airdrop" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "batteryPercentage" ]
      [ "haus" "menuBar" "controlCenter" "batteryPercentage" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "bluetooth" ]
      [ "haus" "menuBar" "controlCenter" "bluetooth" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "displayBrightness" ]
      [ "haus" "menuBar" "controlCenter" "displayBrightness" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "focus" ]
      [ "haus" "menuBar" "controlCenter" "focus" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "nowPlaying" ]
      [ "haus" "menuBar" "controlCenter" "nowPlaying" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "menuBar" "controlCenter" "sound" ]
      [ "haus" "menuBar" "controlCenter" "sound" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "perch" "enable" ] [ "haus" "perch" "enable" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "perch" "followSystemAppearance" ]
      [ "haus" "perch" "followSystemAppearance" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "pounce" "enable" ] [ "haus" "pounce" "enable" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "pounce" "followSystemAppearance" ]
      [ "haus" "pounce" "followSystemAppearance" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "pounce" "items" ] [ "haus" "pounce" "items" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "pounce" "scale" ] [ "haus" "pounce" "scale" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "pounce" "signingIdentity" ]
      [ "haus" "pounce" "signingIdentity" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "pounce" "windowMode" ] [ "haus" "pounce" "windowMode" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "pounce" "windowSwitcher" ]
      [ "haus" "pounce" "windowSwitcher" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "prowl" "enable" ] [ "haus" "prowl" "enable" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "roster" ] [ "haus" "roster" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "screenshots" "format" ] [ "haus" "screenshots" "format" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "screenshots" "includeDate" ]
      [ "haus" "screenshots" "includeDate" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "screenshots" "location" ]
      [ "haus" "screenshots" "location" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "screenshots" "shadow" ] [ "haus" "screenshots" "shadow" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "screenshots" "thumbnail" ]
      [ "haus" "screenshots" "thumbnail" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "secrets" "provider" ] [ "haus" "secrets" "provider" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "security" "firewall" "allowSigned" ]
      [ "haus" "security" "firewall" "allowSigned" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "security" "firewall" "allowSignedApp" ]
      [ "haus" "security" "firewall" "allowSignedApp" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "security" "firewall" "blockAllIncoming" ]
      [ "haus" "security" "firewall" "blockAllIncoming" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "security" "firewall" "enable" ]
      [ "haus" "security" "firewall" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "security" "firewall" "stealthMode" ]
      [ "haus" "security" "firewall" "stealthMode" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "sill" "aiUsage" "provider" ]
      [ "haus" "sill" "aiUsage" "provider" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "sill" "battery" "hideOver" ]
      [ "haus" "sill" "battery" "hideOver" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "sill" "clock" "mode" ] [ "haus" "sill" "clock" "mode" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "sill" "elgato" "host" ] [ "haus" "sill" "elgato" "host" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "sill" "enable" ] [ "haus" "sill" "enable" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "sill" "items" ] [ "haus" "sill" "items" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "sill" "position" ] [ "haus" "sill" "position" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "snippets" "enable" ] [ "haus" "snippets" "enable" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "snippets" "matches" ] [ "haus" "snippets" "matches" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "theme" "accent" ] [ "haus" "theme" "accent" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "theme" "contrast" ] [ "haus" "theme" "contrast" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "theme" "flavor" ] [ "haus" "theme" "flavor" ])
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "theme" "ports" "enable" ]
      [ "haus" "theme" "ports" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [ "nebelhaus" "theme" "systemAppearance" ]
      [ "haus" "theme" "systemAppearance" ]
    )
    (lib.mkRenamedOptionModule [ "nebelhaus" "theme" "wallpaper" ] [ "haus" "theme" "wallpaper" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "tour" "enable" ] [ "haus" "tour" "enable" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "tour" "steps" ] [ "haus" "tour" "steps" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "ui" "scale" ] [ "haus" "ui" "scale" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "workspaces" ] [ "haus" "workspaces" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "zen" "extensions" ] [ "haus" "zen" "extensions" ])
    (lib.mkRenamedOptionModule [ "nebelhaus" "zen" "extraPolicies" ] [ "haus" "zen" "extraPolicies" ])
  ];
}
