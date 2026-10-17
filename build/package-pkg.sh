#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild, through shipyard's build_component_pkg.sh and set_install_floor.sh
#   usage: build/package-pkg.sh --stage STAGE --updater-app APP --version V --out DIR
#          Packages the tree at STAGE/usr/local/mavergreen/make (from build/build-make.sh, or universal from
#          build/merge.sh) and APP (build/build-updater.sh) as DIR/make-V.pkg: the dev.mavergreen.base
#          component, then the product's, with the 10.9.5 floor and the Installer host arches bin/make
#          itself carries, each of which the updater must carry too. V is UPSTREAM_VERSION with its
#          -mavericks.N, and the updater's version; bin/make must name UPSTREAM_VERSION. Everything in the
#          tree's bin and man is exported: make and gmake, make.1 and gmake.1. The pkg appears in DIR only
#          once it is made. STAGE is not changed.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$here/toolchain.sh"

usage() { echo "usage: build/package-pkg.sh --stage STAGE --updater-app APP --version V --out DIR" >&2; exit 2; }
die() { echo "package-pkg: $*" >&2; exit 1; }
stage=""; app=""; V=""; out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage) [ "$#" -ge 2 ] || usage; stage=$2; shift 2 ;;
    --updater-app) [ "$#" -ge 2 ] || usage; app=$2; shift 2 ;;
    --version) [ "$#" -ge 2 ] || usage; V=$2; shift 2 ;;
    --out) [ "$#" -ge 2 ] || usage; out=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$stage" ] && [ -n "$app" ] && [ -n "$V" ] && [ -n "$out" ] || usage
short=make
prefix="/usr/local/mavergreen/$short"
tree="$stage$prefix"
up="$(tr -d '[:space:]' < "$MAVERICKS_ROOT/UPSTREAM_VERSION")"
[ -x "$tree/bin/make" ] || die "$stage has no $prefix/bin/make"
[ -f "$tree/share/doc/make/COPYING" ] || die "$stage has no $prefix/share/doc/make/COPYING"
id="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier "$short")" || die "$short is not in shipyard's registry"
case "$V" in
  "$up"-mavericks.[1-9]*) ;;
  *) die "--version $V is not UPSTREAM_VERSION $up with a -mavericks.N" ;;
esac
updv="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)" \
  || die "$app has no Contents/Info.plist with a CFBundleShortVersionString"
[ "$updv" = "$V" ] || die "$app is version $updv, not $V"

mk_toolchain "$(uname -m)" > /dev/null
"$CLANG22_BIN/llvm-strings" "$tree/bin/make" | grep -qx "$up" || die "$tree/bin/make does not name GNU Make $up"
archs_of() { echo $("$CLANG22_BIN/llvm-lipo" -info "$1" | sed -n 's/.*: //p'); }
makearchs="$(archs_of "$tree/bin/make")"
updarchs="$(archs_of "$app/Contents/MacOS/$short-updater")"
host=""
for a in x86_64 arm64; do
  case " $makearchs " in *" $a "*) ;; *) continue ;; esac
  case " $updarchs " in *" $a "*) ;; *) die "make is $makearchs, and the updater has no $a slice ($updarchs)" ;; esac
  host="${host:+$host,}$a"
done
[ -n "$host" ] || die "make is $makearchs: neither x86_64 nor arm64"

mkdir -p "$out" "$(mk_build_root)"
case "$out" in /*) ;; *) out="$(cd "$out" && pwd)" ;; esac
work="$(mktemp -d "$(mk_build_root)/package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
root="$work/root"; dest="$root$prefix"
mkdir -p "${dest%/*}" "$work/scripts" "$work/resources" "$work/component"
COPYFILE_DISABLE=1 cp -Rp "$tree" "$dest"
sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage "$root" --product "$short" --name "GNU Make" \
  --version "$V" --updater-app "$app" --scripts-out "$work/scripts" >&2
find "$root" -name '._*' -exec rm -f {} + 2>/dev/null || true

cp "$MAVERICKS_ROOT/scripts/resources/Welcome.html" "$work/resources/"
cp "$dest/share/doc/make/COPYING" "$work/resources/LICENSE.txt"
comp="$work/component/$short.pkg"
sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root "$root" --identifier "$id" --version "$V" \
  --install-location / --scripts "$work/scripts" --out "$comp" >&2
sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" --identifier "$id" --title "GNU Make for Mavericks" \
  --component "$comp" --out "$work/product.pkg" --resources "$work/resources" --welcome Welcome.html \
  --license LICENSE.txt --host-arch "$host" --min-os 10.9.5 --require-scripts >&2
pkg="$out/make-$V.pkg"
mv "$work/product.pkg" "$pkg"
echo "package-pkg: $pkg ($host)" >&2
