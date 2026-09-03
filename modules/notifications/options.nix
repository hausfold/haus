# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# The notifications room's options — how this desktop's own banners get drawn,
# plus the one source haus itself feeds them from (`haus.mail.*`, implemented
# in ./mail.nix). Two namespaces, one room: a card about new mail is a
# notification before it is anything else, and `modules/options-groups.nix`'s
# `roomOwners` is what carries that — `haus.bar` and `haus.menuBar` are the
# other pair.
#
# There is deliberately no `notifications.enable` here, and the missing name is
# the point: `haus.notifications.enable = false` would read as "this Mac draws
# no haus notifications", which is false on every machine. `haus-notify` is
# unconditional in ../core and falls back to Apple's banner when no compositor
# answers. The room is the subject; `compositor` is the one question it actually
# decides.
{ lib, ... }:

{
  options.haus = {
    notifications.compositor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The trill notification compositor, installed from its own flake and
        copied to a fixed `/Applications/Trill.app`.

        haus has drawn its banners through trill since `haus-notify` landed, but
        by *finding* it at runtime — PATH, then `/Applications`, then
        `~/Applications` — and falling back to Apple's banner when nothing
        answered. That still works, is still the fallback, and is not gated on
        this switch. The bundle this room places wins that search against a
        hand-installed one, deliberately: a dev build left in `~/Applications`
        used to outrank it forever, because this room rewrites its own path on
        every activation and can never displace a copy sitting in front of it.
        What this adds is the other half: the bundle actually being there, at a
        path that does not move, pinned by this machine's flake lock like every
        other room.

        Why the path is fixed rather than a store path: trill's whole
        `trill doctor` and System Mirror surface is a **Full Disk Access** grant,
        and macOS keys a TCC grant per app *path* and signing identity. A store
        path changes on every version bump, so the grant would drop on the
        rebuild that installed the fix you wanted. `/Applications/Trill.app` is
        where a drag-install or a cask would have put it, so an existing grant
        carries over rather than being asked for again.

        Off by default, and not only out of taste: there is no `trill` cask and
        the `trill` command already resolves without this room, so turning it on
        is a decision to have haus own the bundle.

        It does **not** put `trill` on PATH — `modules/core/trill.sh` already
        does, for every install source including this one, and a second
        `bin/trill` would be a build-time collision rather than a redundancy.

        It does **not** decide what happens to any individual notification
        either. Routing, dropping and rewriting by `source` all live in
        `~/.config/trill/rules.json`, hot-reloaded, and haus deliberately puts
        no second dial in front of it.
      '';
    };

    # ---- the mail watcher ----------------------------------------------------
    # `haus.mail`, not `haus.notifications.mail`: the address a person reaches
    # for is the subject they have in mind, and nobody thinks "notifications"
    # when they want to be told about mail. The room it belongs to is the
    # registry's answer, not the option path's.
    mail.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Watch a mailbox over IMAP and draw one card per new message.

        The server pushes: an IDLE connection is held open, so a card arrives
        in the seconds after the mail does and nothing on this Mac polls. What
        draws it is `haus-notify`, so it is a trill card where trill is
        installed and an Apple banner where it is not, like everything else
        this desktop puts on screen.

        Which mail is worth a card is decided twice before haus sees it, and
        neither dial is this room's. The account's own filters decide what
        reaches the mailbox at all — a Gmail filter that skips the inbox never
        produces a card — and `~/.config/trill/rules.json` decides what a
        `haus.mail` card then does: quiet hours, dropped, rewritten, or
        silenced entirely. That is why there is no filter option here.

        It needs the mailbox's password before it will start (see
        `secretCommand`). Until there is one the agent parks with EX_CONFIG and
        says so in `~/Library/Logs/haus-mail.log`; the build is fine, the
        watcher simply is not up.
      '';
    };

    mail.address = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "you@gmail.com";
      description = ''
        The mailbox's own address, which is also the IMAP username.

        It is the account name for the login and the account name in the link
        the card's Open pill carries — Gmail's `u/<address>` form rather than
        `u/0`, which means "whichever Google account signed in first" and is
        the wrong mailbox on any Mac signed into two of them.
      '';
    };

    mail.host = lib.mkOption {
      type = lib.types.str;
      default = "imap.gmail.com";
      example = "imap.fastmail.com";
      description = ''
        The IMAP server.

        Gmail's by default because that is the account this was built for, but
        nothing in the room is Gmail-specific except one flourish: where the
        server says it speaks Gmail's dialect, the card gets an Open pill that
        goes to the message's own thread. Elsewhere the card carries no pill,
        which is the honest answer — a link that opens the wrong thing is
        worse than no link.
      '';
    };

    mail.port = lib.mkOption {
      type = lib.types.port;
      default = 993;
      example = 143;
      description = ''
        The IMAP port. 993 is implicit TLS, which is what this room configures
        and what every hosted provider answers on.

        An option because a self-hosted server can differ, not because anyone
        should need to change it.
      '';
    };

    mail.mailboxes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "INBOX" ];
      example = [
        "INBOX"
        "[Gmail]/Starred"
      ];
      description = ''
        Which mailboxes to watch, spelled exactly as the server spells them.

        ⚠️ Do not empty this list to mean "all of them". The watcher's own
        default for an empty list is every mailbox on the account, which on
        Gmail is every label plus All Mail — so one arriving message announces
        itself twice, three times, once per label it matched. haus refuses to
        build with the list empty for that reason.

        `INBOX` is the one name IMAP standardises. Everything else is the
        provider's own spelling, and Gmail's are bracketed
        (`[Gmail]/All Mail`); `haus-mail-announce` has no way to guess them, so
        take them from your client or from
        `goimapnotify -conf ~/.config/haus/mail/watch.json -list`.
      '';
    };

    mail.secretCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "op read op://private/gmail/app-password";
      description = ''
        Shell printing the mailbox's IMAP password on stdout.

        A command rather than a value so the password never enters the Nix
        store, where it would be world-readable and kept in every generation.
        It is run at startup by the watcher and again by the announcer for each
        message it fetches, and nothing caches the answer to disk.

        EMPTY (the default) means haus holds it: this room declares
        MAIL_IMAP_PASSWORD to the secrets room, `haus-secret --check` asks you
        for it once, and `haus.secrets.provider` decides where it is kept. Set
        this only to fetch the value some other way — which withdraws the
        declaration, since a manifest entry nothing reads is a value the wizard
        would ask for and never use.

        On a Google account the value is an **app password**
        (`https://myaccount.google.com/apppasswords`, which needs 2-Step
        Verification on first): Google no longer accepts an account password
        for IMAP. It is a static credential with full access to the mailbox, so
        it belongs in the keychain and nowhere else — and revoking it in that
        same page is what stops this Mac reading the mail, without touching any
        other machine.

        ⚠️ A command containing `%s` is reinterpreted by the watcher as a
        format string (it substitutes the mailbox name into hooks that way), so
        keep percent signs out of it.
      '';
    };
  };
}
