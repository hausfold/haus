#!/usr/bin/env bash
# `glow`, with the Nebelung glamour style already on the line.
#
# A file rather than a heredoc in default.nix because this script's `"$@"` and
# the builder's substitution holes read as each other's escaping mistakes when
# they share a Nix string, and getting that wrong is a wrapper that silently
# drops its arguments.
#
# Nothing below this line may spell a substitution hole in prose: `substitute`
# rewrites every occurrence in the file, comments included, so a hole named in
# a comment comes out the other side as a store path mid-sentence. (It did.)
#
# `exec`, so this process is REPLACED: glow's pager, its TTY detection and the
# exit code a caller reads are all its own, exactly as if the binary were on
# PATH directly. No trap, no wait, nothing between you and it.
#
# The style flag goes before "$@" on purpose — see `glowThemed` in
# ./default.nix. Last flag wins in pflag, so a caller's own -s overrides this
# one and nothing here takes the choice away.
exec @glow@ -s "@glowStyle@" "$@"
