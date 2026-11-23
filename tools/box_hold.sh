#!/usr/bin/env bash
# box_hold.sh — hold the box for a lane's CLAIMED slot, so tools/box_busy.sh says BUSY for the whole slot.
#
#   tools/box_hold.sh <lane> -- <command> [args...]   run <command> holding the box; exit with ITS exit code
#   tools/box_hold.sh --selftest                      watch every arm flip (no engine, scratch markers only)
#
# WHY. 2026-11-11: box_busy said "FREE (other lanes' godot up: 2)" while cowir-adhoc's claimed slot was mid-run, and
# cowir-battle started an engine beside it. box_busy judges a gate marker and a publish; a lane's slot wrote nothing, and
# BETWEEN its steps there is no process to count. This writes the slot marker box_busy reads (--slot-marker names the
# path): pid, lane, what, since. The channel CLAIM/RELEASE is still the protocol; this makes the claim visible to a script.
#
# It REFUSES to start (exit 3, nothing run) when box_busy reads BUSY: a gate, a publish, or another lane's live hold.
# The marker is taken with noclobber, so two lanes starting in the same second cannot both get it. A marker whose pid is
# dead is stale: it is replaced, and said. The marker is removed on exit by a trap, and ONLY if it is still this hold's
# own (a later holder's marker is never deleted). The command's own steps may ask box_busy: a process inside its own hold
# reads free (box_busy decides that by ancestry).
# Exit: the command's exit code · 2 usage · 3 refused (the reason is printed).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BB="${BOX_HOLD_BUSY:-$HERE/box_busy.sh}"

