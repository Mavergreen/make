#!/bin/sh
# platform: macOS-only -- build/toolchain.sh gets clang22 from a pkg
#   usage: build/build-make.sh --arch x86_64|arm64 --stage DIR
#          Builds the GNU Make release UPSTREAM_VERSION names for one arch with mk_toolchain's clang22, in
#          a hermetic environment, with make's own configure and build.sh (so building it needs no make),
#          and stages it under DIR/usr/local/mavergreen/make, replacing any tree there: bin/make, bin/gmake
#          (a link to make), include/gnumake.h, share/man/man1/make.1 and gmake.1 (a link), and
#          share/info/make.info*. The staged make passes shipyard's compat guard for ARCH before this
#          exits 0. Work happens in a fresh $MAVERICKS_BUILD_ROOT/make/build-ARCH.XXXXXX, removed on
#          success. Build output goes to stderr.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$here/toolchain.sh"
. "$here/hermetic-env.sh"

usage() { echo "usage: build/build-make.sh --arch x86_64|arm64 --stage DIR" >&2; exit 2; }
die() { echo "build-make: $*" >&2; exit 1; }
arch=""; stage=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch) [ "$#" -ge 2 ] || usage
      case "$2" in x86_64|arm64) arch=$2 ;; *) usage ;; esac; shift 2 ;;
    --stage) [ "$#" -ge 2 ] || usage; stage=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$arch" ] && [ -n "$stage" ] || usage
case "$stage" in /*) ;; *) stage="$(pwd)/$stage" ;; esac
prefix=/usr/local/mavergreen/make
v="$(tr -d '[:space:]' < "$MAVERICKS_ROOT/UPSTREAM_VERSION")"

mk_toolchain "$arch" >&2
mkdir -p "$(mk_build_root)"
work="$(mktemp -d "$(mk_build_root)/build-$arch.XXXXXX")"
src="$(sh "$here/fetch-make.sh" --dest "$work")"
gnu() { printf '%s' "$1" | sed 's/^arm64$/aarch64/'; }
case "$arch" in x86_64) darwin=13 ;; arm64) darwin=20 ;; esac
target="$(gnu "$arch")-apple-darwin$darwin"
if [ "$(uname -m)" = "$arch" ]; then build="$target"; else build="$(gnu "$(uname -m)")-apple-darwin$(uname -r | cut -d. -f1)"; fi
prefix_maps=""
for d in "$(mk_build_root)" "$work"; do
  for p in "$d" "$(cd -P "$d" && pwd)"; do prefix_maps="$prefix_maps -ffile-prefix-map=$p=."; done
done
mkdir "$work/obj"
srcrel="../${src#"$work"/}"
# spec: INGREDIENTS.md "How GNU Make is built" -- the two run-test answers a cross build cannot measure
( cd "$work/obj" && mk_hermetic /bin/sh "$srcrel/configure" --build="$build" --host="$target" --prefix="$prefix" \
    --disable-nls --without-guile --disable-dependency-tracking \
    CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-O2$prefix_maps" LDFLAGS=-Wl,-oso_prefix,. MAKE=/usr/bin/false \
    ac_cv_func_gettimeofday=yes ac_cv_func_strcoll_works=yes ) > "$work/configure.log" 2>&1 || {
  tail -30 "$work/configure.log" >&2; die "make's configure failed ($work/configure.log)"; }
( cd "$work/obj" && mk_hermetic /bin/sh "$srcrel/build.sh" ) > "$work/build.log" 2>&1 || {
  tail -30 "$work/build.log" >&2; die "make's build.sh failed ($work/build.log)"; }
[ -x "$work/obj/make" ] || die "build.sh left no make ($work/build.log)"

tree="$stage$prefix"
rm -rf "$tree"
mkdir -p "$tree/bin" "$tree/include" "$tree/share/man/man1" "$tree/share/info"
cp "$work/obj/make" "$tree/bin/make"
chmod 755 "$tree/bin/make"
ln -s make "$tree/bin/gmake"
cp "$src/src/gnumake.h" "$tree/include/gnumake.h"
cp "$src/doc/make.1" "$tree/share/man/man1/make.1"
ln -s make.1 "$tree/share/man/man1/gmake.1"
cp "$src"/doc/make.info "$src"/doc/make.info-[0-9]* "$tree/share/info/"
chmod 644 "$tree/include/gnumake.h" "$tree/share/man/man1/make.1" "$tree"/share/info/*

MAVERICKS_ALLOW_ARCHS="$arch" MAVERICKS_DEVIATIONS_ROOT="$MAVERICKS_ROOT" \
  LIPO="$CLANG22_BIN/llvm-lipo" OTOOL="$CLANG22_BIN/llvm-otool" NM="$CLANG22_BIN/llvm-nm" \
  STRINGS="$CLANG22_BIN/llvm-strings" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$tree/bin/make" >&2 \
  || die "the compat guard refused $tree/bin/make"
rm -rf "$work"
echo "build-make: GNU Make $v for $arch staged at $tree" >&2
