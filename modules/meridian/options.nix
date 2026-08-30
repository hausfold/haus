# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# meridian's options — a local Anthropic API served from your Claude Max
# subscription.
#
# They are spelled `haus.ai.meridian.*` while the files live in
# `modules/meridian/`, which is the one place in this repo where the namespace
# and the directory disagree. Both halves are deliberate: the ADDRESS belongs
# under `haus.ai` because "which endpoint do this machine's agents talk to" is
# the AI room's question and nobody would look for it anywhere else, and the
# FILES sit apart because the payload is a room's worth of its own — an npm
# derivation, a committed lockfile and a launchd agent — and folding it into
# modules/ai would bury it inside the largest room in the house. The room
# registry keys on namespaces rather than directories, so it needs nothing
# said twice.
{ lib, ... }:

{
  options.haus.ai.meridian = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve your Claude Max subscription to every Anthropic-compatible client
        on this Mac, from a proxy on loopback. Point a tool at
        `http://127.0.0.1:3456` with any API key and it talks to your
        subscription rather than to a metered API key — which is what makes an
        agent that is not Claude Code (pi, opencode, crush, an editor plugin)
        cost what the subscription already costs instead of billing per token.

        It is not an agent and does not need one: `haus.ai.enable` is about
        whether this machine runs coding agents, and this is an ENDPOINT that is
        useful to anything speaking the Anthropic wire format. So the two
        switches are independent — turning agents off never takes the proxy away
        from a client haus does not install.

        The credential is Claude Code's. meridian reads the OAuth token out of
        the login keychain (`Claude Code-credentials`) or
        `~/.claude/.credentials.json`, which is why this is a per-user launchd
        agent rather than a daemon: a root daemon can see neither. Signing in is
        a card in `haus permissions` — until you have, the proxy answers 401 and
        the clients pointed at it look broken.

        haus does not point anything at it. The file that tells a client to use
        the proxy is that client's own (`~/.pi/agent/models.json`,
        `~/.config/opencode/…`) and haus writes none of them — see the AI room's
        `clientScopeNote`. This room's job ends at "the port answers".

        One thing haus does add to traffic you have already pointed here: pi's
        extension stamps `x-session-affinity` on requests that already carry
        `x-meridian-agent: pi`, without which meridian replays the whole
        conversation every turn instead of resuming its SDK session — see
        `modules/terminal/pi/agent-state.ts`. It never makes a client address
        this proxy; it only stops one that already does from paying for every
        cache write twice. `HAUS_PI_SESSION_AFFINITY=0` turns it off.
      '';
    };

    # INTERNAL, for exactly the reason `haus.portless.package` is: the
    # `<option>Name` sibling every other package option carries exists so a
    # data-only desktop can name a package by string and have pkg-by-name
    # resolve it, and that presumes the package is IN nixpkgs. meridian is not;
    # the room builds it from the npm registry tarball against a lockfile it
    # commits (modules/meridian/package.nix). A string naming it would resolve
    # to nothing, so there is a pin here and no knob. Override it the way you
    # override any unlisted build: an overlay, or set this from a module that
    # has `pkgs`.
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      defaultText = lib.literalExpression "haus's pinned meridian build";
      description = ''
        The meridian build to install. Pinned rather than resolved from PATH
        because the agent starts at login, where a per-user Node version manager
        (fnm, nvm, volta) does not exist — see modules/meridian/package.nix.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3456;
      description = ''
        The port the proxy listens on, upstream's default. Every client you
        point at it names this number, so moving it means editing each of those
        files by hand — it is here for the machine that already has something on
        3456, not as a thing to tune.

        The bind address is 127.0.0.1 and is not an option. A proxy that answers
        for your subscription with no authentication is safe on loopback and is
        an open account on any other interface, so this room does not offer the
        leaf that would make that a one-word change.
      '';
    };
  };
}
