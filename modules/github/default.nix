# The GitHub room — this machine's webhook endpoint, and the one signal every
# surface that watches GitHub reads.
#
# ── what was here before ─────────────────────────────────────────────────────
# A raw `launchd.user.agents` stanza in a host file, running a Cloudflare tunnel
# for an app's private receiver, with a comment on it explaining that it had
# been deleted once by someone who could not tell what it was for. That is the
# failure mode this room fixes first: anything a machine RUNS deserves an
# address, because config nobody can name is config somebody eventually reaps.
#
# ── the shape ────────────────────────────────────────────────────────────────
#
#   GitHub ──▶ cloudflared ──▶ 127.0.0.1:<port> ──▶ receiver
#                                                    ├─▶ forwardTo   (raw bytes,
#                                                    │               signature and
#                                                    │               all — trill)
#                                                    ├─▶ subscribers (rooms, via
#                                                    │               _contrib)
#                                                    └─▶ state/last  (the signal
#                                                                    everything
#                                                                    else reads)
#
# Three deliberate absences, each of which was the tempting version:
#
#   no token          nothing here can change anything on GitHub. `hooks` is a
#                     declaration of intent, `haus doctor` prints the `gh`
#                     command that closes a gap, and a person runs it. An action
#                     that reaches off this Mac, that `haus rollback` cannot
#                     undo, and that needs a scope the machine may not have, is
#                     a card the user plays.
#   no mapper         the receiver reads two top-level fields of a payload and
#                     nothing else. Turning a delivery into MEANING is an app's
#                     job — trill already quarantines those shapes in one file —
#                     and a second mapper here would be a copy that drifts,
#                     inside a nix-darwin module, where the only symptom is a
#                     notification that quietly stopped arriving.
#   no room reads     the bar and the AI room learn about deliveries through
#     another room's  `haus._contrib.github.subscribers`, the same contract every
#     config         other cross-room feature in this repo uses. This room does
#                     not know a bar exists.
#
# ── push shortens a poll, it never removes one ───────────────────────────────
# The invariant the whole consumer side is built on. GitHub sends no heartbeat,
# so "no deliveries because nothing happened" and "no deliveries because the
# tunnel died" are the same silence. Every surface therefore keeps a slow poll
# under the bridge (`haus.github.backstop`) and coverage EXPIRES if it stops
# being confirmable — see signal.sh's header for how that falls closed.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.github;
  swiftBin = pkgs.callPackage ../lib/swift-bin.nix { };

  home = "/Users/${username}";
  stateDir = "${home}/.local/state/haus/github";
  configDir = "${home}/.config/haus/github";
  subscribersDir = "${configDir}/subscribers";
  secretFile = "${stateDir}/secret";

  # ---- where the HMAC secret comes from --------------------------------------
  # An empty `secretCommand` no longer means "misconfigured": it means this room
  # asks the secrets room to hold the value, which is what the declaration below
  # does. So there are two shapes here, and the room only DECLARES a need in the
  # first — a host that fetches the secret its own way is not asking haus to
  # hold one, and a manifest entry nothing reads would be a value the wizard
  # asks for and never uses.
  secretName = "GITHUB_WEBHOOK_SECRET";
  hausHoldsSecret = cfg.secretCommand == "";
  secretCommand =
    if hausHoldsSecret then
      "haus-secret --reason ${lib.escapeShellArg "haus-github-receiver: verify the signature on incoming GitHub deliveries"} ${secretName}"
    else
      cfg.secretCommand;
  # The same thing said to a PERSON, in the manual-click card below: the reason
  # above is for the audit log, not for a reader following instructions.
  secretShowCommand = if hausHoldsSecret then "haus-secret ${secretName}" else cfg.secretCommand;

  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  # See receiver.swift for what it does and why the fan-out is bytes rather
  # than events.
  receiver = swiftBin {
    name = "haus-github-receiver";
    src = ./receiver.swift;
    description = "Verify, record and fan out GitHub webhook deliveries on loopback";
  };

  # One body, two doors: this is the same file the surfaces source, so a person
  # debugging the bridge runs exactly what the bar runs.
  #
  # `HAUS_UI_SH` is prepended rather than wrapped — the same shape
  # modules/ai/default.nix uses for the statusline, and for the same reason: the
  # script is `readFile`d into the store, so it has nothing to look beside.
  # `:-` so the environment still wins, and the file the SURFACES source (the
  # `~/.config/haus/github/signal.sh` copy below) is untouched by this: its half
  # never draws, and its `[ -r ]` guard leaves it plain either way.
  signalBin = pkgs.writeShellScriptBin "github-signal" (
    ''
      HAUS_UI_SH="''${HAUS_UI_SH:-${pkgs.snug}/share/ui.sh}"
    ''
    + builtins.readFile ./signal.sh
  );

  credentialsFile =
    if cfg.tunnel.credentialsFile != "" then
      cfg.tunnel.credentialsFile
    else
      "${home}/.cloudflared/${cfg.tunnel.id}.json";

  # ---- what the sourced half of signal.sh reads ------------------------------
  # A generated shell file rather than values baked into signal.sh, for the same
  # reason the bar generates `github_config.sh`: the script is `readFile`d into
  # a package, so baking the numbers in would rebuild (and re-hash) the binary
  # every time a host retuned an interval.
  signalConfig = ''
    # GENERATED from haus.github.* by modules/github/default.nix — do not edit.
    HAUS_GH_STATE="${stateDir}"
    HAUS_GH_CONFIG="${configDir}"
    HAUS_GH_BACKSTOP="${toString cfg.backstop}"
    HAUS_GH_COVERAGE_REFRESH="${toString cfg.coverageRefresh}"
    HAUS_GH_HOSTNAME="${cfg.tunnel.hostname}"
    HAUS_GH_PORT="${toString cfg.port}"
  '';

  # One row per declared hook: `<scope>\t<events,csv>`. Tab-separated and read by
  # `while IFS=$'\t' read`, so an event list stays one field even empty.
  hooksTsv = lib.concatMapStrings (
    hook: "${hook.scope}\t${lib.concatStringsSep "," hook.events}\n"
  ) cfg.hooks;

  # ---- the receiver's wrapper ------------------------------------------------
  # The secret is fetched HERE rather than in an activation script, and that is
  # the load-bearing choice: activation runs as root, and the answer to
  # `secretCommand` is `haus-secret`, which on the default provider reads the
  # user's login keychain. Root cannot. Running it from the agent also means a
  # rotated secret is one `launchctl kickstart` away instead of a rebuild.
  #
  # Exit 78 is EX_CONFIG — "there is no secret, and there is no reduced-function
  # receiver that skips signature checks". ThrottleInterval keeps KeepAlive from
  # turning that honest refusal into a spin.
  receiverWrapper = pkgs.writeShellScript "haus-github-receiver-start" ''
    set -u
    export PATH="${userPath}"
    umask 077
    mkdir -p "${stateDir}"
    chmod 700 "${stateDir}"

    if secret=$(${secretCommand} 2>/dev/null) && [ -n "$secret" ]; then
      printf '%s' "$secret" >"${secretFile}.new" && mv -f "${secretFile}.new" "${secretFile}"
    fi
    rm -f "${secretFile}.new"

    if [ ! -s "${secretFile}" ]; then
      echo "haus-github-receiver: no secret from \`${secretCommand}\` and none cached" >&2
      exit 78
    fi

    exec ${receiver}/bin/haus-github-receiver \
      --port ${toString cfg.port} \
      --secret-file "${secretFile}" \
      --state "${stateDir}" \
      --subscribers "${subscribersDir}" \
      ${lib.concatMapStringsSep " " (target: "--forward ${lib.escapeShellArg target}") cfg.forwardTo}
  '';

  coverageRefresher = pkgs.writeShellScript "haus-github-coverage" ''
    set -u
    export PATH="${userPath}"
    exec ${signalBin}/bin/github-signal refresh
  '';

  tunnelConfig = ''
    # GENERATED from haus.github.tunnel.* by modules/github/default.nix.
    # The credentials this names are cloudflared's own, written by
    # `cloudflared tunnel create` and never read by haus.
    tunnel: ${cfg.tunnel.id}
    credentials-file: ${credentialsFile}

    ingress:
      - hostname: ${cfg.tunnel.hostname}
        service: http://127.0.0.1:${toString cfg.port}
      - service: http_status:404
  '';

  # ---- subscribers -----------------------------------------------------------
  # One executable per contributing room, named for its key so the receiver's
  # sorted walk is stable and a person reading the directory can tell who asked
  # for what. The event filter is applied HERE rather than in each subscriber:
  # a room saying "wake me for workflow_run" should not also have to write the
  # `case` that ignores everything else.
  subscriberFiles = lib.mapAttrs' (
    key: entry:
    lib.nameValuePair "${lib.removePrefix "${home}/" subscribersDir}/${key}" {
      executable = true;
      text = ''
        #!/bin/bash
        # GENERATED from haus._contrib.github.subscribers.${key}.
        set -u
        export PATH="${userPath}"
        ${lib.optionalString (entry.events != [ ]) ''
          case " ${lib.concatStringsSep " " entry.events} " in
            *" ''${HAUS_GITHUB_EVENT:-} "*) ;;
            *) exit 0 ;;
          esac
        ''}
        ${entry.command}
      '';
    }
  ) config.haus._contrib.github.subscribers;
