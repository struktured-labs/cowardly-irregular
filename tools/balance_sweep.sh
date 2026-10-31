#!/usr/bin/env bash
# balance_sweep.sh — the three-path boss table (Carmelo's directive 19478 + addendum 19479).
#
# One cell = one BAL_PATH against one boss, at the boss's OWN authored level. The ladder is
# DERIVED from the dungeon scripts' `boss_id` plus the three Vertex trials, and each row's level is
# read out of monsters.json at run time, so neither can go stale here the way a pinned table would.
#
# ⛔ ALL FOUR PATHS ARE AUTOBATTLE SCRIPTS. HeadlessBattleResolver._selection_phase asks
# AutobattleSystem.execute_grid_autobattle for every player action and has no second input path, so
# a "manual" row is A COMPETENT SCRIPT PLAYING THAT WAY and never a human: it cannot read a tell it
# was not written for, which is where a real player is strongest and this approximation weakest.
# Any table built from this output has to carry that sentence.
#
# ⛔ THE `label` COLUMN IS THE ONE THAT MAKES THE REST READABLE. A path installs a script; nothing
# else says its distinctive rule ever ran, and a party that dies during setup produces a perfectly
# clean 0% row whose burst never fired. balance_harness.gd prints the game's own per-rule fire
# counts; `label=unproven` here means one of those lines carried a `**` warning and the row's name
# is not evidence of its behaviour.
#
# USAGE
#   tools/balance_sweep.sh                      # full ladder, 4 paths, 20 trials
#   SWEEP_PATHS="manual oneshot" tools/balance_sweep.sh
#   SWEEP_BOSSES="the_calibrant shadow_dragon" BAL_TRIALS=5 tools/balance_sweep.sh
#   tools/balance_sweep.sh --selftest           # parser arms, no godot
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

TRIALS="${BAL_TRIALS:-20}"
SWEEP_PATHS="${SWEEP_PATHS:-default auto manual oneshot}"
BAG="${BAL_BAG:-potion:5,hi_potion:2,ether:3}"
BUDGET="${SWEEP_BUDGET:-420}"
OUT="${SWEEP_OUT:-tmp/balance_sweep.tsv}"
LOGDIR="${SWEEP_LOGDIR:-tmp/sweep_$$}"

## The ladder. Every id here is reachable in the shipped game: thirteen are a dungeon's `boss_id`
## or its BossTrigger, three are the Vertex trials TrialRouting routes between, and
## optimization_itself is a roaming Abstract encounter struktured named as one of the four walls.
## DELIBERATELY NOT the 47 rows monsters.json flags `boss`: that set includes the five spotlight
## duels, whose win conditions (survive_turns, status_threshold) this resolver does not model at
## all, and the autogrind meta-bosses, which no ladder position gates.
LADDER="${SWEEP_BOSSES:-cave_rat_king masterite_warden_suburban masterite_tempo_steampunk \
cartographer_wraith masterite_warden_industrial fire_dragon ice_dragon lightning_dragon \
masterite_arbiter_futuristic shadow_dragon optimization_itself masterite_curator_abstract \
chancellor_mordaine the_operator the_examiner the_margin the_calibrant}"

# ── the parser ──────────────────────────────────────────────────────────────────────────────
# ⛔ IT MUST SAY "no" OUT LOUD. An extraction that silently yields empty prints a table of blanks
# that reads like a measurement, which is this repo's most expensive recurring shape. Every field
# that does not match comes back as the literal `?` and the row is marked parse=BAD.
_parse() {
    python3 - "$1" <<'PYEOF'
import re, sys
txt = open(sys.argv[1], errors="replace").read()
def one(pat, group=1):
    m = re.search(pat, txt, re.M)
    return m.group(group) if m else "?"
win   = one(r'^\[BAL\] win rate\s+(\d+)/(\d+) = ([\d.]+)%', 3)
wn    = one(r'^\[BAL\] win rate\s+(\d+)/(\d+) = ([\d.]+)%', 1)
rds   = one(r'^\[BAL\] rounds to win\s+([\d.]+) mean')
osr   = one(r'^\[BAL\] one-shots\s+(\d+)/(\d+) = ([\d.]+)%', 3)
hp    = one(r'^\[BAL\] party HP left\s+([\d.]+)%')
stale = one(r'^\[BAL\] termination\s+stalemate\s+(\d+)')
if stale == "?":
    stale = "0" if re.search(r'^\[BAL\] termination', txt, re.M) else "?"
label = "unproven" if re.search(r'^\[BAL\]\s+\S+\s+turns=.*\*\*', txt, re.M) else "ok"
bad = "BAD" if "?" in (win, wn, osr, hp, stale) else "ok"
print("\t".join([win, wn, rds, osr, hp, stale, label, bad]))
PYEOF
}

