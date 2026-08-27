# haus.portless — named .localhost URLs for local dev servers, with real HTTPS.
#
# One reverse proxy on :443 owns every dev server on the machine: each app
# registers `<name>` against a port the proxy assigned, and the browser reaches
# it at `https://<name>.localhost` with no port and no certificate warning.
#
# Why the layer ships it rather than leaving it a per-project devDependency: agent
# lanes. `holt` puts N agents in N worktrees of the SAME repo, which means N
# copies of the same `npm run dev` all wanting the same port — the second one
# dies with EADDRINUSE, or silently takes the next number and every hardcoded URL
# in the project now points at a different lane's server. That is a machine-wide
# collision between checkouts, so it wants a machine-wide allocator, which is
# exactly what a room is for.
#
# The daemon here is declared rather than installed by `portless service install`.
# Upstream's installer writes /Library/LaunchDaemons/sh.portless.proxy.plist by
# hand, chowns it and bootstraps it; nix-darwin already does all three, and a
# plist written by a tool outside the generation is a plist a rollback cannot
# take back. The Label is upstream's, deliberately: launchd allows exactly one
# service per label, so ours and theirs can never both be live on :443, and
# `portless doctor` recognises what it finds.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.portless;

  home = "/Users/${username}";
  stateDir = "${home}/.portless";

  # The proxy's own arguments, in upstream's spelling (dist/cli.js'
  # buildProxyStartConfig). --foreground because launchd supervises the process
  # itself and a daemon that forks and exits is a daemon launchd restarts
  # forever; --skip-trust because the trust store is the user's card below and
  # never a thing a rebuild does on its own.
  proxyArgs = [
    "proxy"
    "start"
    "--foreground"
    "--port"
    (toString cfg.port)
  ]
  ++ (if cfg.https then [ "--https" ] else [ "--no-tls" ])
  ++ lib.concatMap (tld: [
    "--tld"
    tld
  ]) cfg.tlds
  ++ [ "--skip-trust" ];

  # A script rather than a bare ProgramArguments list for one reason: the proxy
  # runs as ROOT but keeps its state in the user's home, so it needs that user's
  # uid and gid — runtime facts a static plist cannot hold. Upstream's installer
  # reads them from the sudo that elevated it; we look them up, which also lets
  # us create the state dir with the right owner before the proxy ever writes to
  # it. Without that, root's first write leaves a root-owned ~/.portless and
  # every later `portless list` from your own shell is a permission error.
  proxyDaemon = pkgs.writeShellScript "haus-portless-proxy" ''
    set -eu
    uid=$(/usr/bin/id -u ${username})
    gid=$(/usr/bin/id -g ${username})
    /bin/mkdir -p ${lib.escapeShellArg stateDir}
    /usr/sbin/chown "$uid:$gid" ${lib.escapeShellArg stateDir}
    export HOME=${lib.escapeShellArg home}
    export SUDO_UID="$uid" SUDO_GID="$gid"
    export PORTLESS_STATE_DIR=${lib.escapeShellArg stateDir}
    exec ${lib.getExe cfg.package} ${lib.escapeShellArgs proxyArgs}
  '';

  # The lane shim, with the pinned portless baked in — see portless-lane.sh for
  # why the port is chosen here rather than read back from portless.
  portlessLane = pkgs.writeShellApplication {
    name = "portless-lane";
    runtimeInputs = [ pkgs.git ];
    text = lib.replaceStrings [ "@portless@" ] [ (lib.getExe cfg.package) ] (
      builtins.readFile ./portless-lane.sh
    );
  };
in
lib.mkIf cfg.enable {
  haus.portless.package = lib.mkDefault (pkgs.callPackage ./package.nix { });

  assertions = [
    {
      assertion = cfg.lanes.enable -> config.haus.ai.enable;
      message = ''
        haus.portless.lanes.enable needs haus.ai.enable — lanes are the AI room's,
        and without it there is nothing on this machine for the shim to name.
        Turn haus.ai on, or set haus.portless.lanes.enable = false.
      '';
    }
  ];

  environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.lanes.enable portlessLane;

  launchd.daemons.portless = {
    serviceConfig = {
      Label = "sh.portless.proxy";
      ProgramArguments = [ "${proxyDaemon}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/var/log/haus-portless.log";
      StandardErrorPath = "/var/log/haus-portless.log";
    };
  };

  # The CA's card in core's manual-click deck. A card and NOT an activation step,
  # for the reason the option spells out: activation is root and could write the
  # trust store without asking, and a certificate authority the browser will
  # believe for any name is not something a machine should install while you are
  # looking the other way.
  haus._contrib.permissions.portless-ca = lib.mkIf (cfg.trustCA && cfg.https) {
    order = 45;
    title = "Trust the local certificate authority — portless";
    why = ''
      portless serves your dev servers over real HTTPS, signing each hostname
      with a certificate authority it generated on this Mac. Until that CA is
      trusted, every .localhost name opens on a browser warning instead of your
      app.
    '';
    cost = "every dev URL opens with a certificate warning you have to click through";
    # Read-only and silent: `security find-certificate` reads the System keychain
    # and never prompts, which is the one hard rule a card's check has to keep.
    # It answers "is the CA installed", which is the whole question — trust
    # settings and the certificate arrive together through `portless trust`.
    check = ''
      /usr/bin/security find-certificate -c "portless Local CA" \
        /Library/Keychains/System.keychain >/dev/null 2>&1
    '';
    prompt = "${lib.getExe cfg.package} trust";
    promptLabel = "Trust the portless CA now";
    steps = [
      "Approve the macOS prompt — it is adding one certificate authority to the System keychain"
      "Undo it any time with `portless clean`, which removes the CA along with portless' other state"
    ];
  };
}
