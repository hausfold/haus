# Where this machine's secrets come from, and the command that reads one.
{
  haus.secrets.provider = "keyring";
  haus.hush.slack.tokenCommand = "secretspec get slack";
}
