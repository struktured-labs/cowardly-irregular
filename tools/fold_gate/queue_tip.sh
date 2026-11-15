#!/usr/bin/env bash
# queue_tip.sh — record one READY tip for fold NNN, checked against origin, in both files fold.sh is fed from.
#
#   tools/fold_gate/queue_tip.sh NNN <branch> <sha>   (branch with or without the lane/ prefix)
#   tools/fold_gate/queue_tip.sh NNN --list
#   tools/fold_gate/queue_tip.sh NNN --couple <branch> <branch> ...   (all fold together or none do)
#   tools/fold_gate/queue_tip.sh --selftest
#
# Until now each tip was checked with `git ls-remote` by hand and appended to tmp/fold_args_NNN.txt
# (branch:sha) and, separately, tmp/fold_verified_NNN.txt (bare sha). On .801 the second file was written
# in the first file's format and fold.sh silently skipped two tips. This writes both from one input.
#
# Refuses (exit 1, nothing written) unless the sha resolves to a commit that is ON origin/lane/<branch>
# after a fetch of that branch, and is not already on origin/main. A branch already queued is REPLACED, never listed twice (a READY that
# moves its tip names the new sha). Exit 0 = recorded / listed · 1 = refused · 2 = usage.
# Files land in tmp/ of the checkout you are STANDING in (fold.sh reads them from there), not of the
# checkout the script lives in: run from another worktree, the old rule wrote where no fold looked (.803).
# QUEUE_DIR overrides that and QUEUE_NO_FETCH=1 skips the fetch (both for the selftest).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

dest_dir() {
  [ -n "${QUEUE_DIR:-}" ] && { echo "$QUEUE_DIR"; return; }
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$REPO"
  echo "$top/tmp"
}

queue() {
  local nnn="$1" b="${2#lane/}" want="$3" dir="$(dest_dir)" full tip args ver
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
  echo "queued $b:${full:0:9}${old:+ (replaces $old)}$note -> $args"
}

list() {
  local dir; dir="$(dest_dir)"; local a v
  a="$(wc -l < "$dir/fold_args_$1.txt" 2>/dev/null || echo 0)"; v="$(wc -l < "$dir/fold_verified_$1.txt" 2>/dev/null || echo 0)"
  local gone=0 line b sha full
  while IFS= read -r line; do
    [ -n "$line" ] || continue; b="${line%%:*}"; sha="${line#*:}"
    # A queued sha is only good while its branch still holds it: a force-push after READY drops it,
    # and fold.sh then SKIPs that branch at fold time. Say so here, before the fold.
    full="$(git -C "$REPO" rev-parse -q --verify "$sha^{commit}" 2>/dev/null)"
    if [ -n "$full" ] && git -C "$REPO" merge-base --is-ancestor "$full" "refs/remotes/origin/lane/$b" 2>/dev/null; then
      echo "$line"
    else echo "$line   <- GONE: no longer on origin/lane/$b (force-pushed or deleted); fold.sh would SKIP it"; gone=1; fi
  done < "$dir/fold_args_$1.txt"
  echo "-- $a tip(s), $v verified sha(s)"; [ "$a" = "$v" ] || { echo "queue_tip: the two files disagree" >&2; return 1; }
  # A COUPLE is a set whose evidence was measured only together (.804: a census green only with
  # threatblock AND toast in the tree). Pulling one member late must pull the rest, so a set that is
  # partly queued is named here and fails the list.
  local cf="$dir/fold_couples_$1.txt" set m have miss
  if [ -f "$cf" ]; then
    while IFS= read -r set; do
      [ -n "$set" ] || continue; have=""; miss=""
      for m in $set; do
        if awk -F: -v b="$m" '$1==b{f=1} END{exit !f}' "$dir/fold_args_$1.txt"; then have="$have $m"; else miss="$miss $m"; fi
      done
      if [ -n "$have" ] && [ -n "$miss" ]; then echo "COUPLE BROKEN: queued$have but not$miss — fold all or none"; gone=1; fi
    done < "$cf"
  fi
  # The fold applies the tips IN THIS ORDER onto origin/main; check that now with merge-tree, chained
  # through commit-tree so each tip meets everything before it (.804: spite x a glacius tip collided in
  # BattleScene.gd, found by hand before the fold). Names the first tip that cannot apply and the
  # earlier queued tip it collides with.
  local base t tree prior
  base="$(git -C "$REPO" rev-parse -q --verify refs/remotes/origin/main)" || base=""
  if [ -n "$base" ] && [ "$gone" = 0 ]; then
    while IFS=: read -r b sha; do
      [ -n "$b" ] || continue
      if tree="$(git -C "$REPO" merge-tree --write-tree "$base" "$sha" 2>/dev/null)"; then
        base="$(git -C "$REPO" commit-tree "$(printf '%s' "$tree" | head -1)" -p "$base" -p "$sha" -m "queue_tip preview")"
      else
        prior=""
        while IFS=: read -r pb ps; do
          [ "$pb" = "$b" ] && break
          git -C "$REPO" merge-tree --write-tree "$ps" "$sha" >/dev/null 2>&1 || prior="$prior $pb"
        done < "$dir/fold_args_$1.txt"
        echo "CONFLICT: $b ${sha} does not apply after the tips above it${prior:+ (collides with:$prior)}"; gone=1; break
      fi
    done < "$dir/fold_args_$1.txt"
  fi
  return "$gone"
}