in
lib.mkMerge [
  # ---- assertions -----------------------------------------------------------
  # The tunnel's two, and not the secret's any more. There is still no degraded
  # receiver that accepts unsigned deliveries — but "no secret yet" stopped
  # being a build-time fact when the secrets room grew a deck: this room
  # declares the value it needs, the receiver stays dormant with exit 78 until
  # somebody enters it, and the manual-click deck is what asks. Refusing to
  # BUILD a machine over a value that is entered after the first rebuild is the
  # wrong end of that (AGENTS.md, "Room A needs a capability room B provides" —
  # functional, with a substitute).
  {
    assertions = [
      {
        assertion = !cfg.tunnel.enable || cfg.enable;
        message = "haus.github.tunnel.enable is on but haus.github.enable is off, so the tunnel would forward deliveries to a port nothing is listening on.";
      }
      {
        assertion = !cfg.tunnel.enable || (cfg.tunnel.id != "" && cfg.tunnel.hostname != "");
        message = "haus.github.tunnel.enable needs both haus.github.tunnel.id (the UUID `cloudflared tunnel create` printed) and haus.github.tunnel.hostname (the public name it answers on).";
      }
    ];

    warnings = lib.optional (cfg.enable && cfg.hooks == [ ]) ''
      haus.github.enable is on with no haus.github.hooks declared, so nothing can ever be reported as covered and every surface keeps polling at its un-bridged interval. Deliveries still arrive and still forward; what is missing is the machine's permission to trust them.
    '';
  }

  (lib.mkIf cfg.enable {
    # `github-signal` on PATH is the same body the surfaces source — one file,
    # two doors, so a person debugging the thing runs exactly what the bar runs.
    environment.systemPackages = [
      receiver
      signalBin
    ];

    launchd.user.agents.haus-github-receiver = {
      serviceConfig = {
        ProgramArguments = [ "${receiverWrapper}" ];
        RunAtLoad = true;
        KeepAlive = true;
        # A machine with no secret yet parks with EX_CONFIG rather than spinning.
        ThrottleInterval = 60;
        StandardOutPath = "${home}/Library/Logs/haus-github-receiver.log";
        StandardErrorPath = "${home}/Library/Logs/haus-github-receiver.log";
        EnvironmentVariables.PATH = userPath;
      };
    };

    # Coverage is the slow question — "may a surface stop polling" — and it is
    # asked on a timer rather than by whoever happens to render first. That is
    # what keeps it off every render path AND makes the answer the same for all
    # of them.
    launchd.user.agents.haus-github-coverage = {
      serviceConfig = {
        # A store path, not `/bin/bash -lc`. A login shell would source
        # /etc/profile and the user's own dotfiles to find `github-signal` —
        # files haus does not own, in a job whose failure mode is that coverage
        # silently never refreshes and every surface keeps polling forever with
        # nothing anywhere saying why.
        ProgramArguments = [ "${coverageRefresher}" ];
        RunAtLoad = true;
        StartInterval = cfg.coverageRefresh;
        StandardOutPath = "${home}/Library/Logs/haus-github-coverage.log";
        StandardErrorPath = "${home}/Library/Logs/haus-github-coverage.log";
        EnvironmentVariables.PATH = userPath;
      };
    };

    home-manager.users.${username}.home.file = lib.mkMerge [
      {
        ".config/haus/github/config.sh".text = signalConfig;
        ".config/haus/github/hooks.tsv".text = hooksTsv;
        ".config/haus/github/signal.sh".source = ./signal.sh;
      }
      subscriberFiles
      (lib.mkIf cfg.tunnel.enable {
        ".config/haus/github/tunnel.yml".text = tunnelConfig;
      })
    ];

    # The hook itself. Advisory by construction: the card prints the command, a
    # person runs it. `check` costs one authenticated API call per declared hook
    # and prompts for nothing, which is the deck's rule.
    haus._contrib.permissions.github-hook = {
      order = 60;
      title = "Webhook — GitHub";
      why = ''
        This Mac can receive GitHub events directly instead of asking every few
        seconds whether anything changed. That needs a webhook on GitHub's side,
        pointing at your tunnel and signed with the same secret this machine
        holds. haus never creates it: it holds no GitHub token, and a rebuild
        should not be able to change something on an account.
      '';
      cost = "the bar's GitHub pill, the agent statusline and the lanes popup keep polling — slower to notice a merge, and more of your API budget";
      # Gated on the SYMPTOM, not the platform: with no hooks declared there is
      # nothing this card could ask anyone to do, and a card nobody can act on
      # teaches people to skip the ones they can.
      applies = "command -v gh >/dev/null 2>&1 && [ -s ${lib.escapeShellArg "${configDir}/hooks.tsv"} ]";
      # `check`, not `[ -z "$(… drift)" ]`. drift REFRESHES — one API call per
      # hook, and it rewrites the `scopes` file three other surfaces read — and
      # it used to print nothing for the two verdicts that carry no fix command
      # (`unreadable`, `bad-scope`), so the card drew a green tick in exactly the
      # states a fresh install lands in. `check` is read-only and treats "never
      # confirmed" as not done.
      check = "github-signal check";
      detail = "github-signal drift 2>/dev/null | sed 's/^/run: /'";
      steps = [
        "Run the command printed above — it creates or repairs the hook with the events this machine reads"
        "Set the hook's secret to the same value `${secretShowCommand}` prints"
        "`github-signal status` should then show the scope as covered within the hour"
      ];
    };

    # What this room needs from the secrets room, in the secrets room's own
    # words: a NEED, never a value. Only when haus is the one holding it — see
    # `hausHoldsSecret` above.
    haus._contrib.secrets.github-webhook = lib.mkIf hausHoldsSecret {
      name = secretName;
      why = ''
        Signs the events GitHub sends this Mac. The same string goes in the
        webhook's own settings on GitHub and stays here; every delivery carries
        an HMAC of its body under it, and the receiver drops anything that does
        not match — which is the entire reason a public hostname pointed at
        your laptop is safe.
      '';
      cost = "the receiver refuses to start, so deliveries go nowhere and every surface that watches GitHub keeps polling";
      obtain = "make one up (`openssl rand -hex 32`), then paste the same value into the hook on GitHub";
    };

    haus._contrib.permissions.github-tunnel = lib.mkIf cfg.tunnel.enable {
      order = 61;
      title = "Tunnel — cloudflared";
      why = ''
        GitHub has to be able to reach this Mac, and a laptop has no stable
        address. cloudflared answers on ${cfg.tunnel.hostname} and forwards to a
        loopback port here. Creating the tunnel is a one-time errand with a
        browser in it, so haus writes the routing config and leaves the
        credentials to you.
      '';
      cost = "no delivery ever arrives, and every surface stays on its polling interval";
      check = "[ -s ${lib.escapeShellArg credentialsFile} ]";
      steps = [
        "cloudflared tunnel login"
        "cloudflared tunnel create ${cfg.tunnel.id}  (or reuse an existing one and set haus.github.tunnel.id to its UUID)"
        "cloudflared tunnel route dns ${cfg.tunnel.id} ${cfg.tunnel.hostname}"
      ];
    };
  })

  (lib.mkIf (cfg.enable && cfg.tunnel.enable) {
    # Gated on the credentials file rather than on a build-time fact: a machine
    # that has not run the one-time bootstrap gets a DORMANT agent, not a crash
    # loop. PathState is launchd's own answer to that, and it wakes the agent by
    # itself the moment the file appears.
    launchd.user.agents.haus-github-tunnel = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.cloudflared}/bin/cloudflared"
          "--config"
          "${configDir}/tunnel.yml"
          "tunnel"
          "run"
          cfg.tunnel.id
        ];
        RunAtLoad = true;
        KeepAlive.PathState.${credentialsFile} = true;
        StandardOutPath = "${home}/Library/Logs/haus-github-tunnel.log";
        StandardErrorPath = "${home}/Library/Logs/haus-github-tunnel.log";
        EnvironmentVariables.PATH = userPath;
      };
    };
  })
]
