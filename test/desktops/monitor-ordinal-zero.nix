# Monitor number 0. It reads like a position and is not one: AeroSpace numbers
# displays from 1 and answers a 0 by refusing to parse the whole config, so the
# regex that admits an ordinal has to start at 1. The scalar case is
# host-only-monitor.nix; this one is the list, which is checked element by
# element rather than as a whole.
{
  haus.windows.workspaceMonitors."3" = [
    "main"
    "0"
  ];
}
