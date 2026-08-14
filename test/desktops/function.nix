# A module function. The single thing a desktop may never be: it can reach
# pkgs, lib and config, which is the whole trust boundary.
{ lib, ... }:
{
  haus.ui.scale = 1.2;
}
