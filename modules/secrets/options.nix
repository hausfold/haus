# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# secrets' options — which secretspec provider supplies values on this machine,
# and the deck every other room writes to when it needs one of those values.
{ lib, ... }:

let
  contrib = import ../lib/contrib.nix { inherit lib; };
in
{
  options.haus = {
    secrets.provider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "keyring";
      example = "gcsm";
      description = ''
        The secretspec provider that supplies secret VALUES on this machine.
        The secrets room writes it to ~/.config/secretspec/config.toml as the
        default provider, so `secretspec run / check / set` work without
        flags. Any provider string secretspec accepts, URIs included:
        "keyring" (macOS login keychain — local, no accounts), "onepassword",
        "bws" (Bitwarden Secrets Manager), "gcsm" (Google Cloud Secret
        Manager), "awssm" (AWS Secrets Manager), "vault", "pass",
        "protonpass", "lastpass", "dotenv", "env", or a scoped URI like
        "onepassword://account@vault".

        WHICH secrets a PROJECT needs is still that project's own committed
        secretspec.toml. What the ROOMS on this machine need is declared by
        the rooms themselves and rendered to ~/.config/haus/secretspec.toml —
        see `haus-secret --list`. Cloud providers authenticate with their own
        credentials, configured outside Nix (e.g. `gcloud auth
        application-default login` for gcsm); that login is the one manual
        step on a new Mac. null skips writing the config file entirely — run
        `secretspec config init` yourself.
      '';
    };

    secrets.project = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = "haus";
      example = "nix";
      description = ''
        The secretspec PROJECT name the room-declared manifest carries, which
        is the namespace its values are stored under: on the keyring provider
        two projects asking for GITHUB_TOKEN are two separate keychain items.

        The default keeps this machine's rooms in their own namespace, which
        is what you want on a fresh Mac. Point it at a project you already
        have — the name in your config flake's own secretspec.toml, usually —
        and any value already entered there under the same secret NAME is
        found straight away, with nothing to re-enter and nothing duplicated.
      '';
    };

    # ---- the room-declared secret deck ---------------------------------------
    # The permissions deck's argument, one class of thing over: a dozen rooms
    # each know about one value this machine needs and none of them knows about
    # the others, so the receiver renders whatever it finds without knowing who
    # wrote it (modules/lib/contrib.nix, `mkExtensionRegistry`).
    #
    # What a room declares here is a NEED, never a value: names and prose only,
    # exactly what a secretspec.toml may hold, which is why this can live in the
    # store at all. The secrets room turns the deck into a real manifest at
    # ~/.config/haus/secretspec.toml and hands every room the same accessor
    # (`haus-secret <NAME>`), so a room never has to know which provider this
    # Mac uses or where the manifest sits.
    #
    # Why a room declares instead of the host writing the manifest by hand: the
    # host cannot know what the rooms it turned on need, and the answer changes
    # with the generation. A declaration rolls back with its room — turn the
    # github room off and the webhook secret stops being asked for, the same way
    # a permission card leaves with the room that contributed it.
    _contrib.secrets = contrib.mkExtensionRegistry {
      description = ''
        One secret VALUE a room on this machine needs, declared by the room
        that knows why. The secrets room renders the deck into
        ~/.config/haus/secretspec.toml; `haus-secret` reads, lists and fills
        it, and `haus doctor` reports what is still empty.
      '';
      options = {
        name = lib.mkOption {
          type = lib.types.strMatching "[A-Z][A-Z0-9_]*";
          example = "GITHUB_WEBHOOK_SECRET";
          description = ''
            The secret's name in the manifest, and the environment variable
            `secretspec run` would inject — so SCREAMING_SNAKE_CASE, which is
            secretspec's own convention and what the providers key on.

            It is the ADDRESS of a value, so two rooms wanting the same one
            (the same token, the same account) should spell the same name and
            share it; two rooms wanting different values must not. The deck's
            key is per-room ("github-webhook"), the name is per-value — and
            the secrets room refuses a build where one name carries two
            different descriptions, because a manifest cannot hold both.
          '';
        };

        why = lib.mkOption {
          type = lib.types.str;
          description = ''
            One or two sentences: what this machine does with the value.
            Written for somebody who has never heard of the room — "signs the
            webhook deliveries GitHub sends this Mac" beats "the receiver's
            HMAC key". This is the description that lands in the manifest and
            the line `haus-secret --check` prints before asking for a value,
            so it is also the only context the person filling it gets.
          '';
        };

        cost = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            What actually breaks while it is empty, in the user's terms. Empty
            when the answer is simply "the feature is absent". Same job as the
            permission deck's `cost`: it is the half that earns a skip.
          '';
        };

        obtain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "github.com → Settings → Developer settings → Personal access tokens";
          description = ''
            Where the value comes from, in one line — the page to open, the
            command that prints it. Printed beside `why` when the value is
            asked for, because "enter GITHUB_WEBHOOK_SECRET" is not an
            instruction anybody can act on cold.
          '';
        };

        required = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the room is broken without it. `false` for a value that
            only unlocks an extra — secretspec then leaves it out of its own
            pass/fail, `haus doctor` reports it as optional, and nothing on
            this machine nags about it.
          '';
        };
      };
    };
  };
}
