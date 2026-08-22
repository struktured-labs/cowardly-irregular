#!/usr/bin/env bash
# mutation_check.sh — run ONE mutation and return a verdict that cannot be misread.
#
# WHY THIS EXISTS (@cowir-controller, 2026-08-22): a mutation that produces ZERO
# test failures has (at least) three causes, and they print identically:
#
#   A  the mutation never applied      (typo'd literal, wrong file, already-changed source)
#   B  the suite never ran             (script parse error, typo'd -gtest name -> "Tests 0")
#   C  the test is VACUOUS             (it derives its own expectation from the symbol
#                                       under mutation, so both sides move together and
#                                       assert_eq(0,0) passes -- @cowir-controller's M1)
#
# Only C is a finding. A and B are instrument failures. Read as "the mutation didn't
# land, revert it, the code was fine", C is silently converted into its own opposite --
# which is exactly the wrong conclusion and the most expensive one.
#
# The disambiguation is cheap and it is NOT an inference: ASSERT THE MUTATION LANDED.
# Hash the file before and after and require the bytes to differ. Then zero failures can
# only mean C. This is the fleet's "pair every count with a sample-existence assertion"
# rule (see memory: defect-suppresses-its-own-evidence) applied to mutation testing --
# a count of failures is only informative if the mutated population is known non-empty.
#
# The FOURTH state matters just as much and is the one hand-run mutations skip:
# a baseline that is ALREADY RED makes every mutation look live. So baseline runs first.
#
# Usage:
#   tools/mutation_check.sh <file> <old-literal> <new-literal> [test-target...]
#   tools/mutation_check.sh --self-test        # fixtures, no godot needed
#
# Exit codes:
#   0  TEST IS LIVE     mutation landed, suite went red   -> the test guards this symbol
#   4  VACUOUS          mutation landed, suite stayed green -> THE FINDING
#   3  INSTRUMENT       could not measure; verdict withheld (never blamed on the test)
#   2  bad invocation
#
# The runner is injectable for self-test: MC_RUNNER=<cmd>. Defaults to tools/run_tests.sh.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p tmp

RUNNER="${MC_RUNNER:-tools/run_tests.sh}"

_die_usage() { echo "usage: tools/mutation_check.sh <file> <old> <new> [test-target...]" >&2; exit 2; }

# ---------------------------------------------------------------- self-test
if [ "${1:-}" = "--self-test" ]; then
  W="$(mktemp -d "${TMPDIR:-$PWD/tmp}/mcselftest.XXXXXX")"
  trap 'rm -rf "$W"' EXIT
  mkdir -p "$W/tools"
  cp tools/mutation_check.sh "$W/tools/"
  printf 'const DELAY = 0.40\n' > "$W/subject.gd"
  fail=0
  _arm() { # name expected_ec runner_behaviour old new
    local name="$1" want="$2" beh="$3" old="$4" new="$5"
    # The fake runner READS THE SUBJECT, like a real test does. That is the whole point:
    # "live" must be green before the mutation and red after, which is the only fixture
    # shape that can exercise the verdict arms at all.
    cat > "$W/fake_runner.sh" <<FAKE
#!/usr/bin/env bash
echo "---- Totals"
case "$beh" in
  live)     echo "  Tests   12"; grep -q '0\.0$' subject.gd && exit 1 || exit 0 ;;
  vacuous)  echo "  Tests   12"; exit 0 ;;
  basered)  echo "  Tests   12"; exit 1 ;;
  zero)     echo "  Tests   0";  exit 0 ;;
  crash)    exit 127 ;;
esac
FAKE
    chmod +x "$W/fake_runner.sh"
    ( cd "$W" && MC_RUNNER="$W/fake_runner.sh" bash tools/mutation_check.sh subject.gd "$old" "$new" >"$W/out.txt" 2>&1 )
    local got=$?
    if [ "$got" = "$want" ]; then
      printf '  ✅ %-36s ec=%s\n' "$name" "$got"
    else
      printf '  🔴 %-36s ec=%s (expected %s)\n' "$name" "$got" "$want"; sed 's/^/       /' "$W/out.txt"; fail=1
    fi
    printf 'const DELAY = 0.40\n' > "$W/subject.gd"   # restore fixture
  }
  echo "mutation_check.sh --self-test"
  echo "  -- verdict arms (the harness must be able to reach BOTH) --"
  _arm "TEST IS LIVE  (green->red)"       0 live    "0.40" "0.0"
  _arm "VACUOUS       (green->green)"     4 vacuous "0.40" "0.0"
  echo "  -- instrument arms (verdict withheld, never blamed on the test) --"
  _arm "baseline ALREADY RED"             3 basered "0.40" "0.0"
  _arm "literal ABSENT (typo'd constant)" 3 live    "0.44" "0.0"
  _arm "mutation is a NO-OP (old==new)"   3 live    "0.40" "0.40"
  _arm "suite ran nothing (Tests 0)"      3 zero    "0.40" "0.0"
  _arm "runner crashed (ec=127)"          3 crash   "0.40" "0.0"
  echo
  # A self-test in which every arm returned 3 would print all-green and mean nothing --
  # the same vacuity the tool itself exists to catch. Both verdicts above are reachable
  # from ONE fixture, which is what makes the instrument arms informative.
  if [ "$fail" = 0 ]; then echo "SELF-TEST: PASS — 2 verdict arms reachable + 5 instrument arms, all distinct"; else echo "SELF-TEST: FAIL"; fi
  exit "$fail"
fi

