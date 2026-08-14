# A hand-rolled `mkForce`. A data file has no `lib`, but the attrset one
# produces is writable by hand — and a desktop that could raise its own
# priority would stop losing to the host that chose it.
{
  haus.ui.scale = {
    _type = "override";
    priority = 1;
    content = 2.0;
  };
}
