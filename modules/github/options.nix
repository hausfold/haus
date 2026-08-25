# The GitHub room's options: this machine's webhook endpoint.
#
# The room exists because the alternative was what this Mac actually had — a raw
# `launchd.user.agents` stanza in a host file, running a tunnel nobody could
# name, which was deleted once by someone reasonably concluding it was dead
# wiring. Anything a machine runs deserves an address; this is that address.
#
# ── the one rule the whole surface is shaped by ──────────────────────────────
# **haus never writes to GitHub.** Not the hook, not a label, not a comment. The
# receiver holds no token and makes no API call, and `hooks` below is a
# DECLARATION of what this machine wants to exist rather than a thing haus will
# go and create. `haus doctor` diffs the declaration against what is really
# there and prints the one `gh` command that closes the gap; a person runs it.
#
# That is not squeamishness, it is the same rule the manual-click deck follows
# for TCC grants: an action that reaches outside this Mac, that `haus rollback`
# cannot undo, and that needs a scope the machine may not have, is a card the
# user plays — not a side effect of a rebuild they ran for an unrelated reason.
{ lib, ... }:
let
  contrib = import ../lib/contrib.nix { inherit lib; };
in
{
  options.haus = {
    # ---- what other rooms hear ------------------------------------------------
    # A DECK, not a single feature: the bar wants its octocat pill repainted, the
    # AI room wants its lane cache warmed, and neither knows the other exists —
    # which is exactly the case `mkExtensionRegistry` is for. This room renders
    # each entry into an executable the receiver runs, and never learns what any
    # of them are for.
    _contrib.github.subscribers = contrib.mkExtensionRegistry {
      description = ''
        One thing to run when a verified delivery arrives, contributed by the
        room that wants to know. Run DETACHED and never waited on — GitHub gives
        a delivery about ten seconds and marks a hook unhealthy when responses
        stop, so a slow subscriber must not be able to spend that budget.

        Key it after the room and the thing ("bar-github-pill"), never after the
        event: two rooms wanting `workflow_run` is the normal case, and a bare
        event name would silently let the second one win.
      '';
      options = {
        events = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "workflow_run" ];
          description = ''
            GitHub event names this subscriber cares about; empty means all of
            them. The filter is applied by the generated wrapper, so a room
            never writes the `case` that ignores everything else.
          '';
        };

        command = lib.mkOption {
          type = lib.types.lines;
          description = ''
            Shell to run. `HAUS_GITHUB_EVENT`, `HAUS_GITHUB_SCOPE` (the
            `owner/name` or org the delivery was about), `HAUS_GITHUB_DELIVERY`
            and `HAUS_GITHUB_AT` are in the environment.

            Keep it a POKE rather than the work itself. The surfaces already
            know how to refresh; what they lack is a reason to, and the cheapest
            correct subscriber is the one that hands them that reason and exits.
          '';
        };
      };
    };

    github.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Receive GitHub webhook deliveries on this machine.

        GitHub → a Cloudflare tunnel → a loopback receiver here, which proves
        the delivery's signature, writes down that it happened, forwards the raw
        bytes to anything in `forwardTo`, and wakes whichever rooms asked to
        hear about it. Nothing on GitHub changes: there is no token anywhere in
        this room.

        What it buys is latency and quiet. The surfaces that watch GitHub — the
        bar's octocat pill, the agent statusline's PR column, the lanes popup —
        all poll, because a poll is the only thing that works with no bridge.
        With one, they poll on a long backstop and refresh the moment something
        actually happens, which is both faster to notice a merge and far less
        traffic on your API budget.

        Needs `secretCommand` set: the delivery signature is the entire auth
        story, so a receiver with no secret is a receiver that would have to
        trust anyone who found the hostname.
      '';
    };

    github.port = lib.mkOption {
      type = lib.types.port;
      default = 42786;
      example = 8099;
      description = ''
        The loopback port the receiver binds. Never exposed: the public leg is
        the tunnel's, and the socket is 127.0.0.1 only.

        It is an option because it has to agree with two other things — the
        tunnel's ingress (which this room writes, so that half is automatic) and
        whatever else on the Mac already wants the port. trill's own GitHub
        bridge listens on 42787, which is why the default sits one below it:
        the usual arrangement is deliveries landing here and being forwarded
        there, and the two cannot share a socket.
      '';
    };

    github.secretCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "secretspec get github_webhook_secret";
      description = ''
        Shell printing the webhook's HMAC secret on stdout — the same string
        entered in GitHub's hook settings. Run once per activation, and its
        output is written to `~/.local/state/haus/github/secret` (mode 600),
        which is what the receiver reads.

        A command rather than a value so the secret never enters the Nix store,
        where it would be world-readable and preserved in every generation.
        `secretspec get <name>` is the intended shape — `haus.secrets.provider`
        already decides where that reads from on this machine.

        An empty command with the room enabled is an error rather than a
        degradation: there is no reduced-function receiver that skips signature
        checks, and there should not be.
      '';
    };

    github.forwardTo = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "127.0.0.1:42787" ];
      description = ''
        Where to repeat each verified delivery, verbatim — same body, same
        `X-Hub-Signature-256`, same event and delivery headers — as `host:port`.

        Verbatim is the point. The far end verifies the signature itself and
        trusts nothing about this process, so putting haus's receiver in front
        of an app that already speaks GitHub webhooks changes nothing about that
        app. `127.0.0.1:42787` is trill's own bridge, which is the case this
        exists for: trill keeps mapping deliveries into banners exactly as it
        did when GitHub called it directly.

        Fire-and-forget, five second timeout, and never waited on: a slow
        forward target must not be able to spend GitHub's delivery timeout.
      '';
    };

    github.hooks = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            scope = lib.mkOption {
              type = lib.types.str;
              example = "org:hausfold";
              description = ''
                What the hook is attached to: `org:<name>` for an organisation
                hook (which covers every repository in it, including ones
                created later) or `repo:<owner>/<name>` for a single repository.
              '';
            };

            events = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "issue_comment"
                "pull_request"
                "pull_request_review"
                "pull_request_review_comment"
                "workflow_run"
              ];
              example = [ "pull_request" ];
              description = ''
                The GitHub event names the hook should be subscribed to, spelled
                as GitHub spells them.

                The default is the set the surfaces in this house actually read:
                pull request lifecycle and reviews for "is this landable", CI
                runs for "is main red", comments for "did someone say my name".
                `pull_request_review` earns its place specifically — approvals
                are what turn a row green, and a hook without it looks like it
                is working while the one state you check most never arrives.
              '';
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          scope = "org:hausfold";
          events = [
            "pull_request"
            "workflow_run"
          ];
        }
      ];
      description = ''
        The hooks this machine WANTS to exist on GitHub. Declaring one creates
        nothing: haus holds no token and never writes to GitHub. What the
        declaration does is make two questions answerable.

        The first is coverage. A room only stops polling a repository once
        something says deliveries for it will actually arrive, and "an active
        hook whose scope covers this repository, whose event list includes what
        I read, and whose last delivery GitHub did not record as failed" is that
        something. `github-signal` asks GitHub for those facts on a slow timer
        and caches the answer; the surfaces read the cache.

        The second is drift. `haus doctor` diffs this list against the hooks
        that really exist and prints the `gh api` command that closes the gap —
        a missing event being the failure worth catching, because a hook
        subscribed to four of the five events you care about looks entirely
        healthy from every side.
      '';
    };

    github.backstop = lib.mkOption {
      type = lib.types.ints.between 60 3600;
      default = 300;
      example = 900;
      description = ''
        How long a covered surface may go without asking GitHub anyway, in
        seconds.

        Push shortens a poll; it never removes one. Nothing distinguishes "no
        deliveries because nothing happened" from "no deliveries because the
        tunnel died" — GitHub sends no heartbeat — so every consumer keeps a
        slow poll under the bridge and this is it. Raise it if you trust the
        tunnel and want the quiet; lower it toward the un-bridged interval if a
        stale readout would cost you something.
      '';
    };

    github.coverageRefresh = lib.mkOption {
      type = lib.types.ints.between 300 86400;
      default = 3600;
      example = 21600;
      description = ''
        How often, in seconds, to re-ask GitHub what the declared hooks look
        like — are they active, what events are they subscribed to, did the last
        delivery land.

        Slow on purpose. It is the answer to "may I stop polling", which changes
        on a human cadence (someone edits a hook) rather than a machine one, and
        it costs an authenticated API call per declared hook. Consumers never
        make this call themselves; they read its cached answer.
      '';
    };

    github.tunnel.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run `cloudflared` for the hook's public hostname, pointed at the
        receiver's loopback port.

        haus writes the ingress config (hostname → `127.0.0.1:<port>`) so the
        port stays a single number in one place, but it never creates the
        tunnel or its credentials: `cloudflared tunnel login`, `tunnel create`
        and `tunnel route dns` are a one-time errand with a browser in it, and
        `haus doctor` carries the card that says so. Until the credentials file
        exists the agent stays dormant rather than crash-looping.

        Separate from `enable` because the two are genuinely separable: a Mac
        reachable some other way (a static address, someone else's tunnel, a
        relay) wants the receiver without this.
      '';
    };

    github.tunnel.id = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "6209f5f4-f8a2-4501-8af9-a8bb24777a89";
      description = ''
        The Cloudflare tunnel's UUID, as `cloudflared tunnel create` printed it.

        The UUID rather than the name: the name is a label that can be reused
        across accounts, and the credentials file is named for the UUID, so this
        is the one spelling where the config and the credentials cannot end up
        describing different tunnels.
      '';
    };

    github.tunnel.hostname = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "hooks.example.com";
      description = ''
        The public hostname the tunnel answers on — the same URL entered in
        GitHub's hook settings, minus the scheme and path.

        It must already be routed to the tunnel (`cloudflared tunnel route dns
        <tunnel> <hostname>`), which is part of the same one-time errand as
        creating it.
      '';
    };

    github.tunnel.credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/Users/you/.cloudflared/6209f5f4-f8a2-4501-8af9-a8bb24777a89.json";
      description = ''
        The tunnel credentials `cloudflared tunnel create` wrote. Defaults to
        `~/.cloudflared/<id>.json`, which is where it puts them.

        Named rather than inlined because it is a secret cloudflared owns and
        rotates on its own terms — haus points at it and never reads it. The
        agent is also gated on this file existing, so a machine that has not run
        the one-time bootstrap gets a dormant agent rather than a crash loop.
      '';
    };
  };
}
