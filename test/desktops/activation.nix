# Runs code at activation — arbitrary root shell on someone else's machine, and
# the reason "data-only" is a boundary rather than a style.
{
  system.activationScripts.postActivation.text = "echo hello";
  haus.ui.scale = 1.2;
}
