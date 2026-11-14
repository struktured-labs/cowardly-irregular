#!/usr/bin/env bash
# queue_tip.sh — record one READY tip for fold NNN, checked against origin, in both files fold.sh is fed from.
#
#   tools/fold_gate/queue_tip.sh NNN <branch> <sha>   (branch with or without the lane/ prefix)
#   tools/fold_gate/queue_tip.sh NNN --list
#   tools/fold_gate/queue_tip.sh --selftest
#
# Until now each tip was checked with `git ls-remote` by hand and appended to tmp/fold_args_NNN.txt
# (branch:sha) and, separately, tmp/fold_verified_NNN.txt (bare sha). On .801 the second file was written
# in the first file's format and fold.sh silently skipped two tips. This writes both from one input.
#
# Refuses (exit 1, nothing written) unless the sha resolves to a commit that is ON origin/lane/<branch>
# after a fetch of that branch, and is not already on origin/main. A branch already queued is REPLACED, never listed twice (a READY that
# moves its tip names the new sha). Exit 0 = recorded / listed · 1 = refused · 2 = usage.
# QUEUE_DIR overrides tmp/ and QUEUE_NO_FETCH=1 skips the fetch (both for the selftest).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

queue() {
  local nnn="$1" b="${2#lane/}" want="$3" dir="${QUEUE_DIR:-$REPO/tmp}" full tip args ver
  case "$nnn" in ''|*[!0-9]*) echo "queue_tip: release number '$nnn' is not a number" >&2; return 2 ;; esac
  [ -n "$b" ] && [ -n "$want" ] || { echo "usage: queue_tip.sh NNN <branch> <sha>" >&2; return 2; }
  if [ "${QUEUE_NO_FETCH:-0}" != 1 ]; then
    git -C "$REPO" fetch -q origin "refs/heads/lane/$b:refs/remotes/origin/lane/$b" 2>/dev/null \
      || { echo "queue_tip: REFUSED $b: origin has no lane/$b" >&2; return 1; }
  fi
  tip="$(git -C "$REPO" rev-parse -q --verify "refs/remotes/origin/lane/$b^{commit}")" \
    || { echo "queue_tip: REFUSED $b: no origin/lane/$b" >&2; return 1; }
  full="$(git -C "$REPO" rev-parse -q --verify "$want^{commit}" 2>/dev/null)" \
    || { echo "queue_tip: REFUSED $b: '$want' names no commit here (unpushed, or a typo)" >&2; return 1; }
  git -C "$REPO" merge-base --is-ancestor "$full" "$tip" \
    || { echo "queue_tip: REFUSED $b: ${full:0:9} is not on origin/lane/$b (tip ${tip:0:9})" >&2; return 1; }
  ! git -C "$REPO" merge-base --is-ancestor "$full" "refs/remotes/origin/main" \
    || { echo "queue_tip: REFUSED $b: ${full:0:9} is already on origin/main — nothing to fold" >&2; return 1; }
  args="$dir/fold_args_$nnn.txt"; ver="$dir/fold_verified_$nnn.txt"
  mkdir -p "$dir"; touch "$args" "$ver"
  local old; old="$(awk -F: -v b="$b" '$1==b{print $2}' "$args")"
  awk -F: -v b="$b" '$1!=b' "$args" > "$args.new" && mv "$args.new" "$args"
  [ -n "$old" ] && { grep -vxF "$old" "$ver" > "$ver.new"; mv "$ver.new" "$ver"; }
  echo "$b:${full:0:9}" >> "$args"; echo "${full:0:9}" >> "$ver"
  local note=""; [ "$full" = "$tip" ] || note=" — an older commit than the tip ${tip:0:9}"
  echo "queued $b:${full:0:9}${old:+ (replaces $old)}$note"
}

list() {
  local dir="${QUEUE_DIR:-$REPO/tmp}" a v
  a="$(wc -l < "$dir/fold_args_$1.txt" 2>/dev/null || echo 0)"; v="$(wc -l < "$dir/fold_verified_$1.txt" 2>/dev/null || echo 0)"
  cat "$dir/fold_args_$1.txt" 2>/dev/null
  echo "-- $a tip(s), $v verified sha(s)"; [ "$a" = "$v" ] || { echo "queue_tip: the two files disagree" >&2; return 1; }
}

selftest() {
  local d fails=0 ref=refs/remotes/origin/lane/zz-queue-selftest base t1 t2 t3 out ec
  d="$REPO/tmp/queue_selftest_$$"; mkdir -p "$d"
  base="$(git -C "$REPO" rev-parse origin/main)"
  t1="$(git -C "$REPO" commit-tree "$base^{tree}" -p "$base" -m "queue selftest 1")"
  t2="$(git -C "$REPO" commit-tree "$base^{tree}" -p "$t1" -m "queue selftest 2")"
  t3="$(git -C "$REPO" commit-tree "$base^{tree}" -p "$base" -m "queue selftest off-branch")"
  git -C "$REPO" update-ref "$ref" "$t2"
  trap 'git -C "$REPO" update-ref -d '"$ref"'; rm -rf "'"$d"'"' RETURN
  arm() { local label="$1" want="$2" pat="$3"; shift 3
    out="$(QUEUE_DIR="$d" QUEUE_NO_FETCH=1 "$@" 2>&1)"; ec=$?
    if [ "$ec" = "$want" ] && printf '%s\n' "$out" | grep -q -- "$pat"; then echo "ok   $label"
    else echo "FAIL $label (ec=$ec, wanted $want and /$pat/): $out"; fails=1; fi; }
  arm "the tip is queued in both files"        0 "queued zz-queue-selftest:${t2:0:9}" queue 990 lane/zz-queue-selftest "${t2:0:9}"
  arm "an older commit on the branch is queued" 0 "an older commit than the tip"      queue 990 zz-queue-selftest "${t1:0:9}"
  arm "the re-queue replaced, not appended"     0 "1 tip(s), 1 verified"              list 990
  [ "$(cat "$d/fold_verified_990.txt")" = "${t1:0:9}" ] && echo "ok   the verified file holds the bare sha" \
    || { echo "FAIL the verified file holds: $(cat "$d/fold_verified_990.txt")"; fails=1; }
  arm "a sha off the branch is refused"        1 "is not on origin/lane/zz-queue-selftest" queue 990 zz-queue-selftest "${t3:0:9}"
  arm "a sha already on main is refused"       1 "already on origin/main"             queue 990 zz-queue-selftest "${base:0:9}"
  arm "a sha that names nothing is refused"    1 "names no commit"                    queue 990 zz-queue-selftest 0000000feedface
  arm "a missing branch is refused"            1 "no origin/lane/zz-no-such"          queue 990 zz-no-such "${t2:0:9}"
  arm "a refusal wrote nothing"                0 "1 tip(s), 1 verified"              list 990
  echo "queue_tip selftest: $([ $fails = 0 ] && echo 'every arm as expected' || echo 'an arm FAILED')"
  return "$fails"
}

case "${1:-}" in
  --selftest) selftest ;;
  *) [ "${2:-}" = "--list" ] && { list "$1"; exit; }; [ "$#" = 3 ] || { sed -n 3,5p "$0" >&2; exit 2; }; queue "$@" ;;
esac
