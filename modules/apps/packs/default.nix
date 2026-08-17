# The Apps room's saved app collections: the one map from a switch name to the
# file that switch installs.
#
# It exists because two places need to agree about that pairing and used to
# derive it separately — `modules/apps/default.nix`, which imports the file when
# `haus.apps.packs.<name>.enable` is on, and `nix flake check`'s
# `app-collections`, which reads the same file back to prove the room lowered it
# per leaf. A check that guesses the filename from the option name is a check
# that reads a different file than the room installs the day those two stop
# matching, and it would do it silently.
#
# Adding a collection is three edits, and the check fails on any two of them:
# the file, a row here, and a `packs.<name>.enable` option in options.nix.
#
# NOT a nix-darwin module — a plain attrset of paths, imported by both. It is
# deliberately not a flake output: these files are this repo's own since the
# third-party pack format was retired (2026-08-17), so nothing outside needs the
# table.
{
  writing = ./writing.nix;
}
