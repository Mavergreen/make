#!/bin/sh
# platform: macOS-only -- lipo-merge-tree.sh lipos the slices with clang22's llvm-lipo
#   usage: build/merge.sh --x86_64 STAGE --arm64 STAGE --out STAGE
#          Merges an x86_64 and an arm64 stage from build/build-make.sh into one universal stage at OUT,
#          which must not exist, with shipyard's lipo-merge-tree.sh --require-archs "x86_64 arm64" and
#          clang22's llvm-lipo as lipo (10.9's own lipo is a stub without the Command Line Tools). Any
#          non-Mach-O file that differs between the slices fails the merge, naming it.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$here/.." && pwd)"; export MAVERICKS_ROOT
. "$here/toolchain.sh"

usage() { echo "usage: build/merge.sh --x86_64 STAGE --arm64 STAGE --out STAGE" >&2; exit 2; }
die() { echo "merge: $*" >&2; exit 1; }
x=""; a=""; out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --x86_64) [ "$#" -ge 2 ] || usage; x=$2; shift 2 ;;
    --arm64) [ "$#" -ge 2 ] || usage; a=$2; shift 2 ;;
    --out) [ "$#" -ge 2 ] || usage; out=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$x" ] && [ -n "$a" ] && [ -n "$out" ] || usage
case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac
prefix=/usr/local/mavergreen/make
for s in "$x" "$a"; do [ -d "$s$prefix" ] || die "$s has no $prefix"; done
[ ! -e "$out" ] && [ ! -L "$out" ] || die "$out already exists"

mk_toolchain "$(uname -m)" > /dev/null
mkdir -p "$(mk_build_root)"
work="$(mktemp -d "$(mk_build_root)/merge.XXXXXX")"
made=""
trap 'rm -rf "$work"; [ -z "$made" ] || rm -rf "$out"' EXIT
mkdir "$work/bin"
ln -s "$CLANG22_BIN/llvm-lipo" "$work/bin/lipo"
made=1
mkdir -p "$out${prefix%/*}"
PATH="$work/bin:$PATH" sh "$SHIPYARD_SCRIPTS/lipo-merge-tree.sh" --a "$x$prefix" --b "$a$prefix" --out "$out$prefix" \
  --require-archs "x86_64 arm64" >&2 || die "the slices did not merge"
made=""
echo "merge: universal GNU Make at $out$prefix" >&2
