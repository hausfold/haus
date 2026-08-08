# full — the whole rice, and the rice's own default.
#
# Every choosable room on, developer pack on. Importing this changes nothing
# from a bare install; it exists so "full" is a NAMED thing you can point at,
# diff against, and compose with, rather than an absence of configuration.
{
  haus = {
    sill.enable = true; # the menu bar
    prowl.enable = true; # tiling + the Caps-Lock leader
    pounce.enable = true; # the ⌘Space palette
    tour.enable = true; # the first-run tutor

    developer.enable = true;
  };
}
