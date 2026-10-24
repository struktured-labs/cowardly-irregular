#!/usr/bin/env bash
# run_publish_selftests.sh — run every tool selftest the publish chain runs, the way it runs them.
# v3.33.661 passed the fold gate and was then REFUSED at publish gate 0d: tools/reap_probe.sh failed
# its own selftest there. The fold mirrored seven hand-listed checks and that tool was not among
# them. The corpus here is the publish chain's own derivation (tools/derive_selftest_corpus.py), so
# the two cannot drift, and TMPDIR is cleared because the chain sets none — that was the variable
# that made the tool pass for its author and fail for the publisher.
# Exit 0 = every selftest passed · 1 = at least one failed · 2 = the corpus could not be derived
#      3 = refused: the box is busy (or box_busy.sh could not answer), so nothing ran.
#
# WHY IT ASKS tools/box_busy.sh FIRST. Several of these selftests build fixture worktrees in the
# SHARED .git (reap_release_worktrees, reap_probe). Measured 2026-10-24: an ad-hoc run overlapped
# cowir-main's chain running this same corpus and reap's fixtures could not be built — a VOID,
# reported as a FAIL. A run that collides with a fold chain or a publish's gate 0d can VOID THEIRS
# too. The one caller that holds the box is exempt: the fold chain writes BOX_MARKER with its own
# pid and then runs this script, so a run whose ANCESTOR is the marker's pid is the holder asking.
# RPS_IGNORE_BUSY=1 overrides a refusal (it still prints why the box was busy).
#
# A failure keeps its WHOLE output in tmp/run_publish_selftests.$$/<tool>.log. The console shows
# only the tail, and a tail cut the git message out of that VOID line.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
unset TMPDIR
mkdir -p tmp
if [ "${1:-}" = "--selftest" ]; then
  ## Each arm builds a FAKE repo holding a copy of this script, a stub corpus and the REAL
  ## box_busy.sh, then runs that copy — the arms exercise the shipped code, not a re-implementation.
  T="$(mktemp -d "$PWD/tmp/rps_selftest.XXXXXX")"; trap 'rm -rf "$T"' EXIT
  fails=0
  mk() {  # mk DIR CORPUS... : a fake repo whose corpus is the named stub tools
    mkdir -p "$1/tools" "$1/tmp"; cp "$0" "$1/tools/run_publish_selftests.sh"; cp tools/box_busy.sh "$1/tools/"
    local c="$1" t; shift
    printf '#!/usr/bin/env python3\nprint("%s")\n' "$*" > "$c/tools/derive_selftest_corpus.py"
    for t in "$@"; do
      case "$t" in
        bad*) printf '#!/usr/bin/env bash\necho "EARLY: fatal: fixture worktree could not be built"\nfor i in $(seq 1 40); do echo "filler $i"; done\nexit 1\n' > "$c/tools/$t" ;;
        *)    printf '#!/usr/bin/env bash\necho ok\n' > "$c/tools/$t" ;;
      esac
      chmod +x "$c/tools/$t"
    done
  }
  run() {  # run DIR [ENV...] : the copy, with box_busy pointed at this arm's own marker and dirs
    local d="$1"; shift
    env BOX_MARKER="$d/m" DEPLOY_DIR="$d/dep" FOLD_TREE="$d/none" "$@" "$d/tools/run_publish_selftests.sh" 2>&1
  }
  ## 1 free box, a passing corpus -> 0, and the count is printed
  mk "$T/a" good1.sh good2.sh; o="$(run "$T/a")"; e=$?
  [ "$e" = 0 ] && case "$o" in *"2 tool(s) run, 0 failed"*) ;; *) false ;; esac || { echo "FAIL arm1: free box + passing corpus: ec=$e: $o"; fails=1; }
  ## 2 a LIVE marker held by an unrelated pid -> 3, refused, NOTHING ran, the reason is named
  mk "$T/b" good1.sh; sleep 600 & holder=$!; printf 'pid=%s\nwhat=chain999\n' "$holder" > "$T/b/m"
  o="$(run "$T/b")"; e=$?
  { [ "$e" = 3 ] && case "$o" in *"REFUSED"*"chain999"*) ;; *) false ;; esac && case "$o" in *"ok    good1.sh"*) false ;; esac; } \
    || { echo "FAIL arm2: busy box did not refuse with its reason before running anything: ec=$e: $o"; fails=1; }
  ## 3 same marker, RPS_IGNORE_BUSY=1 -> runs, and still says why the box was busy
  o="$(run "$T/b" RPS_IGNORE_BUSY=1)"; e=$?
  { [ "$e" = 0 ] && case "$o" in *"chain999"*"1 tool(s) run, 0 failed"*) ;; *) false ;; esac; } \
    || { echo "FAIL arm3: override did not run past a busy box while naming it: ec=$e: $o"; fails=1; }
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
  ## 4 the HOLDER calling (marker pid = our ancestor, as chain.sh does) -> runs, no refusal
  mk "$T/c" good1.sh
  o="$(bash -c 'printf "pid=%s\nwhat=chain998\n" "$$" > "$1/m"; env BOX_MARKER="$1/m" DEPLOY_DIR="$1/dep" FOLD_TREE="$1/none" "$1/tools/run_publish_selftests.sh" 2>&1' _ "$T/c")"; e=$?
  { [ "$e" = 0 ] && case "$o" in *"REFUSED"*) false ;; *"holds the box"*"1 tool(s) run, 0 failed"*) ;; *) false ;; esac; } \
    || { echo "FAIL arm4: the marker's own holder was refused: ec=$e: $o"; fails=1; }
  ## 5 a publish in flight (log, no ec) -> 3, the other reason box_busy knows
  mk "$T/d" good1.sh; mkdir -p "$T/d/dep/v3.33.0-alpha"; : > "$T/d/dep/v3.33.0-alpha/publish.log"
  o="$(run "$T/d")"; e=$?
  { [ "$e" = 3 ] && case "$o" in *"REFUSED"*"publish in flight"*) ;; *) false ;; esac; } \
    || { echo "FAIL arm5: an in-flight publish did not refuse: ec=$e: $o"; fails=1; }
  ## 6 box_busy.sh missing -> 3, fail closed (cannot tell is not free)
  mk "$T/e" good1.sh; rm "$T/e/tools/box_busy.sh"; o="$(run "$T/e")"; e=$?
  { [ "$e" = 3 ] && case "$o" in *"could not answer"*) ;; *) false ;; esac; } \
    || { echo "FAIL arm6: a missing box_busy.sh did not fail closed: ec=$e: $o"; fails=1; }
  ## 7 a failing tool whose decisive line is ABOVE the console tail -> 1, and the saved log has it
  mk "$T/f" bad1.sh good1.sh; o="$(run "$T/f")"; e=$?
  log="$(printf '%s\n' "$o" | sed -n 's/^ *full output ([0-9]* lines): //p' | head -1)"
  { [ "$e" = 1 ] && case "$o" in *"EARLY: fatal"*) false ;; esac && [ -f "$T/f/$log" ] \
      && command grep -a -q 'EARLY: fatal: fixture worktree could not be built' "$T/f/$log"; } \
    || { echo "FAIL arm7: a failure's early line was not kept in full (ec=$e log='$log'): $o"; fails=1; }
  [ "$fails" = 0 ] && echo "run_publish_selftests selftest: 7/7 arms as expected"
  exit "$fails"
