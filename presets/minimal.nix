# minimal — just the themed shell.
#
# No bar, no tiling, no palette: nothing that changes how the Mac behaves
# system-wide. What you get is the terminal experience — the prompt, the
# toolbelt, the colours — on an otherwise stock macOS.
#
# Still a DEVELOPER machine. "Minimal" here means few rooms, not few tools; if
# you want a Mac with no developer tooling, that's `everyday`. (Before
# nebelhaus.developer existed this distinction was impossible to make, and
# "minimal" quietly installed the whole toolbelt anyway.)
{
  nebelhaus = {
    sill.enable = false;
    prowl.enable = false;
    pounce.enable = false;
    tour.enable = false; # the tour teaches moves this preset doesn't ship

    developer.enable = true;
  };
}