couple() {
  local nnn="$1" dir; shift; dir="$(dest_dir)"
  [ "$#" -ge 2 ] || { echo "usage: queue_tip.sh NNN --couple <branch> <branch> ..." >&2; return 2; }
  mkdir -p "$dir"; local m out=""; for m in "$@"; do out="$out ${m#lane/}"; done
  echo "${out# }" >> "$dir/fold_couples_$nnn.txt"; echo "coupled:${out}"
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
  git -C "$REPO" update-ref "$ref" "$t3"
  arm "a queued sha the branch lost is GONE"   1 "GONE: no longer on origin/lane/zz-queue-selftest" list 990
  git -C "$REPO" update-ref "$ref" "$t2"
  local c1 c2 blob1 blob2 tr1 tr2
  blob1="$(printf 'one\n' | git -C "$REPO" hash-object -w --stdin)"; blob2="$(printf 'two\n' | git -C "$REPO" hash-object -w --stdin)"
  tr1="$(printf '100644 blob %s\tzz_queue_selftest.txt\n' "$blob1" | git -C "$REPO" mktree)"; tr2="$(printf '100644 blob %s\tzz_queue_selftest.txt\n' "$blob2" | git -C "$REPO" mktree)"
  c1="$(git -C "$REPO" commit-tree "$tr1" -p "$base" -m "queue selftest conflict 1")"; c2="$(git -C "$REPO" commit-tree "$tr2" -p "$base" -m "queue selftest conflict 2")"
  git -C "$REPO" update-ref refs/remotes/origin/lane/zz-queue-c1 "$c1"; git -C "$REPO" update-ref refs/remotes/origin/lane/zz-queue-c2 "$c2"
  arm "a clean pair passes the merge check"   0 "1 tip(s)"                                 list 990
  queue 991 zz-queue-c1 "${c1:0:9}" >/dev/null 2>&1; QUEUE_DIR="$d" QUEUE_NO_FETCH=1 queue 991 zz-queue-c1 "${c1:0:9}" >/dev/null
  QUEUE_DIR="$d" QUEUE_NO_FETCH=1 queue 991 zz-queue-c2 "${c2:0:9}" >/dev/null
  arm "a tip that cannot apply is a CONFLICT"  1 "CONFLICT: zz-queue-c2 .* (collides with: zz-queue-c1)" list 991
  git -C "$REPO" update-ref -d refs/remotes/origin/lane/zz-queue-c1; git -C "$REPO" update-ref -d refs/remotes/origin/lane/zz-queue-c2
  arm "a couple is recorded"                   0 "coupled: zz-queue-selftest zz-partner"  couple 990 lane/zz-queue-selftest zz-partner
  arm "a half-queued couple is BROKEN"         1 "COUPLE BROKEN: queued zz-queue-selftest but not zz-partner" list 990
  echo "zz-partner:${t2:0:9}" >> "$d/fold_args_990.txt"; echo "${t2:0:9}" >> "$d/fold_verified_990.txt"
  out="$(QUEUE_DIR="$d" "$REPO/tools/fold_gate/queue_tip.sh" 990 --list 2>&1)"
  printf '%s\n' "$out" | grep -q "COUPLE BROKEN" && { echo "FAIL a whole couple still reads BROKEN: $out"; fails=1; } || echo "ok   a whole couple is not BROKEN"
  local other="$d/other_checkout"; mkdir -p "$other"; git -C "$other" init -q
  out="$(cd "$other" && env -u QUEUE_DIR bash -c "source '$REPO/tools/fold_gate/queue_tip.sh' --source-only; dest_dir")"
  [ "$out" = "$other/tmp" ] && echo "ok   files land in the checkout you stand in" \
    || { echo "FAIL dest from another checkout was '$out', wanted '$other/tmp'"; fails=1; }
  echo "queue_tip selftest: $([ $fails = 0 ] && echo 'every arm as expected' || echo 'an arm FAILED')"
  return "$fails"
}

case "${1:-}" in
  --source-only) return 0 2>/dev/null || exit 0 ;;
  --selftest) selftest ;;
  *) [ "${2:-}" = "--list" ] && { list "$1"; exit; }; [ "${2:-}" = "--couple" ] && { n="$1"; shift 2; couple "$n" "$@"; exit; }; [ "$#" = 3 ] || { sed -n 3,5p "$0" >&2; exit 2; }; queue "$@" ;;
esac
