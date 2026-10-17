# platform: host-agnostic
#   usage: . build/hermetic-env.sh; mk_toolchain ARCH; mk_hermetic CMD [ARG...]
#          Runs CMD with an empty environment except HOME (a fresh empty directory under the build root, so
#          no dotfile reaches a build), TMPDIR, PATH (clang22's bin, then /usr/bin:/bin:/usr/sbin:/sbin),
#          and mk_toolchain's SDKROOT and MACOSX_DEPLOYMENT_TARGET. Returns 1 if mk_toolchain has not run.
#          Needs build/toolchain.sh sourced first.
mk_hermetic() {
  [ -n "${CLANG22_BIN:-}" ] && [ -n "${SDKROOT:-}" ] && [ -n "${MACOSX_DEPLOYMENT_TARGET:-}" ] || {
    echo "mk_hermetic: no toolchain; run mk_toolchain ARCH first" >&2; return 1; }
  mkdir -p "$(mk_build_root)" || return 1
  _mh_home="$(mktemp -d "$(mk_build_root)/home.XXXXXX")" || return 1
  _mh_rc=0
  env -i HOME="$_mh_home" TMPDIR="${TMPDIR:-/tmp}" \
    PATH="$CLANG22_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    SDKROOT="$SDKROOT" MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" "$@" || _mh_rc=$?
  rm -rf "$_mh_home"
  return "$_mh_rc"
}
