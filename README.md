# GNU Make for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut
its first release.

GNU Make, built into a Mac OS X 10.9 (Mavericks)-compatible installer package that runs on 10.9 and
on modern macOS, Intel and Apple Silicon alike. A Mac without the Command Line Tools gets a working
`make`.

It installs into `/usr/local/mavergreen/make`, and `gmake` and `make` are on the family's `PATH`
(`/usr/local/mavergreen/bin`, which login shells get from `/etc/paths.d`). Login shells search
`/usr/bin` first, so a bare `make` still finds Apple's `/usr/bin/make`, which without the Command Line
Tools only offers to install them. Call `gmake`, or `/usr/local/mavergreen/bin/make`. A later family
release points Apple's `make` at this one.

The tree's own `bin` holds `make` and `gmake`, so a build that puts
`/usr/local/mavergreen/make/bin` first on its `PATH` finds this make under either name.

This is an unofficial community build. It is not affiliated with, endorsed by or supported by the
GNU Project or the Free Software Foundation.
