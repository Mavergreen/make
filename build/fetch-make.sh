#!/bin/sh
# platform: host-agnostic
#   usage: build/fetch-make.sh [--dest DIR]
#          Prints the path of a freshly extracted DIR/make-<version> (default DIR:
#          $MAVERICKS_BUILD_ROOT/make/src) of the GNU Make release UPSTREAM_VERSION names, verified with
#          shasum against the SHA-256 UPSTREAM_SHA256 pins for make-<version>.tar.gz. The tarball is cached
#          in $MAVERICKS_BUILD_ROOT/make/cache and verified on every use. Exit 1 on any fetch or verification
#          failure, or when UPSTREAM_SHA256 pins another version's tarball; 2 on a usage error.
#          Fixture mode: MK_UPSTREAM_BASE_URL replaces https://ftp.gnu.org/gnu/make (a file:// URL works),
#          and MK_PIN_DIR the directory UPSTREAM_VERSION and UPSTREAM_SHA256 are read from.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/msc.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"

usage() { echo "usage: fetch-make.sh [--dest DIR]" >&2; exit 2; }
die() { echo "fetch-make: $*" >&2; exit 1; }
tmp="${TMPDIR:-/tmp}"
root="${MAVERICKS_BUILD_ROOT:-${tmp%/}/mm-build}/make"
dest="$root/src"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest) [ "$#" -ge 2 ] || usage; dest=$2; shift 2 ;;
    *) usage ;;
  esac
done
pins="${MK_PIN_DIR:-$here/..}"
v="$(tr -d '[:space:]' < "$pins/UPSTREAM_VERSION")"
[ -n "$v" ] || die "$pins/UPSTREAM_VERSION is empty"
tarball="make-$v.tar.gz"
set -- $(cat "$pins/UPSTREAM_SHA256")
[ "$#" -eq 2 ] || die "$pins/UPSTREAM_SHA256 is not one '<sha256>  <tarball>' line"
sha=$1
[ "$2" = "$tarball" ] || die "UPSTREAM_SHA256 pins $2, but UPSTREAM_VERSION is $v; record the SHA-256 of $tarball there"
case "$sha" in *[!0-9a-f]*|'') die "'$sha' is not a SHA-256" ;; esac
[ "${#sha}" -eq 64 ] || die "'$sha' is not a SHA-256"
base="${MK_UPSTREAM_BASE_URL:-https://ftp.gnu.org/gnu/make}"

shipyard_fetch_verified "$base/$tarball" "$sha" "$root/cache" "$tarball" \
  || die "$tarball could not be fetched and verified against $sha"
mkdir -p "$dest"
rm -rf "${dest:?}/make-$v"
tar -xzf "$root/cache/$tarball" -C "$dest"
[ -d "$dest/make-$v" ] || die "$tarball did not extract to $dest/make-$v"
printf '%s\n' "$dest/make-$v"
