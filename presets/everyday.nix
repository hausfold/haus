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
#   - tour ON. It's a first-run tutor; this is exactly the person it's for.
{
  nebelhaus = {
    sill.enable = true;
    pounce.enable = true;
    tour.enable = true;

    prowl.enable = false;

    developer.enable = false;
  };
}
