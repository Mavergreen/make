#!/bin/sh
# platform: host-agnostic
#   usage: tests/fetch-make-test.sh
#          build/fetch-make.sh against a file:// fixture: it extracts a tarball matching the pin, refuses one
#          that does not, and refuses a SHA-256 pinned for another version's tarball.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fetch="$here/../build/fetch-make.sh"
t="$(mktemp -d "${TMPDIR:-/tmp}/fetch-make-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $*"; exit 1; }

mkdir -p "$t/up/make-9.9.9" "$t/pins" "$t/build"
echo 'GNU Make fixture' > "$t/up/make-9.9.9/README"
( cd "$t/up" && tar -czf make-9.9.9.tar.gz make-9.9.9 )
sha="$(shasum -a 256 "$t/up/make-9.9.9.tar.gz" | awk '{print $1}')"
echo 9.9.9 > "$t/pins/UPSTREAM_VERSION"
run() { MAVERICKS_BUILD_ROOT="$t/build" MK_UPSTREAM_BASE_URL="file://$t/up" MK_PIN_DIR="$t/pins" sh "$fetch" "$@"; }

printf '%s  make-9.9.9.tar.gz\n' "$sha" > "$t/pins/UPSTREAM_SHA256"
got="$(run --dest "$t/dest")" || fail "fetch-make refused a tarball matching its pin"
[ "$got" = "$t/dest/make-9.9.9" ] || fail "fetch-make printed '$got', not $t/dest/make-9.9.9"
[ "$(cat "$got/README")" = 'GNU Make fixture' ] || fail "the extracted tree is not the fixture's"
echo stale > "$got/README"
run --dest "$t/dest" > /dev/null || fail "a second fetch failed"
[ "$(cat "$got/README")" = 'GNU Make fixture' ] || fail "a second fetch did not extract afresh"

printf '%s  make-9.9.9.tar.gz\n' "$(printf '%s' "$sha" | tr 0-9a-f 1-9a-f0)" > "$t/pins/UPSTREAM_SHA256"
rm -rf "$t/build"
if run --dest "$t/dest2" > "$t/o" 2>&1; then fail "fetch-make took a tarball that does not match its pin"; fi
grep -q "$sha" "$t/o" || fail "the refusal does not name the SHA-256 it got: $(cat "$t/o")"
[ ! -d "$t/dest2/make-9.9.9" ] || fail "a refused tarball was extracted"

printf '%s  make-9.9.8.tar.gz\n' "$sha" > "$t/pins/UPSTREAM_SHA256"
if run --dest "$t/dest3" > "$t/o" 2>&1; then fail "fetch-make took a SHA-256 pinned for make-9.9.8"; fi
grep -q 'UPSTREAM_SHA256 pins make-9.9.8.tar.gz, but UPSTREAM_VERSION is 9.9.9' "$t/o" \
  || fail "the version refusal says: $(cat "$t/o")"
echo "PASS: fetch-make (extracts a verified tarball afresh; refuses a mismatched SHA-256, naming the one it got, and a pin for another version)"
