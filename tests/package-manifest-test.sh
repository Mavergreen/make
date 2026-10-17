#!/bin/sh
# platform: macOS-only -- build/package-pkg.sh runs pkgbuild and productbuild, and pkgutil expands the result
#   usage: [MK_STAGE=DIR [MK_UPDATER_APP=APP]] tests/package-manifest-test.sh
#          Packages a tiny universal stand-in stage with build/package-pkg.sh, expands the pkg and runs its
#          postinstall against a scratch volume: the components, Distribution, payload, manifest, updater
#          and farm links are what the family and this product expect, and the tree's own bin holds make
#          and a gmake link to it. With MK_STAGE (a stage from build/build-make.sh or build/merge.sh) it
#          also packages that, with MK_UPDATER_APP or an updater build/build-updater.sh builds for this
#          host, runs shipyard's artifact conformance over it, and runs the expanded gmake.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$MAVERICKS_ROOT/build/toolchain.sh"
. "$here/fixtures/tiny-stage.sh"
package="$MAVERICKS_ROOT/build/package-pkg.sh"
short=make
prefix=/usr/local/mavergreen/make
up="$(tr -d '[:space:]' < "$MAVERICKS_ROOT/UPSTREAM_VERSION")"
V="$up-mavericks.7"
fail() { echo "FAIL $*"; exit 1; }
id="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier "$short" 2>&1)" \
  || fail "the shipyard at $SHIPYARD_SCRIPTS does not register $short: $id"
upd_id="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-bundle-id "$short")"
feed="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" feed "$short")"
upd_rel="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-app "$short")"
label="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" agent-label "$short")"
mk_toolchain "$(uname -m)" > /dev/null
mkdir -p "$(mk_build_root)"
t="$(mktemp -d "$(mk_build_root)/package-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
PB=/usr/libexec/PlistBuddy
[ "$id" = dev.mavergreen.make ] || fail "shipyard's registry gives make the identifier '$id', not dev.mavergreen.make"

tiny_updater() {
  a="$1/$short-updater.app/Contents"
  mkdir -p "$a/MacOS"
  cp "$t/fat" "$a/MacOS/$short-updater"
  cat > "$a/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$upd_id</string>
<key>CFBundleExecutable</key><string>$short-updater</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$2</string>
<key>SUFeedURL</key><string>$feed</string>
</dict></plist>
EOF
}

expand() {
  rm -rf "$t/x" "$t/root" "$t/scripts"
  pkgutil --expand "$1" "$t/x" || fail "pkgutil could not expand $1"
  mkdir -p "$t/root" "$t/scripts"
  for c in "$t/x"/*.pkg; do
    tar -xf "$c/Payload" -C "$t/root" || fail "could not read $c/Payload"
  done
  for c in "$t/x"/*.pkg; do
    if [ "$(sed -n 's/.*<pkg-info[^>]* identifier="\([^"]*\)".*/\1/p' "$c/PackageInfo")" = "$id" ]; then
      cp -R "$c/Scripts/." "$t/scripts/"
    fi
  done
  [ -x "$t/scripts/postinstall" ] || fail "the $id component has no postinstall"
}

