# Imports another file, so what it can do is no longer readable from itself.
{
  imports = [ ./valid-other.nix ];
  haus.ui.scale = 1.2;
}
