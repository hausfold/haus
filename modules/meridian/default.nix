# haus.ai.meridian — a local Anthropic API served from your Claude Max
# subscription.
#
# One loopback proxy owns the machine's answer to "where does an agent send its
# requests": a client points at `http://127.0.0.1:3456` with any API key, and
# meridian answers it by driving Claude Code under your subscription. The point
# is the agents that are NOT Claude Code — pi, opencode, an editor plugin — which
# otherwise need a metered API key to do what the subscription already pays for.
#
# A per-user AGENT, never a daemon, and that is a correctness constraint rather
# than a preference. meridian authenticates by reading Claude Code's OAuth token
# out of the login keychain (`security find-generic-password -s
# "Claude Code-credentials"`), falling back to `~/.claude/.credentials.json`.
# Both are the user's: root has no login keychain and reads neither, so a
# `launchd.daemons` entry would start cleanly, bind the port, and 401 every
# request forever. portless is the other way round for the same kind of reason —
# it needs :443, which needs root — and the two rooms landing on opposite
# answers is the rule working, not an inconsistency.
#
# The agent is DECLARED rather than installed by hand. The trial install this
# replaces wrote `~/Library/LaunchAgents/co.hausfold.meridian.plist` itself,
# which is a plist a rollback cannot take back — and it carried
# `KeepAlive.SuccessfulExit = false`, so the first SIGTERM (a logout, a
# `killall`, a graceful shutdown) exited 0 and launchd left it down with nothing
# saying why. `KeepAlive = true` here is that bug's fix: the only exit that is
# supposed to be final is the one where launchd tears the domain down anyway.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.ai.meridian;

  home = "/Users/${username}";
  # `haus-meridian.log`, not `meridian.log`, for two reasons pointing the same
  # way: every other user agent this house owns is named `haus-<thing>.log`
  # (github's three, portless' /var/log one), and `meridian.log` is the file the
  # hand-rolled install below has already written a megabyte into — sharing it
  # would interleave this agent's first lines with the old one's history and
  # make "did it start?" unanswerable by `tail`.
  logFile = "${home}/Library/Logs/haus-meridian.log";

  # A launchd GUI agent's PATH is bare (/usr/bin:/bin:/usr/sbin:/sbin), and
  # meridian spawns Claude Code, which shells out to the developer tools a
  # session expects to have. The wrapper in package.nix already puts the pinned
  # node in front of whatever this is, so nothing here can change which node the
  # proxy itself runs on.
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
in
lib.mkIf cfg.enable {
  haus.ai.meridian.package = lib.mkDefault (pkgs.callPackage ./package.nix { });

  # On PATH as well as under launchd: `meridian profile`, `meridian
  # refresh-token` and `meridian --version` are the person's half of this room,
  # and they have to be the SAME build the agent runs or a token refreshed by
  # hand lands somewhere the running proxy is not looking.
  environment.systemPackages = [ cfg.package ];

  launchd.user.agents.haus-meridian = {
    serviceConfig = {
      ProgramArguments = [ (lib.getExe cfg.package) ];
      RunAtLoad = true;
      # Unconditional, unlike upstream's installer — see the header. Throttled
      # because a proxy that cannot start (no credential yet, port taken) should
      # say so once every ten seconds in the log rather than spin.
      KeepAlive = true;
      ThrottleInterval = 10;
      ProcessType = "Background";
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
      EnvironmentVariables = {
        HOME = home;
        PATH = userPath;
        # Everything meridian is configured by is an environment variable; it
        # takes no flags beyond `--version` and `--help`. The bind address is
        # spelled out rather than left to the default because it is the line
        # that keeps an unauthenticated view of your subscription off every
        # other interface, and a default is a thing that can move.
        MERIDIAN_PORT = toString cfg.port;
        MERIDIAN_HOST = "127.0.0.1";
      };
    };
  };

  # The hand-rolled install this room replaces, evicted on every rebuild.
  #
  # Not tidiness: `co.hausfold.meridian` and the agent above both `RunAtLoad` on
  # the same port, so whichever loses the race gets EADDRINUSE, exits 1, and —
  # being KeepAlive — retries every ten seconds forever with nothing but the log
  # saying why. A plist written outside a generation is also a plist a rollback
  # cannot take back, which is this room's whole reason for existing; leaving one
  # in place would make its own header untrue.
  #
  # Bootout THEN unlink: the job is KeepAlive, so a copy that outlives its plist
  # holds the port until logout. Idempotent no-op once clean — the same shape
  # modules/bar uses to evict the stray Homebrew SketchyBar agent.
  #
  # The npm prefix underneath it (~/.local/meridian-trial) is SAID rather than
  # DONE. It is a directory in your own home that haus never created, it is inert
  # once nothing launches it, and haus does not take things away behind your
  # back — the same line modules/bar draws around the Homebrew formula it
  # stopped using.
  system.activationScripts.postActivation.text = ''
    uid=$(/usr/bin/id -u ${username})
    trialPlist="${home}/Library/LaunchAgents/co.hausfold.meridian.plist"
    if [ -e "$trialPlist" ]; then
      echo "[activation] meridian: evicting the hand-installed co.hausfold.meridian agent — this room declares it now" >&2
      /bin/launchctl bootout "gui/$uid/co.hausfold.meridian" 2>/dev/null || true
      /bin/rm -f "$trialPlist"
    fi
    if [ -d "${home}/.local/meridian-trial" ]; then
      echo "[activation] meridian: ${home}/.local/meridian-trial is no longer launched by anything. Remove it when you are happy with the room." >&2
    fi
  '';

  # Signing in is the one step a fresh machine needs a PERSON for, so it is a
  # card rather than an activation step — haus holds no Claude credential and
  # could not create one if it wanted to.
  haus._contrib.permissions.meridian-signin = {
    order = 46;
    title = "Sign in to Claude — meridian";
    why = ''
      meridian serves your Claude Max subscription to every client on this Mac
      by re-using Claude Code's own OAuth token. Until Claude Code has signed in
      at least once, there is no token to re-use and the proxy answers every
      request with a 401.
    '';
    cost = "every client pointed at the proxy fails to authenticate, and looks broken rather than signed out";
    # Read-only and silent: WITHOUT `-w`, `find-generic-password` reports that
    # the item exists and never reads its value, so it neither prompts nor puts
    # a keychain dialog on screen — which is the one hard rule a check has to
    # keep. `-g` or `-w` here would be exactly the prompt that teaches people to
    # stop running `haus doctor`.
    #
    # It answers "is there a token", not "may meridian read it". The ACL half
    # cannot be tested without triggering it, so the card stops at the question
    # it can ask honestly and the steps below cover the rest.
    check = ''
      /usr/bin/security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 ||
      [ -f "$HOME/.claude/.credentials.json" ]
    '';
    steps = [
      "Run `claude` in a terminal and complete `/login` — meridian reads the token that leaves behind"
      "The first request through the proxy may raise a keychain prompt; choose Always Allow, and it will not ask again"
      "Restart the proxy so it picks the new token up: `launchctl kickstart -k gui/$(id -u)/org.nixos.haus-meridian`"
    ];
  };
}
