#!/bin/sh
# platform: macOS-only -- build/build-make.sh gets clang22 from a pkg
#   usage: tests/build-make-test.sh
#          Builds every arch this host can, from an environment whose PATH, compiler flags and pkg-config
#          point at /opt/pkg, and checks each stage with tests/smoke-test.sh. Exits 0 when every arch it
#          could build passed, 77 when it could build none.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$MAVERICKS_ROOT/build/toolchain.sh"
mkdir -p "$(mk_build_root)"
t="$(mktemp -d "$(mk_build_root)/build-make-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
arch=decoy
fail() { echo "FAIL $arch: $*"; exit 1; }

mkdir "$t/decoy"
for tool in cc gcc clang make gmake pkg-config; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/decoy-ran"\nexit 1\n' "$tool" "$t" > "$t/decoy/$tool"
  chmod +x "$t/decoy/$tool"
done
PATH="$t/decoy:$PATH" cc --version > /dev/null 2>&1 || true
[ -f "$t/decoy-ran" ] || fail "the decoy cc is not first on PATH"
rm -f "$t/decoy-ran"

ran=""; skipped=""
for arch in x86_64 arm64; do
  if ! why="$(mk_toolchain_can_build "$arch")"; then
    echo "SKIP $arch: $why"; skipped="$skipped $arch"; continue
  fi
  stage="$t/stage-$arch"
  PATH="$t/decoy:$PATH" CC=cc MAKE=make PKG_CONFIG=pkg-config PKG_CONFIG_PATH=/opt/pkg/lib/pkgconfig \
    CPPFLAGS=-I/opt/pkg/include CFLAGS=-I/opt/pkg/include LDFLAGS=-L/opt/pkg/lib CPATH=/opt/pkg/include \
    LIBRARY_PATH=/opt/pkg/lib \
    sh "$MAVERICKS_ROOT/build/build-make.sh" --arch "$arch" --stage "$stage" > "$t/$arch.log" 2>&1 \
    || { tail -30 "$t/$arch.log"; fail "build-make.sh exited non-zero"; }
  [ ! -f "$t/decoy-ran" ] || fail "the build ran a decoy from PATH: $(cat "$t/decoy-ran")"
  leaks="$(grep -r -l -e /opt/pkg "$stage" || true)"
  [ -z "$leaks" ] || fail "the stage names /opt/pkg in: $leaks"
  rc=0; MK_STAGE="$stage" sh "$here/smoke-test.sh" || rc=$?
  case "$rc" in
    0|77) ;;
    *) fail "the smoke test failed" ;;
  esac
  echo "PASS $arch: built from a PATH and flags pointing at /opt/pkg, which nothing ran and nothing in the stage names"
  ran="$ran $arch"
done
[ -n "$ran" ] || { echo "SKIP: this host could build no arch (reasons above)"; exit 77; }
echo "PASS: build-make (built:$ran${skipped:+; not built here:$skipped})"
