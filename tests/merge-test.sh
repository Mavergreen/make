#!/bin/sh
# platform: macOS-only -- build/merge.sh lipos with clang22's llvm-lipo
#   usage: tests/merge-test.sh
#          build/merge.sh on stand-in x86_64 and arm64 stages: the merged make carries both arches, the
#          gmake links survive, and a text file that differs, or an OUT that exists, is refused with
#          nothing left behind.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$MAVERICKS_ROOT/build/toolchain.sh"
. "$here/fixtures/tiny-stage.sh"
mk_toolchain "$(uname -m)" > /dev/null
mkdir -p "$(mk_build_root)"
t="$(mktemp -d "$(mk_build_root)/merge-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $*"; exit 1; }
merge="$MAVERICKS_ROOT/build/merge.sh"
p=usr/local/mavergreen/make

tiny_machos "$t"
tiny_stage "$t/x" "$t/x86_64"
tiny_stage "$t/a" "$t/arm64"
sh "$merge" --x86_64 "$t/x" --arm64 "$t/a" --out "$t/u" > "$t/o" 2>&1 || fail "merge failed: $(cat "$t/o")"
[ "$(echo $("$CLANG22_BIN/llvm-lipo" -info "$t/u/$p/bin/make" | sed -n 's/.*: //p'))" = "x86_64 arm64" ] \
  || fail "the merged make is not x86_64 and arm64: $("$CLANG22_BIN/llvm-lipo" -info "$t/u/$p/bin/make")"
[ "$(readlink "$t/u/$p/bin/gmake")" = make ] || fail "the merged gmake does not link to make"
[ "$(readlink "$t/u/$p/share/man/man1/gmake.1")" = make.1 ] || fail "the merged gmake.1 does not link to make.1"
cmp -s "$t/x/$p/share/info/make.info-1" "$t/u/$p/share/info/make.info-1" || fail "the merged info manual differs from the slices'"

if sh "$merge" --x86_64 "$t/x" --arm64 "$t/a" --out "$t/u" > "$t/o" 2>&1; then fail "merge wrote over an existing OUT"; fi
grep -q 'already exists' "$t/o" || fail "the existing-OUT refusal says: $(cat "$t/o")"
printf 'other\n' > "$t/a/$p/share/info/make.info-1"
if sh "$merge" --x86_64 "$t/x" --arm64 "$t/a" --out "$t/u2" > "$t/o" 2>&1; then fail "merge took slices whose info manuals differ"; fi
grep -q 'share/info/make.info-1 differs' "$t/o" || fail "the refusal does not name the differing file: $(cat "$t/o")"
[ ! -e "$t/u2" ] || fail "a refused merge left $(find "$t/u2" | head -3) behind"
echo "PASS: merge (both arches in make, links kept; refuses a differing text file and an existing OUT, leaving nothing)"