if [ "${1:-}" = "--selftest" ]; then
  mkdir -p "$HERE/../tmp"; T="$(mktemp -d "$HERE/../tmp/box_hold_selftest.XXXXXX")"; T="$(cd "$T" && pwd)"; trap 'rm -rf "$T"' EXIT
  fails=0; arms=0; EXPECT_ARMS=8; A() { arms=$((arms + 1)); }
  ## every arm runs against SCRATCH markers and a fold tree that does not exist: nothing here can see or touch a real hold
  E=(BOX_SLOT_MARKER="$T/slot" BOX_MARKER="$T/none.m" DEPLOY_DIR="$T/d" DEPLOY_GLOB="$T/none" FOLD_TREE="$T/none" BOX_BUSY_ENGINE="$T/no-engine")
  A  # arm 1  the command runs, its exit code comes back, and the marker is gone afterwards
  env "${E[@]}" "$0" cowir-zz -- sh -c 'exit 7'; e=$?
  [ "$e" = 7 ] || { echo "FAIL arm1a: exit code not passed through (got $e, want 7)"; fails=1; }
  [ ! -e "$T/slot" ] || { echo "FAIL arm1b: the marker outlived its hold"; fails=1; }
  A  # arm 2  WHILE it runs, box_busy reads BUSY and names the lane; a process INSIDE the hold reads free
  ## wait for the marker itself, bounded, never a fixed sleep (the holder's own box_busy check walks /proc for seconds,
  ## and arm 8 is about exactly that window); the held command then stays up until this arm releases it
  env "${E[@]}" "$0" cowir-zz -- sh -c "\"$BB\" > \"$T/inside.out\" 2>&1; echo \$? > \"$T/inside.ec\"; while [ ! -e \"$T/go\" ]; do sleep 0.2; done" & hp=$!
  n=0; while [ ! -e "$T/slot" ] && [ "$n" -lt 300 ]; do sleep 0.2; n=$((n + 1)); done
  [ -e "$T/slot" ] || { echo "FAIL arm2: the hold never wrote its marker (60 s)"; fails=1; }
  out="$(env "${E[@]}" "$BB" 2>/dev/null)"; e=$?
  case "$e/$out" in "1/BUSY: slot cowir-zz running"*) ;; *) echo "FAIL arm2a: box_busy did not read BUSY for the held slot (ec=$e): $out"; fails=1 ;; esac
  A  # arm 3  a second hold is REFUSED while the first lives, and runs nothing
  env "${E[@]}" "$0" cowir-yy -- sh -c "touch \"$T/second.ran\"" > "$T/second.out" 2>&1; e=$?
  [ "$e" = 3 ] || { echo "FAIL arm3a: a second hold was not refused (ec=$e): $(cat "$T/second.out")"; fails=1; }
  [ ! -e "$T/second.ran" ] || { echo "FAIL arm3b: the refused hold ran its command"; fails=1; }
  command grep -a -q 'cowir-zz' "$T/second.out" || { echo "FAIL arm3c: the refusal did not name the holder: $(cat "$T/second.out")"; fails=1; }
  command grep -a -q 'lane=cowir-zz' "$T/slot" 2>/dev/null || { echo "FAIL arm3d: the refused hold damaged the first holder's marker"; fails=1; }
  n=0; while [ ! -e "$T/inside.ec" ] && [ "$n" -lt 300 ]; do sleep 0.2; n=$((n + 1)); done
  : > "$T/go"; wait "$hp"
  [ "$(cat "$T/inside.ec" 2>/dev/null)" = 0 ] || { echo "FAIL arm2b: a process inside its own hold read BUSY: $(cat "$T/inside.out" 2>/dev/null)"; fails=1; }
  A  # arm 4  CONTROL for arm 3: with the first hold over, the same second hold runs
  env "${E[@]}" "$0" cowir-yy -- sh -c "touch \"$T/second.ran\"" > /dev/null 2>&1; e=$?
  { [ "$e" = 0 ] && [ -e "$T/second.ran" ]; } || { echo "FAIL arm4: a hold was refused on a free box (ec=$e)"; fails=1; }
  A  # arm 5  a STALE marker (dead pid) is replaced, and said
  printf 'pid=999999\nlane=cowir-dead\n' > "$T/slot"
  out="$(env "${E[@]}" "$0" cowir-zz -- sh -c 'exit 0' 2>&1)"; e=$?
  case "$e/$out" in 0/*"stale"*"cowir-dead"*) ;; *) echo "FAIL arm5: a stale marker was not replaced and named (ec=$e): $out"; fails=1 ;; esac
  A  # arm 6  a live GATE marker refuses the hold too (the fold's marker, a different file)
  sleep 20 & gp=$!; printf 'pid=%s\nwhat=chain\n' "$gp" > "$T/gate.m"
  out="$(env "${E[@]}" BOX_MARKER="$T/gate.m" "$0" cowir-zz -- sh -c "touch \"$T/gate.ran\"" 2>&1)"; e=$?
  kill "$gp" 2>/dev/null; wait "$gp" 2>/dev/null
  { [ "$e" = 3 ] && [ ! -e "$T/gate.ran" ]; } || { echo "FAIL arm6: a hold started beside a live gate marker (ec=$e): $out"; fails=1; }
  [ ! -e "$T/slot" ] || { echo "FAIL arm6b: a REFUSED hold left its marker behind (it takes the marker before it looks)"; fails=1; }
  A  # arm 8  THE WINDOW: while the hold is still ASKING box_busy, a sibling reader already reads BUSY naming it
  ## The holder's box_busy is a stub that waits (bounded) for this arm to finish reading, then runs the real one: so the
  ## sibling read below lands, deterministically, inside the check. Before the fix it read FREE there (no marker yet).
  printf '#!/usr/bin/env bash\ncase "${1:-}" in "") n=0; while [ ! -e "%s/sib.done" ] && [ "$n" -lt 300 ]; do sleep 0.2; n=$((n + 1)); done ;; esac\nexec "%s" "$@"\n' "$T" "$BB" > "$T/slowbb"; chmod +x "$T/slowbb"
  env "${E[@]}" BOX_HOLD_BUSY="$T/slowbb" "$0" cowir-race -- sh -c "touch \"$T/race.ran\"" > "$T/race.out" 2>&1 & rp=$!
  n=0; while [ ! -e "$T/slot" ] && kill -0 "$rp" 2>/dev/null && [ "$n" -lt 300 ]; do sleep 0.2; n=$((n + 1)); done
  out="$(env "${E[@]}" "$BB" 2>/dev/null)"; e=$?
  : > "$T/sib.done"; wait "$rp"; re=$?
  case "$e/$out" in "1/BUSY: slot cowir-race running"*) ;; *) echo "FAIL arm8a: a sibling read the box mid-check as not BUSY (ec=$e): $out"; fails=1 ;; esac
  { [ "$re" = 0 ] && [ -e "$T/race.ran" ]; } || { echo "FAIL arm8b: the hold did not go on to run once its check said free (ec=$re): $(cat "$T/race.out")"; fails=1; }
  [ ! -e "$T/slot" ] || { echo "FAIL arm8c: the marker outlived the raced hold"; fails=1; }
  A  # arm 7  usage: no lane, no --, no command, a lane with a space
  for bad in "" "cowir-zz" "cowir-zz --" "cowir zz -- true"; do
    # shellcheck disable=SC2086
    env "${E[@]}" "$0" $bad > /dev/null 2>&1; e=$?
    [ "$e" = 2 ] || { echo "FAIL arm7: '$bad' exited $e, want 2"; fails=1; }
  done
  [ "$arms" = "$EXPECT_ARMS" ] || { echo "FAIL: $arms of $EXPECT_ARMS arms ran"; fails=1; }
  [ "$fails" = 0 ] && echo "box_hold selftest: $arms/$EXPECT_ARMS arms ran, every assertion held"
  exit "$fails"
fi

LANE="${1:-}"; SEP="${2:-}"
case "$LANE" in ''|*[!A-Za-z0-9_-]*) echo "usage: tools/box_hold.sh <lane> -- <command> [args...]   (lane: letters, digits, - and _)" >&2; exit 2 ;; esac
[ "$SEP" = "--" ] && [ $# -ge 3 ] || { echo "usage: tools/box_hold.sh <lane> -- <command> [args...]" >&2; exit 2; }
shift 2

MARK="$("$BB" --slot-marker)" || { echo "box_hold: REFUSED: $BB --slot-marker failed, cannot name the marker" >&2; exit 3; }
mkdir -p "$(dirname "$MARK")" 2>/dev/null
if [ -f "$MARK" ]; then
  opid="$(sed -n 's/^pid=//p' "$MARK" | head -1)"
  if [ -z "$opid" ] || ! kill -0 "$opid" 2>/dev/null; then
    echo "box_hold: replacing a stale slot marker (pid ${opid:-?} not alive, lane $(sed -n 's/^lane=//p' "$MARK" | head -1)): $MARK" >&2
    rm -f "$MARK"
  fi
fi
## ⛔ TAKE THE MARKER FIRST, THEN LOOK. It used to ask box_busy and THEN write the marker. box_busy's FREE path walks /proc
## (~4 s on this box, measured 2026-11-13), and for those seconds a hold that was about to run read FREE to every other
## reader: a sibling lane's check, or the fold chain's. Now the marker exists before the question is asked, so a reader
## anywhere in that window reads BUSY. The question is still asked: box_busy runs as OUR child, reads our own marker as free
## by ancestry, and still judges a gate, a publish and a fold-tree engine. A refusal takes the marker back (the trap).
body="$(printf 'pid=%s\nlane=%s\nwhat=%s\nsince=%s\n' "$$" "$LANE" "$(printf '%s ' "$@" | cut -c1-120)" "$(date -u +%H:%M:%SZ)")"
if ! ( set -C; printf '%s\n' "$body" > "$MARK" ) 2>/dev/null; then
  echo "box_hold: REFUSED for $LANE, nothing run: another hold took the marker first: $(tr '\n' ' ' < "$MARK" 2>/dev/null)" >&2; exit 3
fi
_release() { [ "$(sed -n 's/^pid=//p' "$MARK" 2>/dev/null | head -1)" = "$$" ] && rm -f "$MARK"; return 0; }
trap _release EXIT
trap 'exit 130' INT; trap 'exit 143' TERM
r="$("$BB" 2>/dev/null)"; bec=$?
[ "$bec" = 0 ] || { echo "box_hold: REFUSED for $LANE, nothing run: ${r:-box_busy exit $bec with no reason}" >&2; exit 3; }
echo "box_hold: $LANE holds the box ($MARK) for: $*" >&2
"$@"
exit $?
