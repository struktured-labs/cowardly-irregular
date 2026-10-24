#!/usr/bin/env bash
# make.sh — write the four fold-gate scripts for release NNN into tmp/.
#
# cowir-main's fold pipeline gates every release with tmp/gateNNN.sh, tmp/rungateNNN.sh and
# tmp/wedgewatchNNN.sh. Until 2026-10-13 those existed only as untracked files, each made by
# `sed`-ing the previous release's copy, with the authored test count edited by hand. One lost
# tmp/ or one missed sed and the gate that every tag rests on is gone or wrong. The templates
# beside this file are that pipeline, tracked.
#
#   tools/fold_gate/make.sh 681      writes tmp/{chain,gate,rungate,wedgewatch}681.sh, prints the count
#                                    (run tmp/chain681.sh: pre-gate checks, then the gate only if clean)
#   tools/fold_gate/make.sh --check  proves the templates still carry both placeholders
#
# The authored count is DERIVED (test/unit/test_*.gd on disk), never typed: a gate whose
# Scripts total differs from it ran a truncated suite.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ARG="${1:-}"

check_templates() {
  local bad=0 f
  for f in chain gate rungate wedgewatch; do
    grep -q '@NNN@' "$HERE/$f.sh.tmpl" || { echo "make.sh: $f.sh.tmpl has no @NNN@ placeholder" >&2; bad=1; }
    grep -q '^cd @REPO@$' "$HERE/$f.sh.tmpl" || { echo "make.sh: $f.sh.tmpl does not cd to @REPO@" >&2; bad=1; }
  done
  grep -q 'authored: @AUTHORED@' "$HERE/gate.sh.tmpl" || { echo "make.sh: gate.sh.tmpl has no @AUTHORED@ placeholder" >&2; bad=1; }
  # A gate run without a chain pre-gate must SAY so: .702 was tagged over a broken tools/ corpus
  # because rungate was invoked directly, skipping chain's import/smoke/selftests/sweep.
  grep -q 'PRE-GATE:' "$HERE/rungate.sh.tmpl" || { echo "make.sh: rungate.sh.tmpl no longer reports whether a chain pre-gate covered this tree" >&2; bad=1; }
  grep -q 'run_publish_selftests' "$HERE/chain.sh.tmpl" || { echo "make.sh: chain.sh.tmpl no longer runs the publish selftest corpus" >&2; bad=1; }
  # A typed budget goes stale as the suite grows: 1200 wedged .692 when green runs reached 1119s.
  if grep -q 'RUN_TESTS_TIMEOUT=' "$HERE/gate.sh.tmpl"; then echo "make.sh: gate.sh.tmpl types its own RUN_TESTS_TIMEOUT; leave the budget to run_tests.sh" >&2; bad=1; fi
  return "$bad"
}

if [ "$ARG" = "--check" ]; then
  check_templates && echo "make.sh: templates OK"
  exit $?
fi

case "$ARG" in
  ''|*[!0-9]*) echo "usage: tools/fold_gate/make.sh <release number, e.g. 681> | --check" >&2; exit 2 ;;
esac

check_templates
cd "$REPO"
AUTHORED="$(find test/unit -name 'test_*.gd' | wc -l)"
if [ "$AUTHORED" -lt 1000 ]; then
  echo "make.sh: only $AUTHORED test files under test/unit — wrong directory or a broken checkout" >&2
  exit 1
fi
mkdir -p tmp
for f in chain gate rungate wedgewatch; do
  sed -e "s/@NNN@/$ARG/g" -e "s/@AUTHORED@/$AUTHORED/g" -e "s|@REPO@|$REPO|g" "$HERE/$f.sh.tmpl" > "tmp/$f$ARG.sh"
  chmod +x "tmp/$f$ARG.sh"
  bash -n "tmp/$f$ARG.sh"
done
echo "make.sh: wrote tmp/chain$ARG.sh tmp/gate$ARG.sh tmp/rungate$ARG.sh tmp/wedgewatch$ARG.sh (authored: $AUTHORED)"