fi
## The box check (see header). The fold chain's marker pid is our ancestor when the chain runs us.
BOX_MARKER="${BOX_MARKER:-$(./tools/box_busy.sh --marker 2>/dev/null)}"
holder=""; [ -f "$BOX_MARKER" ] && holder="$(sed -n 's/^pid=//p' "$BOX_MARKER" | head -1)"
p=$$; anc=0
while [ -n "$holder" ] && [ "$p" -gt 1 ] 2>/dev/null; do
  [ "$p" = "$holder" ] && { anc=1; break; }
  p="$(awk '/^PPid:/ { print $2 }' "/proc/$p/status" 2>/dev/null)"; [ -n "$p" ] || break
done
if [ "$anc" = 1 ]; then
  echo "run_publish_selftests: box check skipped — our ancestor pid $holder holds the box ($(tr '\n' ' ' < "$BOX_MARKER"))"
else
  bb=0; why="$(BOX_MARKER="$BOX_MARKER" ./tools/box_busy.sh 2>&1)" || bb=$?
  case "$bb" in
    0) ;;
    1) if [ "${RPS_IGNORE_BUSY:-}" = 1 ]; then
         echo "run_publish_selftests: WARNING, running anyway (RPS_IGNORE_BUSY=1) on a busy box: $why" >&2
       else
         echo "run_publish_selftests: REFUSED, nothing ran — $why" >&2
         echo "      These selftests build fixtures in the shared .git and can VOID that run or this one." >&2
         echo "      Wait (tools/box_busy.sh --wait 1800) or set RPS_IGNORE_BUSY=1 to run beside it." >&2
         exit 3
       fi ;;
    *) if [ "${RPS_IGNORE_BUSY:-}" = 1 ]; then
         echo "run_publish_selftests: WARNING, box_busy.sh could not answer (exit $bb), running anyway: $why" >&2
       else
         echo "run_publish_selftests: REFUSED, box_busy.sh could not answer (exit $bb), and cannot tell is not free: $why" >&2
         exit 3
       fi ;;
  esac
fi
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
    FD="tmp/run_publish_selftests.$$"; mkdir -p "$FD"; printf '%s\n' "$out" > "$FD/$t.log"
    echo "FAIL  $t (exit $st, $kind)"; printf '%s\n' "$out" | tail -8 | sed 's/^/      /'
    echo "      full output ($(printf '%s\n' "$out" | wc -l | tr -d ' ') lines): $FD/$t.log"; BAD=$((BAD+1))
  else
    echo "ok    $t ($kind)"
  fi
done
echo "run_publish_selftests: $N tool(s) run, $BAD failed"
[ "$BAD" -eq 0 ]
