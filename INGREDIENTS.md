# Build ingredients

Everything baked into the shipped `.pkg`, and how a change to it reaches a release. An *ingredient*
is an input to the product; the *own upstream* is the thing this repo exists to port.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| GNU Make (own upstream) | `UPSTREAM_VERSION`, with the tarball's SHA-256 in `UPSTREAM_SHA256` | ✅ `git-tags` on GNU's `make.git` moves `UPSTREAM_VERSION`; `UPSTREAM_SHA256` moves by hand | `release.yml` on push to main cuts `-mavericks.1` |
| clang22 (the compiler: the cross pkg off 10.9, the installed release on 10.9) | `components/clang22/version` | ✅ `github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning | repackage → `-mavericks.(N+1)` |
| MacOSX10.9 and 11.3 SDKs, Sparkle framework | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` is a moving tag, so content moves without a path changing |

No Recaulk: the compat guard finds no post-10.9 import in `make` built against the 10.9 SDK, so
nothing needs a back-fill. Add it as an ingredient the day the guard says otherwise.

## How GNU Make is verified

Against the SHA-256 pinned in `UPSTREAM_SHA256`, as `<sha256>  make-<version>.tar.gz`, by
`build/fetch-make.sh` with the OS's own `shasum`, on every build, 10.9 included. GNU signs its tarballs
with GPG and publishes no checksum. The 4.4.1 pin was recorded from a tarball whose SHA-512 and size
matched pkgsrc's `devel/gmake/distinfo`. A Renovate bump fails at the fetch, naming the SHA-256 it got,
until `UPSTREAM_SHA256` follows; a pin naming another version's tarball fails before any download.

## How GNU Make is built

`build/build-make.sh --arch x86_64|arm64` runs make's own `configure` and `build.sh`, so building it
needs no make, with clang22 (`build/toolchain.sh`) in an environment holding only `HOME` (a fresh empty
directory), `TMPDIR`, `PATH` (clang22's `bin`, then `/usr/bin:/bin:/usr/sbin:/sbin`), `SDKROOT` and
`MACOSX_DEPLOYMENT_TARGET` (`build/hermetic-env.sh`). No pkgsrc, Homebrew, MacPorts or Command Line
Tools: `CC` names clang22 with `--no-default-config`, the target, shipyard's pinned SDK and lld.

- **Slices:** x86_64 for 10.9 with the 10.9 SDK, arm64 for 11.0 with the 11.3 SDK. A Mac OS X 10.9
  box builds x86_64 only, since its clang22 has no AArch64 backend.
- **Flags:** `--disable-nls --without-guile`, `-O2`. `-ffile-prefix-map` maps the build root and work
  directory to `.`, and `-Wl,-oso_prefix,.` does the same for debug-map paths, so no installed file
  names the build host.
- **Native and cross agree:** configure runs as a cross build whenever the target arch is not the
  host's. On 10.9, configure's `src/config.h` from a native x86_64 run and from a run forced to cross
  differed in exactly two run tests, `gettimeofday` and a working `strcoll`, which a cross build answers
  "no". Both exist on every macOS this targets, so every build passes
  `ac_cv_func_gettimeofday=yes ac_cv_func_strcoll_works=yes`, and the two modes give the same
  `config.h`.
- **Staged:** under `usr/local/mavergreen/make`: `bin/make`, `bin/gmake` (a relative link to `make`, so
  the tree offers both names to whoever puts its `bin` on `PATH`), `include/gnumake.h`,
  `share/man/man1/make.1` and `gmake.1` (a link), and `share/info/make.info*`, which is what
  `make install` installs without NLS; and `share/doc/make/COPYING`, the GPL the binary is under,
  which the installer also shows.
- **Checked:** the compat guard runs over `bin/make` before the build exits 0. `tests/smoke-test.sh`
  checks the layout, runs the guard over every Mach-O, allows load commands only into `/usr/lib`, and
  fails on any installed file naming the build root, `$HOME`, `Library/Caches`, `/var/folders` or a
  package manager's prefix; then `tests/smoke-runtime.sh`, which needs neither clang22 nor shipyard, runs
  `make` and `gmake`, and builds a Makefile with a pattern rule, `$(shell)` and `-j4` whose four jobs
  must all run at once. x86_64 runs on-target, never under Rosetta.

## How the pkg is made

`build/merge.sh` merges the x86_64 and arm64 stages into one universal tree with shipyard's
`lipo-merge-tree.sh`, clang22's `llvm-lipo` standing in as `lipo`; any other file that differs between
the slices stops the merge. `build/package-pkg.sh` packages one stage, universal in CI or x86_64 alone
from a native 10.9 build, as `make-<version>.pkg`: shipyard's `dev.mavergreen.base`, then
`dev.mavergreen.make`, with the 10.9.5 install floor, the Installer host arches `bin/make` carries,
make's `COPYING` as the license, and `stage_product.sh`'s manifest and install scripts. Everything in
the tree's `bin` and `share/man` is exported, so the family's `PATH` gets `gmake` and `make`, and its
`MANPATH` `gmake.1` and `make.1`; the info manual is not exported, and is read by path.

## What a release carries

`make-<version>.pkg`, the feed `make.xml`, and `make-<upstream>.tar.gz`: the GNU Make source tarball
the release was built from, the bytes `UPSTREAM_SHA256` pins, checked again as they are attached. GNU
Make is GPLv3, and a binary's source offer should not depend on GNU's server keeping an old tarball.
`publish-release.yml` adds `SHA256SUMS` over all three.

## How the updater is built

`CMakeLists.txt` is the Sparkle updater, "Mavericks GNU Make", with the generic app icon by explicit
opt-in. `build/build-updater.sh` builds it with clang22 (`RequireAppleClang` off), like everything else
this repo compiles, once per arch, and merges the two into one universal app. Its public key is the
family's, in `updater/ed25519_key.pub`.

## Declared state

- upstream: UPSTREAM_VERSION
- clang22: components/clang22/version
