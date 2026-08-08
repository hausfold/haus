# everyday — a Mac for someone who doesn't write code.
#
# The inverse of `minimal`: keep the parts that make the machine pleasant to
# use, drop the parts that only make sense if you write software.
#
# This is the preset the whole developer-pack change existed to make possible.
# Before it, disabling the rooms still installed bun, fnm, opencode, lazygit,
# delta and the agent-worktree tooling — so "a nebelhaus for my parents" could
# not be expressed at all.
#
# The judgement calls, which are the interesting part:
#
#   - prowl OFF. Tiling is good; remapping Caps Lock to a leader key on someone
#     else's Mac is not. They keep the native window behaviour they know.
#   - pounce ON. A search box that opens things is legible to anyone — it's the
#     one power feature that needs no explanation.
#   - sill ON. A clock, battery and weather is a better menu bar, not a
#     different paradigm.
#   - tour ON, and AUTHORED. This is the one that needed a second look. The
#     built-in lap is three leader moves plus the palette, so with prowl off it
#     had nothing left to teach and stayed out of the bar entirely — this
#     preset asked for a tutor for the person who most needs one, and shipped
#     no pill at all, silently. `tour.steps` fixes it from the data side, and
#     this rice is the first customer of the community-tour mechanism: one
#     step, the launcher, which is the only move an everyday machine has.
#     `{palette}` rather than a typed "⌘ Space" so the hint still names the
#     right key on a rice that imports this one and moves it.
{
  haus = {
    sill.enable = true;
    pounce.enable = true;
    tour.enable = true;
    tour.steps = [
      {
        hint = "press {palette}, type tour, hit ↵ — that's how you open anything";
        detect = "palette";
      }
    ];

    prowl.enable = false;

    developer.enable = false;
  };
}
