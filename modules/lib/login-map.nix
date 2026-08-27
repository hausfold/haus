# The third answer, and the last of the three facts that make an option a lie if
# you don't know it. Sibling of ./restart-map.nix and ./reachability.nix, and
# deliberately NOT a third table of domains:
#
#   reachability.nix  can the write land at all, and does it mean anything?
#   restart-map.nix   what has to happen after it for anyone to feel it?
#   THIS FILE         what do you tell the person BEFORE they set the option,
#                     when the honest answer to the second question is "nothing
#                     this rebuild can do — log out"?
#
# Three settings groups were once refused for exactly one reason:
# `com.apple.WindowManager` and
# `com.apple.loginwindow` have no live-reload path on macOS 26, and "a group that
# silently needs a logout is worse than no group". Half of that was closed in
# haus#353 — activation announces every logout-only domain the built
# configuration writes, and `haus plan` reports it — so the MACHINE says it. The
# half this file adds is saying it at the OPTION, in its own description, before
# anybody builds anything, which is the shape ./reachability.nix already proved
# for Full Disk Access: one table, which GENERATES the sentence rather than being
# checked against a hand-written copy of it.
#
# ---- why this holds prose and not domains -----------------------------------
# The domain-level fact — "com.apple.WindowManager waits for a logout" — already
# lives in ./restart-map.nix, as the `"logout"` verb, and core already renders it
# into the built activation script. Repeating the verdict here would be the
# fourteenth pass's "a table plus a filter over that table is two sources of
# truth wearing one name", which is the failure both siblings were built to end.
#
# So this file is a RENDERER over restart-map, not a copy of it: it reads the
# `logout` verb from there, and adds the one thing a verb can't carry — what a
# logout costs, per domain, in the words the person setting the option needs.
# `note` is what an option's description interpolates; `domains` is the derived
# list. Both directions are checked at import (below), so a domain that becomes
# logout-only tomorrow fails the build until somebody writes its sentence, and a
# sentence for a domain that is no longer logout-only fails it the same way.
# That is the same fail-closed shape as haus.accessibility's descriptions.
#
# ---- what "logout" means here, precisely ------------------------------------
# Not "restart your Mac", and not "it might not work". The write LANDS — these
# domains are `open` in ./reachability.nix, no TCC grant involved, and the plist
# holds exactly what you asked for. What waits is the READER: macOS reads these
# domains once, when the login session is created, and there is no process to
# restart that would make it read them again. `loginwindow` is the session
# itself, so killing it would end your session to apply a setting; the
# WindowManager keys are read by the WindowServer's session state at login.
#
# Which makes the honest promise a narrow one, and worth saying in full because
# every sentence below is a variation on it: **your next login has this
# setting.** Not this rebuild, not after a `killall`, and nothing is broken in
# between.
{ lib }:

let
  restartMap = import ./restart-map.nix;

  # The derived list — read from restart-map's verb, never restated. A value
  # there is one verb or a list of them (NSGlobalDomain needs two), which is why
  # this asks whether "logout" is AMONG them rather than whether it IS the value:
  # a domain that one day needs both a kill and a logout must still announce the
  # logout half.
  domains = lib.sort (a: b: a < b) (
    lib.filter (d: builtins.elem "logout" (lib.toList restartMap.${d})) (lib.attrNames restartMap)
  );

  # One paragraph per domain, interpolated into every option backed by it.
  #
  # Written per DOMAIN rather than per option on purpose: the cost is a property
  # of the domain, and nine Stage Manager / native-tiling options that each
  # explain the logout in their own words are nine sentences that drift. What an
  # option adds on top is what makes ITS key worth having, which is prose a table
  # can't hold — same split as haus.accessibility's `descriptions`.
  notes = {
    "com.apple.WindowManager" = ''
      TAKES EFFECT AT YOUR NEXT LOGIN. The write lands during the rebuild (no
      permission is involved, and `haus diff` will show the new value straight
      away), but macOS reads this domain when your login session starts and
      offers nothing that makes it re-read: there is no process to restart the
      way Finder or the menu bar can be restarted. So a rebuild that changes
      this option leaves your desktop behaving exactly as it did until you log
      out and back in — which is a wait, not a failure, and nothing is in a
      half-applied state meanwhile.

      `haus plan` says the same thing before the rebuild, and `haus doctor`
      after it, both read out of the built activation script rather than from a
      second copy of this list.
    '';

    "com.apple.loginwindow" = ''
      TAKES EFFECT AT YOUR NEXT LOGIN — and for most of this group that is the
      only moment it could: the login window is what the setting is ABOUT, so
      "when do I see it" and "when does it apply" are the same question. The
      write lands during the rebuild and needs no permission; what has no
      live-reload path is the reader. `loginwindow` is the process that owns
      your session, so the restart that would make it re-read this domain is
      the one that would log you out to do it — which is why haus never fires
      it for you.

      `haus plan` says the same thing before the rebuild, and `haus doctor`
      after it, both read out of the built activation script rather than from a
      second copy of this list.
    '';
  };

  # Fail closed in both directions — the discipline haus.accessibility's
  # generated option surface already runs on. A domain that becomes logout-only
  # with no sentence would ship exactly the silent group §5.6 refuses; a sentence
  # for a domain that is no longer logout-only would tell somebody to log out for
  # a setting that is already live.
  missing = lib.filter (d: !(notes ? ${d})) domains;
  extra = lib.filter (d: !(builtins.elem d domains)) (lib.attrNames notes);
in

if missing != [ ] then
  throw ''
    modules/lib/login-map.nix: ${lib.concatStringsSep ", " missing} is `logout` in
    ./restart-map.nix but has no note here.

    A logout-only domain with no sentence is the silent settings group §5.6 exists
    to refuse: the write lands, the machine does not move, and the option said
    nothing. Write the paragraph here and every option backed by that domain gets
    it — that is the whole mechanism.
  ''
else if extra != [ ] then
  throw ''
    modules/lib/login-map.nix: there is a note for ${lib.concatStringsSep ", " extra},
    which ./restart-map.nix does not mark `logout`.

    Either the domain gained a live-reload path (delete the note — telling someone
    to log out for a setting that is already live is its own kind of lie), or the
    restart map lost an entry it should still have.
  ''
else
  {
    inherit domains;

    # The paragraph for a domain, for an option description to interpolate. A
    # domain with no note can't reach here (the check above), so this is total
    # over `domains` — and deliberately NOT total over every domain on the Mac:
    # asking for a note for `com.apple.finder` is a bug in the caller, and a
    # silently empty string would put it in somebody's option description.
    note =
      domain:
      notes.${domain} or (throw ''
        modules/lib/login-map.nix: no logout note for ${domain}, because
        ./restart-map.nix does not mark it `logout`.

        This is the fact that makes an option honest, so it is not something to
        interpolate speculatively: if that domain really does wait for a login, fix
        the restart map first and the note follows.
      '');
  }
