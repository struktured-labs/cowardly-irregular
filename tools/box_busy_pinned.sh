#!/usr/bin/env bash
# box_busy_pinned.sh — run box_busy.sh AS origin/main HAS IT, never as your checkout has it.
#
# WHY THIS EXISTS. On 2026-10-29 three lanes discovered, independently and within an hour,
# that their box gate delegated to a copy of tools/box_busy.sh from their own tree:
#   @cowir-autogrind  a 12-day-old copy whose DEPLOY_DIR still defaulted to ONE lane's tree.
#                     Their correct "BUSY" that evening was LUCK — .745's marker happened to
#                     sit in the single directory that copy reads. Had it been published from
#                     another lane's worktree (as .697 was), they would have run five godot
#                     invocations inside a live publish.
#   @cowir-ai         delegated to an UNTRACKED tmp/ copy with the same blind default, and
#                     their hand-rolled per-tree loop had gone NARROWER than the fix it worked
#                     around (4 roots vs 5) — and because DEPLOY_DIR overrides DEPLOY_GLOB,
#                     keeping that loop would have DISABLED the native all-lane scan.
#   @cowir-sfx        hash-identical today, and said the right thing about it: "my copy is
#                     current" is exactly the claim CLAUDE.md warns is a property of your
#                     checkout. Verifying it is weaker than not depending on it.
#
# A workaround for a fixed bug does not merely become redundant — it can defeat the fix.
# So: resolve from origin/main, pass everything through, and FAIL CLOSED if resolution fails.
#
# Exit codes are box_busy.sh's own, passed through UNCHANGED (0 = free / publish in flight for
# --publish, 1 = busy / none), EXCEPT: 3 means THIS script could not resolve the tool, so the
# caller learned nothing. A caller must treat 3 as "hold" — never as the absence of a publish.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

PIN_DIR="${BOX_PIN_DIR:-tmp/boxpin}"
PIN="$PIN_DIR/box_busy.origin.sh"
REF="${BOX_PIN_REF:-origin/main}"

if [ "${1:-}" = "--selftest" ]; then
  fails=0
  ## 1 it resolves and the pinned bytes EQUAL the ref's
  out="$(BOX_PIN_DIR="tmp/boxpin_self.$$" "$0" --roots 2>&1)"; e=$?
  [ "$e" = 0 ] || { echo "FAIL arm1: --roots through the pin exited $e: $out"; fails=1; }
  h1="$(git hash-object "tmp/boxpin_self.$$/box_busy.origin.sh" 2>/dev/null)"
  h2="$(git rev-parse "$REF:tools/box_busy.sh" 2>/dev/null)"
  [ -n "$h1" ] && [ "$h1" = "$h2" ] || { echo "FAIL arm2: pinned bytes != $REF ($h1 vs $h2)"; fails=1; }
  ## 3 a bad ref FAILS CLOSED with 3 — never 0, never 1
  out="$(BOX_PIN_REF=refs/heads/__no_such_ref__ BOX_PIN_DIR="tmp/boxpin_self.$$" "$0" --publish 2>&1)"; e=$?
  [ "$e" = 3 ] || { echo "FAIL arm3: unresolvable ref exited $e, want 3 (fail-closed): $out"; fails=1; }
  case "$out" in *"could not resolve"*) ;; *) echo "FAIL arm4: no reason printed: $out"; fails=1 ;; esac
  ## 5 exit codes pass through: --publish is 0 or 1, and must not be mangled to 3
  BOX_PIN_DIR="tmp/boxpin_self.$$" "$0" --publish >/dev/null 2>&1; e=$?
  case "$e" in 0|1) ;; *) echo "FAIL arm5: --publish passthrough gave $e, want 0 or 1"; fails=1 ;; esac
  ## 6 ARGUMENTS REACH THE TOOL: a bogus flag must produce box_busy's own usage code 2,
  ##   which proves we exec it with "$@" rather than swallowing arguments.
  BOX_PIN_DIR="tmp/boxpin_self.$$" "$0" --definitely-not-a-flag >/dev/null 2>&1; e=$?
  [ "$e" = 2 ] || { echo "FAIL arm6: bogus flag gave $e, want box_busy's own 2"; fails=1; }
  rm -rf "tmp/boxpin_self.$$"
  [ "$fails" = 0 ] && echo "box_busy_pinned selftest: 6 arms ran, every assertion held"
  exit "$fails"
fi

mkdir -p "$PIN_DIR" 2>/dev/null
if ! git show "$REF:tools/box_busy.sh" > "$PIN.tmp" 2>/dev/null || [ ! -s "$PIN.tmp" ]; then
  rm -f "$PIN.tmp"
  echo "box_busy_pinned: could not resolve $REF:tools/box_busy.sh — HOLD (exit 3)" >&2
  exit 3
fi
mv -f "$PIN.tmp" "$PIN"
chmod +x "$PIN" 2>/dev/null
exec bash "$PIN" "$@"
