# The whole house. Import this for the full rice, or import individual rooms
# (den / prowl / sill / collar / pounce / trill / perch / hush / secrets) from
# `darwinModules` in the flake.
{
  imports = [
    ./options.nix
    ./den
    ./theme
    ./hearth
    ./prowl
    ./sill
    ./collar
    ./pounce
    ./trill
    ./perch
    ./hush
    ./secrets
    ./snippets
  ];
}
