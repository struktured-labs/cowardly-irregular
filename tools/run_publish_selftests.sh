#!/usr/bin/env bash
# run_publish_selftests.sh — run every tool selftest the publish chain runs, the way it runs them.
# v3.33.661 passed the fold gate and was then REFUSED at publish gate 0d: tools/reap_probe.sh failed
# its own selftest there. The fold mirrored seven hand-listed checks and that tool was not among
# them. The corpus here is the publish chain's own derivation (tools/derive_selftest_corpus.py), so
# the two cannot drift, and TMPDIR is cleared because the chain sets none — that was the variable
# that made the tool pass for its author and fail for the publisher.
# Exit 0 = every selftest passed · 1 = at least one failed · 2 = the corpus could not be derived.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
unset TMPDIR
mkdir -p tmp
CORPUS="$(python3 tools/derive_selftest_corpus.py 2> tmp/run_publish_selftests.err)" || {
  echo "run_publish_selftests: could not derive the corpus: $(cat tmp/run_publish_selftests.err)" >&2
  exit 2; }
if [ -z "$CORPUS" ]; then
  echo "run_publish_selftests: the derived corpus is EMPTY — refusing to call zero selftests a pass" >&2
  exit 2
fi
N=0; BAD=0
for t in $CORPUS; do
  target="tools/$t"; kind="exec"
  case "$t" in
    *.py) if [ -f "tools/${t%.py}_selftest.py" ]; then target="tools/${t%.py}_selftest.py"; kind="py-sibling"; else kind="py-flag"; fi ;;
  esac
  if [ ! -f "$target" ] || { [ "$kind" = "exec" ] && [ ! -x "$target" ]; }; then
    echo "FAIL  $t — $target missing or not runnable"; BAD=$((BAD+1)); continue
  fi
  st=0
  case "$kind" in
    exec)       out=$(./"$target" --selftest 2>&1) || st=$? ;;
    py-flag)    out=$(python3 "$target" --selftest 2>&1) || st=$? ;;
    py-sibling) out=$(python3 "$target" 2>&1) || st=$? ;;
  esac
  N=$((N+1))
  if [ "$st" -ne 0 ]; then
    echo "FAIL  $t (exit $st, $kind)"; printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; BAD=$((BAD+1))
  else
    echo "ok    $t ($kind)"
  fi
done
echo "run_publish_selftests: $N tool(s) run, $BAD failed"
[ "$BAD" -eq 0 ]