check_pkg() {
  pkg="$1"; host_archs="$2"; dist="$t/x/Distribution"
  comps="$(sed -n 's/.*<pkg-ref id="\([^"]*\)".*/\1/p' "$dist" | awk '!seen[$0]++' | tr '\n' ' ')"
  [ "$comps" = "dev.mavergreen.base $id " ] || fail "components are '$comps', not dev.mavergreen.base then $id"
  grep -q "hostArchitectures=\"$host_archs\"" "$dist" || fail "Distribution does not declare hostArchitectures=\"$host_archs\": $(grep hostArch "$dist")"
  grep -q '<title>GNU Make for Mavericks</title>' "$dist" || fail "Distribution's title is not GNU Make for Mavericks"
  grep -q '<os-version[^>]*min="10\.9\.5"' "$dist" || fail "Distribution declares no 10.9.5 floor: $(grep os-version "$dist")"
  grep -q '<license file="LICENSE.txt"' "$dist" || fail "Distribution shows no license"
  grep -q '<welcome file="Welcome.html"' "$dist" || fail "Distribution shows no welcome"

  ( cd "$t/root" && find . \( -type f -o -type l \) | sed 's|^\./||' ) > "$t/files"
  stray="$(grep -v -e "^usr/local/mavergreen/$short/" -e "^$upd_rel/" -e "^Library/LaunchAgents/$label\.plist$" \
    -e '^usr/local/mavergreen/\.base/' "$t/files" || true)"
  [ -z "$stray" ] || fail "the payload installs outside $prefix and the updater: $stray"
  grep -q "^$upd_rel/Contents/Info.plist$" "$t/files" || fail "the payload has no $upd_rel"
  grep -q "^$upd_rel/Contents/MacOS/$short-updater$" "$t/files" || fail "the payload's updater has no executable"
  [ "$("$PB" -c 'Print :CFBundleIdentifier' "$t/root/$upd_rel/Contents/Info.plist")" = "$upd_id" ] \
    || fail "the updater's bundle id is not $upd_id"
  grep -q "^Library/LaunchAgents/$label\.plist$" "$t/files" || fail "the payload has no $label LaunchAgent"
  m="$t/root$prefix/mavergreen.plist"
  [ "$("$PB" -c 'Print :identifier' "$m")" = "$id" ] || fail "manifest identifier is not $id"
  [ "$("$PB" -c 'Print :product' "$m")" = "$short" ] || fail "manifest product is not $short"
  [ "$("$PB" -c 'Print :group' "$m")" = "$short" ] || fail "manifest group is not $short"
  [ -z "$("$PB" -c 'Print :line' "$m" 2>/dev/null)" ] || fail "manifest declares a line; make is unlined"
  [ "$("$PB" -c 'Print :version' "$m")" = "$V" ] || fail "manifest version is not $V"
  [ "$("$PB" -c 'Print :appcast' "$m")" = "$feed" ] || fail "manifest appcast is not $feed"

  b="$t/root$prefix/bin"
  [ -f "$b/make" ] && [ ! -L "$b/make" ] || fail "the tree's bin/make is not a plain file"
  /usr/bin/file "$b/make" | grep -q 'Mach-O' || fail "the tree's bin/make is not Mach-O: $(/usr/bin/file "$b/make")"
  [ -L "$b/gmake" ] && [ "$(readlink "$b/gmake")" = make ] || fail "the tree's bin/gmake is not a relative link to make"
  cmp -s "$b/gmake" "$b/make" || fail "the tree's bin/gmake does not resolve to its bin/make"
  [ "$(ls "$b" | tr '\n' ' ')" = "gmake make " ] || fail "the tree's bin holds $(ls "$b" | tr '\n' ' '), not gmake and make"

  "$t/scripts/postinstall" "$pkg" / "$t/root" > "$t/post.out" 2>&1 || fail "postinstall failed: $(cat "$t/post.out")"
  got="$(ls "$t/root/usr/local/mavergreen/bin" | tr '\n' ' ')"
  [ "$got" = "gmake make " ] || fail "the farm exports '$got', not gmake and make"
  for c in gmake make; do
    [ "$(readlink "$t/root/usr/local/mavergreen/bin/$c")" = "../make/bin/$c" ] \
      || fail "the farm's $c links to $(readlink "$t/root/usr/local/mavergreen/bin/$c"), not into $prefix/bin"
  done
  man="$(ls "$t/root/usr/local/mavergreen/share/man/man1" | tr '\n' ' ')"
  [ "$man" = "gmake.1 make.1 " ] || fail "the farm's man1 holds '$man', not gmake.1 and make.1"
  [ "$(cat "$t/root/usr/local/mavergreen/var/mavergreen/selections/$short")" = "$short" ] \
    || fail "installing the only member did not select it"
}

tiny_machos "$t" "$up"
mkdir -p "$t/tiny" "$t/upd" "$t/out"
tiny_stage "$t/tiny" "$t/fat"
tiny_updater "$t/upd" "$up-mavericks.6"
if sh "$package" --stage "$t/tiny" --updater-app "$t/upd/$short-updater.app" --version "$V" --out "$t/out" > "$t/o" 2>&1; then
  fail "package-pkg took an updater at another version"
fi
grep -q "$up-mavericks.6" "$t/o" || fail "the version refusal does not name the updater's version: $(cat "$t/o")"
rm -rf "$t/upd"; mkdir "$t/upd"; tiny_updater "$t/upd" "4.3-mavericks.1"
if sh "$package" --stage "$t/tiny" --updater-app "$t/upd/$short-updater.app" --version "4.3-mavericks.1" --out "$t/out" > "$t/o" 2>&1; then
  fail "package-pkg took a version that is not UPSTREAM_VERSION's"
fi
grep -q "not UPSTREAM_VERSION $up" "$t/o" || fail "the version refusal does not name UPSTREAM_VERSION: $(cat "$t/o")"
rm -rf "$t/upd"; mkdir "$t/upd"; tiny_updater "$t/upd" "$V"
cp "$t/x86_64" "$t/upd/$short-updater.app/Contents/MacOS/$short-updater"
if sh "$package" --stage "$t/tiny" --updater-app "$t/upd/$short-updater.app" --version "$V" --out "$t/out" > "$t/o" 2>&1; then
  fail "package-pkg took an x86_64 updater for a universal make"
fi
grep -q 'no arm64 slice' "$t/o" || fail "the arch refusal does not name the missing slice: $(cat "$t/o")"
cp "$t/fat" "$t/upd/$short-updater.app/Contents/MacOS/$short-updater"
mkdir "$t/other"; tiny_machos "$t/other" 4.3
tiny_stage "$t/old" "$t/other/fat"
if sh "$package" --stage "$t/old" --updater-app "$t/upd/$short-updater.app" --version "$V" --out "$t/out" > "$t/o" 2>&1; then
  fail "package-pkg took a make that does not name GNU Make $up"
fi
grep -q "does not name GNU Make $up" "$t/o" || fail "the make-version refusal says: $(cat "$t/o")"
[ -z "$(ls "$t/out")" ] || fail "a refused packaging left $(ls "$t/out") behind"
ls -lRT "$t/tiny" > "$t/before"
sh "$package" --stage "$t/tiny" --updater-app "$t/upd/$short-updater.app" --version "$V" --out "$t/out" > "$t/o" 2>&1 \
  || fail "package-pkg failed on the tiny stage: $(cat "$t/o")"
pkg="$t/out/make-$V.pkg"
[ -f "$pkg" ] || fail "no $pkg: $(ls "$t/out")"
ls -lRT "$t/tiny" | cmp -s - "$t/before" || fail "package-pkg changed the caller's stage"
expand "$pkg"
check_pkg "$pkg" "x86_64,arm64"
echo "PASS tiny stage: base then $id, both arches, the 10.9.5 floor, the GPL and welcome; the payload is $prefix, its updater and agent; the tree's bin holds make (Mach-O) and gmake (a link to it); the manifest, the farm's gmake and make and their manpages"

if [ -z "${MK_STAGE:-}" ]; then
  echo "PASS: package (ran: tiny stage; not run here: a real stage, which needs MK_STAGE)"
  exit 0
fi
[ -d "$MK_STAGE$prefix" ] || fail "MK_STAGE has no $prefix"
app="${MK_UPDATER_APP:-}"
if [ -z "$app" ]; then
  app="$t/real-upd/$short-updater.app"
  sh "$MAVERICKS_ROOT/build/build-updater.sh" --arch "$(uname -m)" --out "$app" > "$t/o" 2>&1 \
    || fail "build-updater failed: $(cat "$t/o")"
fi
RV="$("$PB" -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
mkdir -p "$t/dist"
sh "$package" --stage "$MK_STAGE" --updater-app "$app" --version "$RV" --out "$t/dist" > "$t/o" 2>&1 \
  || fail "package-pkg failed on $MK_STAGE: $(cat "$t/o")"
V="$RV"
pkg="$t/dist/make-$V.pkg"
archs="$(echo $("$CLANG22_BIN/llvm-lipo" -info "$MK_STAGE$prefix/bin/make" | sed -n 's/.*: //p'))"
expand "$pkg"
check_pkg "$pkg" "$(printf '%s' "$archs" | tr ' ' ',')"
ran=""
case " $archs " in
  *" $(uname -m) "*)
    got="$(env -i PATH=/usr/bin:/bin "$t/root/usr/local/mavergreen/bin/gmake" --version | sed -n 1p)" \
      || fail "the expanded gmake did not run"
    [ "$got" = "GNU Make $up" ] || fail "the expanded gmake says '$got'"
    ran=", and the expanded gmake runs" ;;
esac
sh "$SHIPYARD_SCRIPTS/stand-in-feeds.sh" "$t/dist" "$V" > "$t/o" 2>&1 || fail "stand-in-feeds failed: $(cat "$t/o")"
facts="$(sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" "$t/dist" "$V" "$MAVERICKS_ROOT")" || fail "artifact-facts failed"
printf '%s\n' "$facts" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh" > "$t/o" 2>&1 \
  || fail "conformance: $(cat "$t/o")"
echo "PASS real stage ($archs): the same, conformance ($(tail -1 "$t/o"))$ran"
echo "PASS: package (ran: tiny stage, real stage)"