_selftest() {
    local pass=0 fail=0 t
    t="$(mktemp -p tmp sweep_selftest_XXXX.log)"
    # arm 1: a complete run parses every field
    cat > "$t" <<'EOF'
[BAL] win rate      13/20 = 65.0%
[BAL] rounds to win 7.31 mean over the 13 victories
[BAL] one-shots     4/20 = 20.0%  (every foe dead in the phase the first damage landed)
[BAL] mean rounds   9.10  (time-to-kill, over 20 battles reporting it)
[BAL] party HP left 41.2% mean
[BAL] termination   (none)           18
[BAL] termination   stalemate        2
[BAL] rule fires over the whole run (path=manual); r0 is the top row and first match wins:
[BAL]   fighter    turns=140   r0=0 r1=0 r2=60 r3=80
EOF
    if [ "$(_parse "$t")" = "$(printf '65.0\t13\t7.31\t20.0\t41.2\t2\tok\tok')" ]; then
        pass=$((pass+1)); else fail=$((fail+1)); echo "  arm1 complete-run parse: got [$(_parse "$t")]"; fi
    # arm 2: THE ONE THAT MATTERS — a truncated run must come back BAD, not blank-but-plausible
    printf '[BAL] win rate      13/20 = 65.0%%\n' > "$t"
    case "$(_parse "$t")" in *$'\t'BAD) pass=$((pass+1));; *) fail=$((fail+1)); echo "  arm2 truncated run must parse=BAD: got [$(_parse "$t")]";; esac
    # arm 3: a `**` note anywhere in the fire counts marks the row unproven
    cat > "$t" <<'EOF'
[BAL] win rate      0/20 = 0.0%
[BAL] one-shots     0/20 = 0.0%
[BAL] party HP left 0.0% mean
[BAL] termination   (none)           20
[BAL]   fighter    turns=40    r0=0 r1=0 r2=40   ** setup_complete NEVER HELD **
EOF
    case "$(_parse "$t")" in *unproven*) pass=$((pass+1));; *) fail=$((fail+1)); echo "  arm3 ** note must mark unproven: got [$(_parse "$t")]";; esac
    # arm 4: and a clean fire-count block must NOT be marked unproven, or arm 3 proves nothing
    cat > "$t" <<'EOF'
[BAL] win rate      0/20 = 0.0%
[BAL] one-shots     0/20 = 0.0%
[BAL] party HP left 0.0% mean
[BAL] termination   (none)           20
[BAL]   fighter    turns=40    r0=0 r1=0 r2=40
EOF
    case "$(_parse "$t")" in *unproven*) fail=$((fail+1)); echo "  arm4 clean block marked unproven";; *) pass=$((pass+1));; esac
    # arm 5: every ladder id must exist in monsters.json with a level, or its cell would run blind
    local missing
    missing="$(python3 - "$LADDER" <<'PYEOF'
import json, sys
m = json.load(open("data/monsters.json"))
bad = [i for i in sys.argv[1].split() if i not in m or "level" not in m.get(i, {})]
print(" ".join(bad))
PYEOF
)"
    if [ -z "$missing" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  arm5 ladder ids absent from monsters.json: $missing"; fi
    rm -f "$t"
    echo "selftest: $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) _selftest; exit $? ;;
    "") ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

_selftest || { echo "BLOCKED: the sweep's own parser is broken — a table from it would be fiction" >&2; exit 2; }

mkdir -p "$LOGDIR" tmp
printf 'boss\tlevel\tpath\twin_pct\twins\trounds_to_win\tone_shot_pct\thp_left_pct\tstalemates\tlabel\tparse\n' > "$OUT"

for boss in $LADDER; do
    lvl="$(python3 -c 'import json,sys; print(int(json.load(open("data/monsters.json"))[sys.argv[1]]["level"]))' "$boss")"
    for p in $SWEEP_PATHS; do
        log="$LOGDIR/${boss}_${p}.log"
        BAL_PATH="$p" BAL_LEVEL="$lvl" BAL_TRIALS="$TRIALS" BAL_ENEMIES="$boss" BAL_BAG="$BAG" \
        XDG_DATA_HOME="$PWD/tmp/xdg" \
        tools/bounded_godot.sh --label "sweep:$boss:$p" --budget "$BUDGET" --log "$log" \
            -- godot --headless --audio-driver Dummy -s res://tools/balance_harness.gd
        ec=$?
        if [ "$ec" -eq 124 ]; then
            printf '%s\t%s\t%s\tWEDGE\t?\t?\t?\t?\t?\twedge\tBAD\n' "$boss" "$lvl" "$p" >> "$OUT"
            echo "[sweep] $boss / $p — WEDGED at ${BUDGET}s, no verdict"
            continue
        fi
        row="$(_parse "$log")"
        printf '%s\t%s\t%s\t%s\n' "$boss" "$lvl" "$p" "$row" >> "$OUT"
        echo "[sweep] $(printf '%-30s %-8s' "$boss" "$p") $row"
    done
done

echo ""
echo "[sweep] table: $OUT     per-cell logs: $LOGDIR"
column -t -s $'\t' "$OUT" 2>/dev/null || cat "$OUT"
