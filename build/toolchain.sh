# platform: macOS-only -- fetch_product_pkg.sh expands the clang22-cross pkg with pkgutil
#   usage: . build/toolchain.sh; mk_toolchain x86_64|arm64
#          Exports CC, AR, RANLIB, CLANG22, CLANG22_BIN, SDKROOT and MACOSX_DEPLOYMENT_TARGET (10.9 or
#          11.0) for one arch. clang22 is the release components/clang22/version pins: on Mac OS X 10.9
#          the installed /usr/local/mavergreen/clang22, which must be that release; elsewhere the
#          clang22-cross pkg, extracted under the build root. CC never reads the driver's .cfg: target,
#          SDK (shipyard's fetch_sdk.sh pin) and linker (lld) are all explicit.
#          mk_toolchain_can_build ARCH prints why and returns 1 when this host cannot build ARCH.
#          mk_build_root prints $MAVERICKS_BUILD_ROOT/make (default ${TMPDIR}/mm-build/make).
: "${MAVERICKS_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
. "$MAVERICKS_ROOT/build/msc.sh"

mk_build_root() { _mbr="${TMPDIR:-/tmp}"; printf '%s/make\n' "${MAVERICKS_BUILD_ROOT:-${_mbr%/}/mm-build}"; }

mk_pin() { tr -d '[:space:]' < "$MAVERICKS_ROOT/components/$1/version"; }

mk_host_is_109() { [ "$(uname -s)" = Darwin ] && [ "$(uname -r | cut -d. -f1)" = 13 ]; }

mk_toolchain_can_build() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "clang22 arrives as a pkg, which only macOS can expand"; return 1
  fi
  case "${1:-}" in
    x86_64) return 0 ;;
    arm64)
      if mk_host_is_109; then
        echo "clang22 on Mac OS X 10.9 has no AArch64 backend, so arm64 builds on a modern Mac"; return 1
      fi
      return 0 ;;
    *) echo "unknown arch '${1:-}' (x86_64 or arm64)"; return 1 ;;
  esac
}

mk_installed_version() {
  awk '/<key>version<\/key>/ { getline; sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print; exit }' "$1/mavergreen.plist" 2>/dev/null
}

mk_fetch_pkg() {
  _mf_short=$1; _mf_ver=$2; _mf_dest=$3; _mf_asset=$4
  if [ -d "$_mf_dest" ] && [ "$(cat "$_mf_dest.pin" 2>/dev/null)" = "$_mf_ver" ]; then return 0; fi
  rm -f "$_mf_dest.pin"
  sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" --asset "$_mf_asset" "$_mf_short" "$_mf_ver" "$_mf_dest" >/dev/null || return 1
  printf '%s\n' "$_mf_ver" > "$_mf_dest.pin"
}

mk_toolchain() {
  _mt_why="$(mk_toolchain_can_build "${1:-}")" || { echo "mk_toolchain: $_mt_why" >&2; return 1; }
  case "$1" in
    x86_64) _mt_target=x86_64-apple-macos10.9; MACOSX_DEPLOYMENT_TARGET=10.9 ;;
    arm64) _mt_target=arm64-apple-macos11.0; MACOSX_DEPLOYMENT_TARGET=11.0 ;;
  esac
  _mt_want="$(mk_pin clang22)"
  if mk_host_is_109; then
    CLANG22=/usr/local/mavergreen/clang22
    [ -x "$CLANG22/bin/clang" ] || {
      echo "mk_toolchain: no clang22 at $CLANG22; install clang22 $_mt_want" >&2; return 1; }
    _mt_have="$(mk_installed_version "$CLANG22")"
    [ "$_mt_have" = "$_mt_want" ] || {
      echo "mk_toolchain: the installed clang22 is ${_mt_have:-of unknown version}, but components/clang22/version pins $_mt_want; install clang22 $_mt_want or move the pin" >&2
      return 1; }
  else
    CLANG22="$(mk_build_root)/toolchain/clang22-cross-$_mt_want"
    mk_fetch_pkg clang22-cross "$_mt_want" "$CLANG22" "mavericks-clang-22-cross-$_mt_want.pkg" || {
      echo "mk_toolchain: could not fetch clang22-cross $_mt_want" >&2; return 1; }
  fi
  CLANG22_BIN="$CLANG22/bin"
  if [ "$1" = arm64 ]; then
    SDKROOT="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)" || return 1
  else
    SDKROOT="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")" || return 1
  fi
  case "$SDKROOT" in
    ''|*' '*|*'	'*) echo "mk_toolchain: the SDK path '$SDKROOT' is empty or has a space; CC carries it as one word" >&2; return 1 ;;
  esac
  CC="$CLANG22_BIN/clang --no-default-config --target=$_mt_target -isysroot $SDKROOT -fuse-ld=lld -Wno-unused-command-line-argument"
  AR="$CLANG22_BIN/llvm-ar"
  RANLIB="$CLANG22_BIN/llvm-ranlib"
  export CLANG22 CLANG22_BIN SDKROOT MACOSX_DEPLOYMENT_TARGET CC AR RANLIB
}
