# Secrets — declared like everything else, valued nowhere in the repo.
#
# The rice ships secretspec (secretspec.dev): a committable secretspec.toml
# declares WHICH secrets a project needs — names and descriptions, never
# values — and a provider supplies the values at runtime. `secretspec run --
# cmd` injects them as env vars into just that process, so nothing lives as
# plaintext files on disk and `secretspec check` on a fresh machine lists
# exactly what still needs entering. That check-and-fill loop is what replaces
# the old hand-carried ~/.secrets directory on the new-Mac checklist.
#
# WHERE values live is personal infrastructure, so it's a host option
# (haus.secrets.provider). The default, "keyring", is the macOS login
# keychain — local, zero accounts, encrypted at rest. Cloud providers (gcsm /
# awssm / bws / onepassword / vault / …) make values follow you across
# machines; their own credential bootstrap (e.g. one gcloud login) becomes the
# single manual step left.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.secrets;
in
{
  # System-wide (like the rest of den's baseline CLI) so haus doctor, sudo, and
  # non-login shells all resolve it.
  environment.systemPackages = [ pkgs.secretspec ];

  # secretspec's own global config — the file `secretspec config init` would
  # write interactively. Declaring it means a fresh machine needs no init step;
  # provider = null leaves the file alone for hand-management.
  home-manager.users.${username} = lib.mkIf (cfg.provider != null) {
    xdg.configFile."secretspec/config.toml".text = ''
      [defaults]
      provider = "${cfg.provider}"
    '';
  };
}