# ---------------------------------------------------------------- args
[ "$#" -ge 3 ] || _die_usage
FILE="$1"; OLD="$2"; NEW="$3"; shift 3
TARGET=("$@")

[ -f "$FILE" ] || { echo "INSTRUMENT: no such file: $FILE" >&2; exit 3; }
[ "$OLD" = "$NEW" ] && { echo "INSTRUMENT: mutation is a no-op (old == new: '$OLD')" >&2; exit 3; }

_hash() { cksum < "$1" | tr -d ' \n'; }

# ---------------------------------------------------------------- 0. is the literal even there
_occ="$(command grep -aFc -- "$OLD" "$FILE" 2>/dev/null || true)"
_occ="${_occ:-0}"
if [ "$_occ" -eq 0 ]; then
  echo "INSTRUMENT: literal not present in $FILE: '$OLD'" >&2
  echo "  (this is cause A — it would otherwise print as 'mutation produced no failures')" >&2
  exit 3
fi
echo "mutation_check: '$OLD' -> '$NEW' in $FILE ($_occ occurrence(s))"

# ---------------------------------------------------------------- 1. baseline MUST be green
echo "--- baseline (unmutated) ---"
"$RUNNER" "${TARGET[@]+"${TARGET[@]}"}" > tmp/mc_baseline.$$.log 2>&1
_base_ec=$?
_base_tests="$(command grep -aE '^[[:space:]]*Tests[[:space:]]+[0-9]+' tmp/mc_baseline.$$.log | tail -1 | tr -dc '0-9')"
if [ "$_base_ec" -ne 0 ]; then
  echo "INSTRUMENT: baseline is ALREADY RED (exit $_base_ec) — every mutation would look live." >&2
  echo "  log: tmp/mc_baseline.$$.log" >&2
  exit 3
fi
if [ -z "$_base_tests" ] || [ "$_base_tests" -eq 0 ]; then
  echo "INSTRUMENT: baseline ran ${_base_tests:-no} tests — nothing to mutate against." >&2
  echo "  (this is cause B — a typo'd test target or a script parse error)" >&2
  exit 3
fi
echo "baseline: green, Tests $_base_tests ✅"

# ---------------------------------------------------------------- 2. apply + PROVE it landed
_before="$(_hash "$FILE")"
cp -a "$FILE" "tmp/mc_orig.$$"
trap 'cp -a "tmp/mc_orig.$$" "$FILE" 2>/dev/null; rm -f "tmp/mc_orig.$$"' EXIT INT TERM

# Literal-safe replace via awk index() — no regex metacharacter hazard in OLD or NEW,
# and no python3 dependency (it is absent from the CI image; see build.yml's PE check).
awk -v old="$OLD" -v new="$NEW" '
{
  line = $0; out = ""
  while ((i = index(line, old)) > 0) {
    out  = out substr(line, 1, i-1) new
    line = substr(line, i + length(old))
  }
  print out line
}' "tmp/mc_orig.$$" > "$FILE" || { echo "INSTRUMENT: could not edit $FILE" >&2; exit 3; }

_after="$(_hash "$FILE")"
if [ "$_before" = "$_after" ]; then
  echo "INSTRUMENT: file bytes UNCHANGED after applying the mutation." >&2
  echo "  (cause A, the silent one — the edit reported success and changed nothing)" >&2
  exit 3
fi
echo "mutation applied: file hash $_before -> $_after ✅  (cause A excluded BY MEASUREMENT)"

# ---------------------------------------------------------------- 3. run mutated
echo "--- mutated ---"
"$RUNNER" "${TARGET[@]+"${TARGET[@]}"}" > tmp/mc_mutated.$$.log 2>&1
_mut_ec=$?
_mut_tests="$(command grep -aE '^[[:space:]]*Tests[[:space:]]+[0-9]+' tmp/mc_mutated.$$.log | tail -1 | tr -dc '0-9')"

if [ -z "$_mut_tests" ] || [ "$_mut_tests" -eq 0 ]; then
  echo "INSTRUMENT: mutated run reported ${_mut_tests:-no} tests." >&2
  echo "  The mutation likely broke PARSING, so the suite never executed. Not a verdict." >&2
  echo "  log: tmp/mc_mutated.$$.log" >&2
  exit 3
fi
if [ "$_mut_ec" -ne 0 ] && [ "$_mut_ec" -ne 1 ]; then
  echo "INSTRUMENT: mutated run exited $_mut_ec (not 0=pass / 1=fail). Not a verdict." >&2
  exit 3
fi
if [ "$_mut_tests" -ne "$_base_tests" ]; then
  echo "⚠️  test COUNT moved: baseline $_base_tests -> mutated $_mut_tests." >&2
  echo "   The mutation changed WHICH tests ran, so the comparison is not like-for-like." >&2
fi

# ---------------------------------------------------------------- 4. verdict
echo
if [ "$_mut_ec" -eq 1 ]; then
  echo "✅ TEST IS LIVE — mutation landed (hash changed) and the suite went RED."
  echo "   Tests $_mut_tests. The test genuinely guards '$OLD' in $FILE."
  exit 0
fi
echo "🔴 VACUOUS — mutation landed (hash changed), suite ran $_mut_tests tests, and stayed GREEN."
echo "   This is NOT 'the mutation didn't apply' — that was excluded by measurement above."
echo "   Most likely: the test derives its expectation from the symbol it mutates, so both"
echo "   sides moved together (@cowir-controller's M1). Re-target the assert on an ABSOLUTE"
echo "   literal, never on the constant under test."
exit 4
