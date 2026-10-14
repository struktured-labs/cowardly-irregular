#!/usr/bin/env bash
# fold_selftest.sh — prove fold.sh's four refusal/accept arms on a throwaway worktree. Pushes nothing.
#
# Arms: an unpushed sha is skipped · an older READYed commit on the branch is folded (not the tip) · a missing branch is skipped · an undeclared file
# deletion is skipped · the same deletion, declared in FOLD_ALLOW_DELETE, merges · a tip whose HISTORY holds an [UNVERIFIED] commit is skipped. Probe tips are
# LOCAL refs under refs/remotes/origin/lane/zz-selftest-*, removed on exit with the worktree.
# Exit 0 = all four arms behaved; 1 = an arm did not.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
WT="$REPO/tmp/fold_selftest_$$"
REF=refs/remotes/origin/lane/zz-selftest-del
REF2=refs/remotes/origin/lane/zz-selftest-label
cleanup() { git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; git -C "$REPO" update-ref -d "$REF" 2>/dev/null; git -C "$REPO" update-ref -d "$REF2" 2>/dev/null; git -C "$REPO" branch -D zz-selftest-base fold/v3.33.997 >/dev/null 2>&1; }
trap cleanup EXIT
git worktree add -q -b zz-selftest-base "$WT" origin/main || { echo "selftest: worktree add failed" >&2; exit 1; }
cd "$WT"
VICTIM="$(git ls-files 'test/unit/test_*.gd' | head -1)"
git rm -q "$VICTIM" && git commit -qm "selftest: delete one file" || exit 1
DEL="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "selftest: a later commit on the same branch"
git update-ref "$REF" "$(git rev-parse HEAD)"
git checkout -q --detach origin/main
git commit -q --allow-empty -m "[UNVERIFIED] selftest: a labelled commit below the tip"
git commit -q --allow-empty -m "selftest: an unlabelled tip on top"
git update-ref "$REF2" "$(git rev-parse HEAD)"
git checkout -q --detach origin/main

FAILS=0
run() {  # $1 label, $2 expected EC, $3 expected line pattern, rest = env + fold.sh args
  local label="$1" want_ec="$2" pat="$3"; shift 3
  local out ec
  out="$(env "$@" 2>&1)"; ec=$?
  git checkout -q --detach origin/main; git branch -D fold/v3.33.997 >/dev/null 2>&1
  if [ "$ec" = "$want_ec" ] && printf '%s\n' "$out" | grep -q "$pat"; then echo "ok   $label"; else
    echo "FAIL $label (ec=$ec, wanted $want_ec and /$pat/)"; printf '%s\n' "$out" | sed 's/^/     /'; FAILS=1; fi
}
F="$REPO/tools/fold_gate/fold.sh"
run "unpushed sha is skipped"        1 "is not on origin/lane/zz-selftest-del"      FOLD_REPO="$WT" FOLD_ALLOW_DELETE= "$F" 997 zz-selftest-del:deadbeef0
run "missing branch is skipped"      1 "SKIP zz-no-such-branch: no origin"    FOLD_REPO="$WT" FOLD_ALLOW_DELETE= "$F" 997 zz-no-such-branch:abc123456
run "undeclared deletion is skipped" 1 "undeclared deletion(s): $VICTIM"      FOLD_REPO="$WT" FOLD_ALLOW_DELETE= "$F" 997 "zz-selftest-del:${DEL:0:9}"
run "an older READYed commit is folded, not the tip" 0 "folding the READYed ${DEL:0:9}"   FOLD_REPO="$WT" FOLD_ALLOW_DELETE="$VICTIM" "$F" 997 "zz-selftest-del:${DEL:0:9}"
run "declared deletion merges"       0 "MERGED zz-selftest-del"               FOLD_REPO="$WT" FOLD_ALLOW_DELETE="$VICTIM" "$F" 997 "zz-selftest-del:${DEL:0:9}"
run "a labelled ancestor is skipped" 1 "SKIP zz-selftest-label: an \[UNVERIFIED\] commit would ride in" FOLD_REPO="$WT" FOLD_ALLOW_DELETE= "$F" 997 "zz-selftest-label:$(git rev-parse --short=9 "$REF2")"
rm -f "$WT"/tmp/chain997.sh tmp/gate997.sh tmp/rungate997.sh tmp/wedgewatch997.sh
exit "$FAILS"
