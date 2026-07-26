# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# secrets' options — which secretspec provider supplies values on this machine.
{ lib, ... }:

{
  options.nebelhaus = {
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

        WHICH secrets exist is not declared here — that's each project's
        committed secretspec.toml. Cloud providers authenticate with their own
        credentials, configured outside Nix (e.g. `gcloud auth
        application-default login` for gcsm); that login is the one manual
        step on a new Mac. null skips writing the config file entirely — run
        `secretspec config init` yourself.
      '';
    };
  };
}
