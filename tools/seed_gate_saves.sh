#!/usr/bin/env bash
# Give the gate's sandbox a READ-ONLY COPY of the player's saves, so the suite's real-save
# hydration actually runs. Copies IN; never copies back.
#
# WHY THIS EXISTS
# ---------------
# `test_real_saves_hydrate_smoke.gd` hydrates every save present on the machine through the
# state layer, so "Continue" cannot be the first place an aged save meets new load code. It
# reads `user://saves/` — which means its corpus is whatever profile the RUNNER points at.
#
# The deploy gate points at a fresh sandbox, by design and correctly: that sandbox is exactly
# why struktured's `saves/` is still dated 2026-09-11 after a day of publishing. But it also
# means the test has NEVER had a save to hydrate in a deploy. Measured 2026-09-16 on the real
# publish worktrees:
#
#     his saves                              7
#     pub357 / pub358 gate sandbox saves/     0 · 0
#     the .359 publish-wide sandbox           0
#
#     empty sandbox   Tests 2 · Passing none · Risky/Pending 2 · the file PENDS
#     seeded sandbox  Tests 2 · Passing 2    · Asserts 124
#
# So every release this lane has shipped carried an evidence line reading `failing=0` over a
# file that exercised nothing, and no cardinal in that line could say so — Scripts, Tests and
# EC are identical in both worlds (the test's own header measured this on 2026-08-22, three
# weeks before the thread that needed it).
#
# ⛔ THE TWO HORNS, AND WHY NEITHER IS TAKEN. Un-sandboxing the gate buys the coverage and puts
# a test suite that DELETES user://script_exports/ on his real profile. Leaving it sandboxed
# keeps him safe and the coverage inert. Seeding a COPY is strictly better than both: the test
# sees real, aged save SHAPES, and every write the suite makes lands in the sandbox.
#
# ONE-WAY BY CONSTRUCTION. There is no copy-back path in this file, and there must never be one:
# the suite mutates what it hydrates, and the whole point is that his originals never see it.
#
# Usage:  tools/seed_gate_saves.sh <sandbox XDG_DATA_HOME dir>
#         tools/seed_gate_saves.sh --selftest
# Exit:   0 seeded, or nothing to seed · 2 refused (unsafe destination, unreadable source)
set -uo pipefail

APP="godot/app_userdata/Cowardly Irregular"
REAL_BASE="${SEED_REAL_BASE:-$HOME/.local/share/$APP}"

_die() { echo "[seed] REFUSED: $*" >&2; exit 2; }

