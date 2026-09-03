# The mail watcher — `haus.mail.*`, in the notifications room because a card on
# screen is the whole of what it produces.
#
# ── the shape ────────────────────────────────────────────────────────────────
#
#   IMAP IDLE ──▶ goimapnotify ──▶ mail-announce.py ──▶ haus-notify ──▶ trill
#   (the server     (holds the       (which messages    (or Apple's banner,
#    pushes)         connection)      are actually new)   when nothing answers)
#
# IDLE is a real server push, so a card arrives in the seconds after the mail
# does; nothing here polls. Two processes rather than one, and the seam is
# deliberate: goimapnotify knows only that a mailbox moved, and the announcer
# works out which messages this Mac has never seen. `mail-announce.py`'s header
# has the rest of that argument, including why imaplib's own `idle()` does not
# collapse the two.
#
# ── three absences ───────────────────────────────────────────────────────────
#
#   no filter option    which mail is worth a card is decided twice already,
#                       and neither dial is haus's: the account's own filters
#                       decide what reaches the mailbox, and
#                       `~/.config/trill/rules.json` decides what a `haus.mail`
#                       card then does — quiet hours, drop, rewrite. A third
#                       one here would be the second dial this room's own
#                       `compositor` option promises not to add.
#   no OAuth            the option surface takes a password because the token
#                       shape it would replace is worse: Gmail's read scopes
#                       are restricted, and an app left unverified has its
#                       refresh token expired every seven days — a watcher that
#                       dies weekly, silently, on a schedule nobody remembers.
#   no message body     the card carries who and what-about. A subject is one
#                       line the user chose to have on screen; a preview is
#                       three lines of somebody else's writing, and trill drops
#                       a body whenever the screen is being watched anyway.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.mail;

  home = "/Users/${username}";
  stateDir = "${home}/.local/state/haus/mail";
  configDir = "${home}/.config/haus/mail";
  watchFile = "${configDir}/watch.json";
  logFile = "${home}/Library/Logs/haus-mail.log";

  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  # ---- where the password comes from ----------------------------------------
  # The github room's two shapes, for the same reason: an empty `secretCommand`
  # is this room asking the secrets room to hold the value, and a host that
  # fetches it some other way is not asking haus to hold one — so the
  # declaration below is withdrawn rather than left as a manifest entry the
  # wizard asks for and nothing reads.
  secretName = "MAIL_IMAP_PASSWORD";
  hausHoldsSecret = cfg.secretCommand == "";
  # Absolute, not a bare name: both callers are launchd-spawned, and while this
  # room does set the agent's PATH, `haus-notify`'s own rule in AGENTS.md is
  # that anything launchd starts addresses the store path. A password command
  # that resolves differently than the notifier would be a very quiet bug.
  passwordCommand =
    if hausHoldsSecret then
      "/run/current-system/sw/bin/haus-secret --reason ${lib.escapeShellArg "haus-mail-watch: log in to ${cfg.host} to read the headers of new mail"} ${secretName}"
    else
      cfg.secretCommand;
  # The same thing said to a person, in the deck card: the reason above is for
  # a provider's audit log, not for a reader following instructions.
  secretShowCommand = if hausHoldsSecret then "haus-secret ${secretName}" else cfg.secretCommand;

  # ---- the announcer, as a binary a person can also run ---------------------
  # One body, two doors, the way `github-signal` is: the agent runs exactly what
  # you run at a prompt, so `haus-mail-announce --mailbox INBOX … --test` is a
  # real answer to "is this thing working" rather than an approximation of it.
  announceBin = pkgs.writeShellScriptBin "haus-mail-announce" ''
    exec ${pkgs.python3}/bin/python3 ${./mail-announce.py} "$@"
  '';

  # The flags that do not change per mailbox. `haus-notify` is addressed as a
  # store path for the reason above.
  announceArgs = lib.escapeShellArgs [
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
    "--address"
    cfg.address
    "--password-command"
    passwordCommand
    "--state-dir"
    stateDir
    "--notify"
    "/run/current-system/sw/bin/haus-notify"
  ];

  # One hook per mailbox, each naming its own mailbox literally.
  #
  # ⚠️ Not goimapnotify's `%s` substitution, which would be the obvious way to
  # write one hook for every box: it reaches the command through
  # `fmt.Sprintf`, so the moment a `%s` is present EVERY other percent in the
  # string becomes a format verb and the command runs with `%!x(MISSING)` in
  # it. A literal mailbox keeps Sprintf out of the path entirely.
  hookFor =
    mailbox:
    "${announceBin}/bin/haus-mail-announce --mailbox ${lib.escapeShellArg mailbox} ${announceArgs} >>${lib.escapeShellArg logFile} 2>&1";

  # JSON rather than the YAML the upstream README is written in: viper picks the
  # format off the extension and reads both, and `builtins.toJSON` cannot
  # produce a quoting bug the way a templated YAML string can. A mailbox called
  # `[Gmail]/All Mail` is exactly the value that finds those.
  watchConfig = {
    configurations = [
      {
        host = cfg.host;
        port = cfg.port;
        # Implicit TLS on 993 — `tls` with `starttls` off, which is what the
        # upstream README means by "set tls as true and starttls as false".
        tls = true;
        tlsOptions = {
          rejectUnauthorized = true;
          starttls = false;
        };
        username = cfg.address;
        alias = cfg.address;
        passwordCMD = passwordCommand;
        xoAuth2 = false;
        boxes = map (mailbox: {
          inherit mailbox;
          onNewMail = hookFor mailbox;
        }) cfg.mailboxes;
      }
    ];
  };

  # ---- the agent's wrapper --------------------------------------------------
  # The secret is proved HERE rather than in an activation script, for the
  # reason the github room's receiver does the same: activation runs as root and
  # the answer to `haus-secret` is in the user's login keychain, which root
  # cannot see. It also means a rotated password is one `launchctl kickstart`
  # away instead of a rebuild — goimapnotify asks for it once, at startup.
  #
  # Exit 78 is EX_CONFIG: there is no reduced-function watcher that logs in
  # without a password, and `ThrottleInterval` below keeps that honest refusal
  # from becoming a spin.
  watcher = pkgs.writeShellScript "haus-mail-watch-start" ''
    set -u
    export PATH="${userPath}"
    umask 077
    mkdir -p "${stateDir}"
    chmod 700 "${stateDir}"

    if ! secret=$(${passwordCommand} 2>/dev/null) || [ -z "$secret" ]; then
      echo "haus-mail-watch: no password from \`${secretShowCommand}\` — dormant until there is one" >&2
      exit 78
    fi
    unset secret

    exec ${pkgs.goimapnotify}/bin/goimapnotify -conf ${lib.escapeShellArg watchFile}
  '';
