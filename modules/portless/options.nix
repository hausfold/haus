# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# portless' options — named .localhost URLs for local dev servers.
{ config, lib, ... }:

{
  options.haus = {
    portless = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Give every local dev server a stable, named URL instead of a port
          number: `https://myapp.localhost` rather than `http://localhost:3000`,
          with real HTTPS and no browser warning. A reverse proxy on :443 routes
          each name to a port it assigned itself, so two projects that both
          default to 3000 stop fighting, a restarted server keeps the tab you had
          open, and cookies and localStorage stop leaking between apps that used
          to share an origin.

          The reason it is in haus at all is agent lanes. `scruff` puts N agents in
          N worktrees of the SAME repo, so N copies of `npm run dev` want the
          same port — the second one dies, or quietly takes 3001 and every
          hardcoded URL now points at the wrong lane. portless already knows
          about worktrees: inside one it prefixes the branch, so each lane gets
          its own hostname without anybody choosing a number. `lanes` below is
          what makes that name the lane's, rather than the branch's.

          Off by default: it runs a root daemon on :443 and puts a local
          certificate authority in your system trust store. The CA is a card in
          `haus permissions` rather than something a rebuild does behind your
          back — see `haus.portless.trustCA`.
        '';
      };

      # INTERNAL, and it is the one `package` option in haus that should be. The
      # `<option>Name` sibling every other one carries exists so a data-only
      # desktop can name a package by string and have pkg-by-name resolve it —
      # which presumes the package is IN nixpkgs. portless is not; the room
      # builds it from the npm registry tarball, hash and all
      # (modules/portless/package.nix). A string naming it would resolve to
      # nothing, so there is no knob to expose, only a pin. Override it the way
      # you override any unlisted build: an overlay, or set this from a module
      # that has `pkgs`.
      package = lib.mkOption {
        type = lib.types.package;
        internal = true;
        defaultText = lib.literalExpression "haus's pinned portless build";
        description = ''
          The portless build to install. Pinned rather than resolved from PATH
          because the daemon runs as root at boot, where a per-user Node version
          manager (fnm, nvm, volta) does not exist — see modules/portless/package.nix.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
        description = ''
          The port the proxy listens on. 443 is what makes the URLs plain
          (`https://myapp.localhost`, no `:port` suffix) and is why the daemon
          runs as root. Move it above 1024 and the daemon drops to a user agent —
          the URLs then carry the port, which costs most of the point.
        '';
      };

      https = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Serve HTTPS with HTTP/2. On means portless mints a per-hostname
          certificate from its own local CA, which is the half that needs the
          trust-store card. Off serves plain HTTP and needs no CA at all — the
          right setting if you want the naming without the certificate.
        '';
      };

      tlds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "localhost" ];
        # One line, because the host template renders each default as a single
        # commented assignment and uncomments exactly one line per option. A list
        # default that nixfmt wraps across lines leaves its own continuation
        # commented out, and `host-template`'s parse check fails — see the note
        # in modules/host-template.nix. `haus.wallpaper.debug.inputs` is the
        # other option that needs this.
        defaultText = lib.literalExpression ''[ "localhost" ]'';
        example = [
          "localhost"
          "dev.example.com"
        ];
        description = ''
          The suffixes routes are served under, first one primary. `.localhost`
          is the one that needs no DNS at all — browsers resolve it to 127.0.0.1
          by rule, not by lookup. Anything else has to resolve some other way,
          which on this machine means `portless hosts sync`.
        '';
      };

      trustCA = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to put a card in `haus permissions` for the one-time
          `portless trust` — adding portless' local CA to the system trust store,
          which is what stops the browser warning on every `.localhost` name.

          A CARD and not an activation step, deliberately. A rebuild runs as root
          and could write the trust store without asking; a certificate authority
          your browser will believe for anything is not a thing a machine should
          install while you are looking the other way. Set this false if you would
          rather run `portless trust` yourself, or are happy clicking through the
          warning.
        '';
      };

      lanes = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.haus.ai.enable;
          defaultText = lib.literalExpression "config.haus.ai.enable";
          description = ''
            In a `scruff` lane, register the lane's dev server under
            `<lane>.<repo>.localhost` — `wiggly-crane.haus.localhost` — rather
            than the name portless infers on its own.

            It infers a good one already: inside a git worktree it prefixes the
            branch, so a lane lands on `<branch>.<project>.localhost` with no help
            from us. The gap is cosmetic and entirely scruff's fault — scruff's
            branches are `worktree-<lane>` and portless splits a branch on `/`,
            so the prefix comes out as the whole `worktree-wiggly-crane` rather
            than the lane name you actually call it. This registers the shorter
            name alongside; both work.

            Temporary by design: vercel-labs/portless#398 adds `--prefix` and
            `PORTLESS_PREFIX`, which does the same job one level down. When it
            lands, the shim goes and a lane simply exports the variable.

            Follows `haus.ai.enable`, since that is what puts lanes on the
            machine — turning portless on for its own sake never drags a lane
            shim onto a desktop that has no lanes. Setting it true anyway is a
            warning rather than a refusal: the shim already falls back to plain
            `portless run` outside a worktree, so the worst case is a command
            that behaves exactly like the one underneath it.
          '';
        };
      };
    };
  };
}
