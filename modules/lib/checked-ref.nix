# Turning a path spelled INTO a store output from a promise into a build
# dependency — the move three rooms had each grown their own copy of, in one
# place.
#
# ## The shape
#
# Nix interpolates a store path into a string without asserting anything is
# there. So a module that spells `"${someDrv}/a/b/c"` — a nebelung port file, a
# tool's `SKILL.md`, a glamour theme — is making a claim nothing checks:
#
#   · eval is green, because it is string concatenation
#   · `nix flake check` is green, for the same reason
#   · the home-files build is green, because a `home.file` source pointing
#     inside a store output is never existence-checked (home-manager's own
#     `insertFile` ends in a bare `ln -s`)
#   · activation is green, and lands a DANGLING SYMLINK in the user's home
#
# You find it months later, wondering why the app looks stock or why the agent
# never learned the tool. Nothing in the chain above is where the mistake shows
# up, which is what makes this class expensive.
#
# The fix is one line of shell and one insight: NAMING the path inside a
# builder is what makes it real. `[ -e "$path" ]` in a `runCommand` runs after
# the referent's derivation is built and before anything downstream can point
# at it, so a wrong name stops the build instead of the user.
#
# ## Why this is a lib file and not a fourth comment
#
# This repo fixed the same class in `modules/theme/ports.nix` (a nebelung port
# path), in `modules/terminal`'s `glowPlugin` (glow's), and in
# `modules/ai/tool-skills.nix` (a tool's skill folder) — each time by copying
# the previous site's shell by hand, and each time from a different room. The
# third site's own comment states the pattern in general terms and names its
# own precedent, and still did not reach the fourth author, because it is prose
# inside a section about themes. The workshop's `notes/drift.md` row
# twenty-four is exactly this: prose does not travel, and the follow-up it
# names is this file.
#
# ## What is NOT here, deliberately
#
# LISTING what a derivation ships needs `builtins.readDir` on a store output —
# import-from-derivation, which would force a build every time somebody runs
# `haus get` to READ their config. ASSERTING that a named path is there needs
# no eval-time read at all. That asymmetry is the whole reason this works, and
# it is why there is no `checkedRef.contents`.
#
# ## The API
#
# `notes/drift.md` sketched this as `checkedRef drv path`. One function can't
# serve both consumers, and the difference is not cosmetic: two of the three
# sites need the referent COPIED into `$out`, because what points at it is a
# `home.file` source, and a check whose result nothing consumes is a check on
# nobody's build path. So:
#
#   guard   refs               → a shell fragment. Paste at the top of your own
#                                builder when you have other work to do.
#   collect { name; refs; }    → the whole derivation: guard every referent,
#                                then copy each into `$out` at its `install`
#                                path, so a consumer points INTO the result and
#                                the check is on its build path by construction.
#
# A ref — `path`, `problem` and `remedies` are required, the rest have
# defaults:
#
#   path        what must exist.
#   test        the test operator, default `-e`. `-f` where a directory at that
#               path would be just as wrong as nothing.
#   problem     the lines saying WHAT is missing, printed verbatim to stderr.
#   remedies    the lines saying what to do, printed under one standard header.
#               Name one per PERSON who could act: the haus author who bumps a
#               pin, and the consumer of a desktop who holds that input
#               transitively and can't. A remedy list with only the author's
#               lever on it is a dead end for everybody else.
#   install     (collect only) where under `$out` the referent lands, or null
#               to check without copying.
#   source      (collect only) what gets copied, default `path`. They differ
#               whenever the thing worth CHECKING is inside the thing worth
#               COPYING — a skill folder is what installs, `SKILL.md` is what
#               makes the name a real promise, and an empty folder would
#               satisfy `-e`.
#
# ## Everything that reaches the shell here is escapeShellArg'd, paths included
#
# Not tidiness. Every string in a ref comes from ANOTHER repo — a nebelung port
# title, a rendered filename, a tool's derivation name — and this room controls
# none of them. Two distinct hazards, and quoting only answers the first:
#
#   · a SPACE. "Catppuccin Mocha.xccolortheme" is a real rendered filename, and
#     an unquoted `[ -e ]` reads it as two arguments and calls it missing. This
#     is not hypothetical — it failed a build on a file that was there.
#   · a `$` or a backtick. Double quotes do NOT stop those: `[ -e "$f" ]` on a
#     path spelled `theme $HOME.json` tests something else entirely and reports
#     a file that exists as missing. A check that lies in the FALSE direction
#     is worse than no check, because it fails a build nobody broke.
#
# So the paths go through `escapeShellArg` exactly as the messages do. `$out`
# is the one thing quoted rather than escaped, because it is ours and must
# expand.
{ lib, pkgs }:
let
  esc = lib.escapeShellArg;

  # One echo per line, each escaped whole. See the header.
  say = lines: lib.concatMapStrings (l: "  echo ${esc l} >&2\n") lines;

  # The standard failure block, so a reader who has hit one of these before
  # recognises the next one from a different room.
  guardOne =
    ref:
    let
      op = ref.test or "-e";
    in
    ''
      if [ ! ${op} ${esc ref.path} ]; then
      ${say ref.problem}  echo 'Fix it whichever way is yours:' >&2
      ${say (map (r: "  · ${r}") ref.remedies)}  exit 1
      fi
    '';
in
{
  # A shell fragment asserting every referent exists. This is the whole
  # mechanism; `collect` is a common way to consume it, not a bigger version.
  guard = refs: lib.concatMapStrings guardOne refs;

  # guard + copy, for the case where something downstream must point INTO the
  # result. `$out/<install>` is what a `home.file` source names.
  collect =
    { name, refs }:
    pkgs.runCommand name { } (
      ''
        mkdir -p $out
      ''
      + lib.concatMapStrings (
        ref:
        guardOne ref
        # Two referents claiming one destination is caught by the `-e` below
        # rather than by whatever `cp` would do with it: plain `cp -R` onto an
        # existing directory nests the source INSIDE it, producing a wrong tree
        # and no error. Worth its own arm wherever the destination is derived
        # from metadata another repo controls — which is every caller so far.
        + lib.optionalString ((ref.install or null) != null) ''
          if [ -e "$out"/${esc ref.install} ]; then
            echo ${esc "${name}: two referents both install at ${ref.install}."} >&2
            echo ${esc "  The second is ${ref.source or ref.path}."} >&2
            echo 'Fix it whichever way is yours:' >&2
            echo ${esc "  · rename one of them where this list is written"} >&2
            echo ${esc "  · drop one — they cannot both be installed"} >&2
            exit 1
          fi
          mkdir -p "$(dirname "$out"/${esc ref.install})"
          # `-H` follows a symlinked SOURCE and nothing inside it, which is what
          # `cp -R <src>/. <dst>/` used to mean here and what the callers need:
          # `$out/<install>` has to be the checked COPY, not a pointer back into
          # the tool's own output. Plain `-R` would copy the link itself.
          cp -RH ${esc (ref.source or ref.path)} "$out"/${esc ref.install}
          # The store is read-only, so a copied directory arrives at 0555 and a
          # later ref installing BENEATH it would die on a bare `cp: Permission
          # denied` — past every message this file exists to print, and past the
          # collision arm above, which cannot see a path that doesn't exist yet.
          # Nix canonicalises the modes at the end of the build regardless, so
          # this changes nothing about what ships.
          chmod -R u+w "$out"/${esc ref.install}
        ''
      ) refs
    );
}
