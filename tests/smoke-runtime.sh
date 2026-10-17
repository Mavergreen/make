#!/bin/sh
# platform: macOS-only -- runs the product's make, which is a macOS build
#   usage: MK_STAGE=DIR tests/smoke-runtime.sh
#          Runs the make tree under DIR (a stage from build/build-make.sh or build/merge.sh, or / for an
#          installed tree) on this host: make and gmake say they are the GNU Make UPSTREAM_VERSION names,
#          and gmake builds a Makefile with a pattern rule, a $(shell) call and -j4, whose four jobs must
#          all be running at once. Needs neither clang22 nor shipyard, so a bare 10.9 guest runs it;
#          tests/smoke-test.sh runs it after its static checks when this host can run the stage's arch.
#          Exits 77 when MK_STAGE is unset.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $*"; exit 1; }

[ -n "${MK_STAGE:-}" ] || { echo "SKIP: set MK_STAGE to a stage from build/build-make.sh, or / for an installed tree"; exit 77; }
bin="${MK_STAGE%/}/usr/local/mavergreen/make/bin"
v="$(tr -d '[:space:]' < "$here/../UPSTREAM_VERSION")"
t="$(mktemp -d "${TMPDIR:-/tmp}/smoke-runtime.XXXXXX")"
trap 'rm -rf "$t"' EXIT

for m in make gmake; do
  [ -x "$bin/$m" ] || fail "no $bin/$m"
  got="$(env -i PATH=/usr/bin:/bin "$bin/$m" --version | sed -n 1p)" || fail "$m --version failed"
  [ "$got" = "GNU Make $v" ] || fail "$m --version says '$got', not 'GNU Make $v'"
done

mkdir "$t/proj"
for n in a b c d; do echo "$n" > "$t/proj/$n.in"; done
cat > "$t/proj/Makefile" <<'EOF'
INS := $(shell ls *.in)
OUTS := $(INS:.in=.out)
SYSTEM := $(shell uname -s)

all: report

%.out: %.in
	@touch $@.started; i=0; \
	while [ $$(ls *.started | wc -l) -lt 4 ]; do \
	  i=$$((i + 1)); [ $$i -le 30 ] || { echo "$@: the other jobs never started" >&2; exit 1; }; sleep 1; \
	done
	tr a-z A-Z < $< > $@

report: $(OUTS)
	cat $^ > $@
	echo $(SYSTEM) >> $@
EOF
env -i PATH=/usr/bin:/bin "$bin/gmake" -C "$t/proj" -j4 > "$t/make.log" 2>&1 || {
  cat "$t/make.log"; fail "gmake -j4 did not build the project (its four pattern-rule jobs must run at once)"; }
[ "$(cat "$t/proj/report")" = "A
B
C
D
Darwin" ] || fail "gmake built a report that says: $(cat "$t/proj/report")"
echo "PASS runtime ($(uname -m) on $(sw_vers -productVersion 2>/dev/null || uname -r)): make and gmake are GNU Make $v; a pattern rule, \$(shell) and four concurrent -j4 jobs"
