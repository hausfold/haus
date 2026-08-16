# Where this machine's secrets come from, and the command that reads one.
{
  haus.secrets.provider = "keyring";
  haus.focus.slack.tokenCommand = "secretspec get slack";
}
