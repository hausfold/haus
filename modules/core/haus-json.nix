# `haus-json` as a package, because two things need it on a PATH and neither
# should carry a python of its own: the wrapper around `haus` (modules/core),
# and the `haus-show` wrapper the flake exposes as `nix run …#show`, which a
# publisher's Linux CI runs. Both used to put `jq` there.
{
  pkgs,
  lib ? pkgs.lib,
}:

pkgs.writeShellScriptBin "haus-json" ''
  exec ${lib.getExe pkgs.python3} ${./haus-json.py} "$@"
''