in
lib.mkMerge [
  {
    assertions = [
      {
        assertion = !cfg.enable || cfg.address != "";
        message = "haus.mail.enable is on but haus.mail.address is empty, and there is nothing to log in as. Set it to the mailbox's own address (the IMAP username).";
      }
      {
        assertion = !cfg.enable || cfg.mailboxes != [ ];
        message = "haus.mail.enable is on with haus.mail.mailboxes empty. An empty list would leave goimapnotify watching EVERY mailbox on the account, which on Gmail means every label plus All Mail — the same message three times. Name the ones you want, or turn the room off.";
      }
    ];
  }

  (lib.mkIf cfg.enable {
    environment.systemPackages = [ announceBin ];

    haus._contrib.services.haus-mail-watch = {
      order = 65;
      title = "Mail watcher — IMAP IDLE";
      why = ''
        Holds an IDLE connection to ${cfg.host} so new mail draws a card within
        seconds of arriving, and nothing on this Mac has to poll for it.
      '';
      cost = "new mail never announces itself — no card, and no error either, because a watcher that is not running has nothing to report";
    };

    launchd.user.agents.haus-mail-watch = {
      serviceConfig = {
        ProgramArguments = [ "${watcher}" ];
        RunAtLoad = true;
        KeepAlive = true;
        # A machine with no password yet parks on EX_CONFIG rather than
        # spinning; a server that drops the connection is back inside a minute.
        ThrottleInterval = 60;
        StandardOutPath = logFile;
        StandardErrorPath = logFile;
        EnvironmentVariables.PATH = userPath;
      };
    };

    home-manager.users.${username}.home.file.".config/haus/mail/watch.json".text =
      builtins.toJSON watchConfig;

    haus._contrib.secrets.mail-imap = lib.mkIf hausHoldsSecret {
      name = secretName;
      why = ''
        Reads the mailbox this Mac announces. It is the account's IMAP
        password: on a Google account that means an app password rather than
        the one you type at a login screen, because Google stopped accepting
        that one for IMAP.
      '';
      cost = "the watcher stays dormant, so new mail draws no card";
      obtain = "Gmail: turn on 2-Step Verification, then mint one at https://myaccount.google.com/apppasswords — every other provider calls it an app password too";
    };
  })
]
