# nebelhaus — the first desktop, and the one `mkNebelhaus` selects when a
# consumer names none.
#
# It is EMPTY on purpose, and only for now. Every value that makes a machine
# feel like nebelhaus — the fog-grey, prowl and sill and hearth turned on the
# way this desktop likes them — is still a module default one layer down, so
# writing them here today would define each of them twice and change what every
# existing install gets. Moving them is step 4 of the workshop's
# notes/rooms-desktops.md, which is deliberately indivisible: the neutral room
# defaults, the values that replace them here, and the compatibility selection
# have to land in one commit or there is a commit on `main` where an install
# silently loses a room.
#
# What this file already does, empty, is make the SEAM real: a full builder
# selects one desktop, its name reaches diagnostics, a second one is refused,
# and a host still wins by plain assignment. Filling it in is then a data
# change against a boundary that already works.
{
  haus = { };
}