seed() {
    local sandbox="$1"
    [ -n "$sandbox" ] || _die "no sandbox given."

    # The destination must be a SANDBOX. Seeding into a real profile would be a write to the
    # thing this exists to protect, so the check is on the path shape rather than on intent.
    case "$sandbox" in
        */tmp/*|*/tmp) : ;;
        *) _die "${sandbox} is not under a tmp/ path. Refusing to seed anywhere that could be a real profile." ;;
    esac
    local dest="${sandbox}/${APP}/saves"
    local src="${REAL_BASE}/saves"
    # Belt and braces: never let source and destination be the same tree.
    if [ "$(cd "$src" 2>/dev/null && pwd -P)" = "$(cd "$dest" 2>/dev/null && pwd -P)" ] \
       && [ -d "$src" ]; then
        _die "source and destination resolve to the same directory (${src})."
    fi

    if [ ! -d "$src" ]; then
        # NOT an error: a fresh clone or CI has no saves, and the test pends there legitimately.
        # Say so, because a silent skip is how this stayed invisible for a year.
        echo "[seed] no saves at ${src} — nothing to seed; the hydration test will PEND."
        return 0
    fi
    local n; n="$(find "$src" -maxdepth 1 -type f 2>/dev/null | wc -l)"
    if [ "$n" -eq 0 ]; then
        echo "[seed] ${src} holds no save files — nothing to seed; the hydration test will PEND."
        return 0
    fi
    mkdir -p "$dest" || _die "could not create ${dest}"
    cp -a "$src/." "$dest/" || _die "copy failed into ${dest}"
    echo "[seed] ${n} save(s) copied into the gate sandbox — real-save hydration will RUN."
    echo "[seed]   from ${src}  (read only; nothing is ever copied back)"
    return 0
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-54s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-54s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/seedgate.XXXXXX")"
    local fake="$d/realprofile"
    mkdir -p "$fake/saves"
    printf 'slot0' > "$fake/saves/slot_0.json"
    printf 'slot1' > "$fake/saves/slot_1.json"
    local before; before="$(cd "$fake/saves" && cksum < slot_0.json)"

    local sb="$d/lane/tmp/gate_xdg"; mkdir -p "$sb"
    local out ec
    out="$(SEED_REAL_BASE="$fake" bash "$SELF" "$sb" 2>&1)"; ec=$?
    _eq "seeds into a tmp/ sandbox"                  "$ec" "0"
    _eq "  ...and the saves are there"               "$(ls "$sb/$APP/saves" 2>/dev/null | wc -l)" "2"
    case "$out" in *"will RUN"*) _eq "  ...and it says hydration will RUN" yes yes ;;
                   *) _eq "  ...and it says hydration will RUN" no yes ;; esac
    _eq "  ...and the SOURCE is untouched"           "$(cd "$fake/saves" && cksum < slot_0.json)" "$before"

    # a destination that is not a sandbox must be REFUSED, not seeded
    out="$(SEED_REAL_BASE="$fake" bash "$SELF" "$d/not-a-sandbox" 2>&1)"; ec=$?
    _eq "a destination outside tmp/ is REFUSED"      "$ec" "2"
    _eq "  ...and nothing was written there"         "$([ -e "$d/not-a-sandbox/$APP/saves" ] && echo present || echo absent)" "absent"

    # seeding from a profile that has none is NOT an error, and says so
    local empty="$d/emptyprofile"; mkdir -p "$empty"
    local sb2="$d/lane/tmp/gate_xdg2"; mkdir -p "$sb2"
    out="$(SEED_REAL_BASE="$empty" bash "$SELF" "$sb2" 2>&1)"; ec=$?
    _eq "a profile with no saves is not an error"    "$ec" "0"
    case "$out" in *"will PEND"*) _eq "  ...and it says the test will PEND" yes yes ;;
                   *) _eq "  ...and it says the test will PEND" no yes ;; esac
    _eq "  ...and it seeded nothing"                 "$([ -d "$sb2/$APP/saves" ] && echo present || echo absent)" "absent"

    # an empty saves DIRECTORY is the same case, and is the one a `[ -d ]` check would miss
    local emptydir="$d/emptydir"; mkdir -p "$emptydir/saves"
    local sb3="$d/lane/tmp/gate_xdg3"; mkdir -p "$sb3"
    out="$(SEED_REAL_BASE="$emptydir" bash "$SELF" "$sb3" 2>&1)"; ec=$?
    _eq "an EMPTY saves dir is not an error either"  "$ec" "0"
    case "$out" in *"will PEND"*) _eq "  ...and it says PEND rather than seeding 0" yes yes ;;
                   *) _eq "  ...and it says PEND rather than seeding 0" no yes ;; esac

    # no argument at all
    out="$(SEED_REAL_BASE="$fake" bash "$SELF" "" 2>&1)"; ec=$?
    _eq "no sandbox argument is REFUSED"             "$ec" "2"

    # ⛔ THE ONE-WAY PROPERTY, asserted on the file itself: a copy-back would defeat the whole
    # design, and a future edit that adds one should red here rather than in his profile.
    #
    # ⚠️ Scoped to real `cp` STATEMENTS. The first version searched the whole file and matched
    # ITS OWN PATTERN — the arm described the defect, so the description tripped it. Same
    # self-match shape as a comment naming a banned glob. Only lines that begin a cp command
    # count, and the direction is read from which variable comes first.
    local cps back=0 line
    cps="$(command grep -nE '^[[:space:]]*cp ' "$SELF" || true)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in *'$dest'*'$src'*) back=$((back+1)) ;; esac
    done <<< "$cps"
    _eq "the file contains NO copy-back cp statement" "$back" "0"
    # and the floor: the forward copy MUST be there, or the arm above is vacuous
    local fwd=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in *'$src'*'$dest'*) fwd=$((fwd+1)) ;; esac
    done <<< "$cps"
    _eq "  ...and the forward copy IS present"        "$fwd" "1"

    rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) seed "${1:-}"; exit $? ;;
esac
