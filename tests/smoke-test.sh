#!/bin/sh
# platform: macOS-only -- reads the stage's Mach-O with clang22's llvm tools, and runs it
#   usage: MK_STAGE=DIR tests/smoke-test.sh
#          Checks the make tree build/build-make.sh (or build/merge.sh) staged under DIR: its layout, the
#          compat guard over every Mach-O for the arches bin/make carries, load commands only into
#          /usr/lib, and no installed file naming the build host. Then runs tests/smoke-runtime.sh when
#          this host can run one of those arches natively. Exits 77 when MK_STAGE is unset, and when this
#          host cannot execute the stage's arch (after its static checks pass).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$MAVERICKS_ROOT/build/toolchain.sh"
fail() { echo "FAIL: $*"; exit 1; }

[ -n "${MK_STAGE:-}" ] || { echo "SKIP: set MK_STAGE to a stage from build/build-make.sh"; exit 77; }
prefix="$MK_STAGE/usr/local/mavergreen/make"
make="$prefix/bin/make"
[ -x "$make" ] || fail "no $make"
t="$(mktemp -d "${TMPDIR:-/tmp}/smoke-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
mk_toolchain "$(uname -m)" >/dev/null
B="$CLANG22_BIN"

[ "$(readlink "$prefix/bin/gmake")" = make ] || fail "bin/gmake does not link to make"
[ "$(readlink "$prefix/share/man/man1/gmake.1")" = make.1 ] || fail "share/man/man1/gmake.1 does not link to make.1"
for f in include/gnumake.h share/man/man1/make.1 share/info/make.info; do
  [ -f "$prefix/$f" ] || fail "the stage has no $f"
done
others="$(cd "$prefix" && find . -type f | grep -v -x -e ./bin/make -e ./include/gnumake.h -e ./share/man/man1/make.1 \
  -e './share/info/make\.info\(-[0-9]*\)\{0,1\}' -e ./mavergreen.plist || true)"
[ -z "$others" ] || fail "the stage carries files nothing installs: $others"

archs="$("$B/llvm-lipo" -info "$make" | sed -n 's/.*: //p' | xargs)" || fail "llvm-lipo cannot read $make"
[ -n "$archs" ] || fail "llvm-lipo found no arch in $make"
find "$prefix" -type f -exec /usr/bin/file {} + | sed -n 's/: *Mach-O.*//p' | sort -u > "$t/macho"
grep -qx "$make" "$t/macho" || fail "the Mach-O scan missed $make"
if grep -q ' ' "$t/macho"; then fail "a Mach-O path has a space: $(grep ' ' "$t/macho")"; fi
MAVERICKS_ALLOW_ARCHS="$archs" MAVERICKS_DEVIATIONS_ROOT="$MAVERICKS_ROOT" \
  LIPO="$B/llvm-lipo" OTOOL="$B/llvm-otool" NM="$B/llvm-nm" STRINGS="$B/llvm-strings" \
  sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" $(cat "$t/macho") > "$t/guard.log" 2>&1 || {
    tail -40 "$t/guard.log"; fail "the compat guard refused the stage"; }

: > "$t/deps"
while read -r f; do
  for a in $archs; do
    "$B/llvm-otool" -arch "$a" -L "$f" | sed 1d | awk -v f="$f" -v a="$a" '{ print f " (" a "): " $1 }' >> "$t/deps"
  done
done < "$t/macho"
grep -q ': /usr/lib/libSystem.B.dylib$' "$t/deps" || fail "the load-command scan found no libSystem: $(cat "$t/deps")"
bad="$(grep -v ': /usr/lib/' "$t/deps" || true)"
[ -z "$bad" ] || fail "a Mach-O loads something outside /usr/lib: $bad"

br="$(mk_build_root)"; mkdir -p "$br"; brp="$(cd -P "$br" && pwd)"
case "${HOME:-/}" in /) fail "HOME is unset or /, so the scan cannot look for it" ;; esac
find "$prefix" -type f -exec grep -l -F -e "$br" -e "$brp" -e "$HOME" -e Library/Caches -e /var/folders \
  -e /opt/pkg -e /opt/local -e /opt/homebrew {} + > "$t/hostpaths" 2> "$t/grep.err" || true
[ ! -s "$t/grep.err" ] || fail "could not scan the stage's files: $(cat "$t/grep.err")"
[ ! -s "$t/hostpaths" ] || fail "installed files name the build root, \$HOME, Library/Caches, /var/folders or a package manager's prefix: $(tr '\n' ' ' < "$t/hostpaths")"
grep -q -F /usr/local/mavergreen/make "$make" || fail "the scan cannot find even the prefix in bin/make"
echo "PASS static: $(wc -l < "$t/macho" | tr -d ' ') Mach-O ($archs): the layout, the compat guard, only /usr/lib, no build-host path"

host="$(uname -m)"
case " $archs " in
  *" $host "*) ;;
  *) echo "SKIP runtime: this $host host cannot run $archs natively, and this test never runs it under Rosetta (x86_64 runs on-target, on Mac OS X 10.9)"; exit 77 ;;
esac
MK_STAGE="$MK_STAGE" sh "$here/smoke-runtime.sh"
