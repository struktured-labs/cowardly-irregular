#!/usr/bin/env bash
# smoke_redirect_proof.sh — prove the render smoke's user:// was the SANDBOX, positively.
#
# WHY (cowir-main 20906, 2026-11-01): deploy_web.sh proved its smoke sandbox by signing HIS REAL
# profile before the boot and verifying it after. That makes his live profile the instrument, so
# his own autosave inside the window false-REDs the publish (.487) — and the fix was a HOLD while
# his game is up. On .758 that left the store split for hours: linux/windows shipped, web held.
# This proves the redirect from the smoke's side instead, so web can publish while he plays.
# deploy_web.sh still runs the old --sig/--verify as an EXTRA check whenever his game is not up.
#
# Three arms; each must be GREEN or the smoke is treated as having touched his profile:
#   --check-value <sandbox> <real_data_home>
#       The value handed to XDG_DATA_HOME is non-empty, an existing directory, its own realpath,
#       and NOT his data home or inside it. ⛔ EMPTY is the dangerous value (cowir-adhoc 20907, and
#       this lane's memory): Godot treats "" as unset and silently falls back to ~/.local/share,
#       so a "variable is present" check passes on exactly the value that writes his profile.
#   --watch <pid> <outfile>   (run in the background beside the smoke)
#       Samples every process under <pid> whose cmdline contains $SRP_MATCH (default
#       --render-smoke) and records what XDG_DATA_HOME ITS environ actually carried: the value,
#       "<empty>", or "<unset>". The env passes through env/bwrap/xvfb-run/timeout; this reads it
#       at the far end, from the process that writes user://.
#   --verdict <sandbox> <seen_file> <profile_rel> <real_data_home> <since_marker>
#       (a) every recorded value equals realpath(<sandbox>) and at least one was recorded;
#       (b) LANDED: the engine's own side effect, a logs/godot*.log newer than <since_marker>,
#           exists under <sandbox>/<profile_rel>;
#       (c) NOT IN HIS: nothing under <real_data_home>/<profile_rel>/smoke/ and no rotated
#           logs/godot2*.log there is newer than <since_marker>. A rotated log appears only when an
#           engine BOOTS on that profile; his running game appends to godot.log, which is not checked.
#
#   --selftest   a fake smoke (bash) under a FAKE HOME: never his profile.
#
# SRP_VAR (default XDG_DATA_HOME) names the variable that relocates user:// for THIS smoke, so the
# desktop battle smoke can be proven the same way (deploy_desktop.sh gate 3b): XDG_DATA_HOME for the
# linux build, WINEPREFIX for the windows one, whose user:// lives inside the prefix. SRP_REAL_REL
# (default: the <profile_rel> argument) is the profile path under <real_data_home> that arm (c)
# inspects, for a smoke whose sandbox layout differs from his (wine's drive_c/users/...).
# Exit: 0 green · 1 red (reasons on stderr) · 2 usage.
set -u
# The match carries no leading "--": test_the_smoke_cannot_see_his_pad_regression keys REAL game launches on
# the flag "--render-smoke" in tools/*.sh, and this line launches nothing. A substring of the real argument.
SRP_MATCH="${SRP_MATCH:-render-smoke}"
SRP_VAR="${SRP_VAR:-XDG_DATA_HOME}"
_red() { echo "[redirect] RED: $*" >&2; }

_matches() { # pids under $1 (inclusive) whose args contain $SRP_MATCH: ONE ps per sample
    # (a /proc walk forking awk per pid took longer than a short smoke lives: the selftest saw nothing)
    ps -eo pid=,ppid=,args= 2>/dev/null | awk -v root="$1" -v m="$SRP_MATCH" '
        { pid[NR]=$1; pp[NR]=$2; $1=""; $2=""; a[NR]=$0; n=NR }
        END { inset[root]=1; ch=1
              for (it=0; ch && it<=n; it++) { ch=0; for (i=1;i<=n;i++) if (!(pid[i] in inset) && (pp[i] in inset)) { inset[pid[i]]=1; ch=1 } }
              for (i=1;i<=n;i++) if ((pid[i] in inset) && index(a[i], m)) print pid[i] }'
}

check_value() {
    local v="$1" real="$2" rv rr
    [ -n "$v" ] || { _red "$SRP_VAR value is EMPTY (Godot/wine fall back to his home)"; return 1; }
    [ -d "$v" ] || { _red "$SRP_VAR '$v' is not an existing directory"; return 1; }
    rv="$(realpath "$v")"; rr="$(realpath -m "$real")"
    [ "$rv" = "$v" ] || { _red "$SRP_VAR '$v' is not its own realpath ('$rv')"; return 1; }
    case "$rv/" in "$rr/"*) _red "$SRP_VAR '$v' is his data home or inside it ('$rr')"; return 1 ;; esac
    return 0
}

watch() {
    # BOUNDED (check_polling_bounded): a counter of 0.2 s ticks, SRP_WATCH_MAX seconds (default 600 = 2x the
    # smoke's own `timeout 300`). Hitting it stops the sampling only; the verdict still judges what was seen.
    local pid="$1" out="$2" q env v i=0 max=$(( ${SRP_WATCH_MAX:-600} * 5 ))
    : > "$out"
    while [ "$i" -lt "$max" ] && kill -0 "$pid" 2>/dev/null; do
        for q in $(_matches "$pid"); do
            env="$(tr '\0' '\n' 2>/dev/null < "/proc/$q/environ")" || continue
            [ -n "$env" ] || continue
            if printf '%s\n' "$env" | command grep -q "^$SRP_VAR="; then
                v="$(printf '%s\n' "$env" | sed -n "s/^$SRP_VAR=//p" | head -1)"; [ -n "$v" ] || v="<empty>"
            else v="<unset>"; fi
            command grep -qxF -- "$q $v" "$out" || echo "$q $v" >> "$out"
        done
        sleep 0.2
        i=$((i + 1))
    done
}

verdict() {
    local sb="$1" seen="$2" rel="$3" real="$4" since="$5" rs n bad=0 v
    rs="$(realpath "$sb")"
    n="$(command grep -c . "$seen" 2>/dev/null || true)"
    if [ "${n:-0}" -eq 0 ]; then _red "no smoke process was ever seen (match '$SRP_MATCH'): the environ arm saw nothing"; bad=1
    else
        while read -r _ v; do
            [ "$v" = "$rs" ] || { _red "the smoke ran with $SRP_VAR='$v', not the sandbox '$rs'"; bad=1; }
        done < "$seen"
    fi
    if [ -z "$(find "$sb/$rel/logs" -maxdepth 1 -name 'godot*.log' -newer "$since" 2>/dev/null | head -1)" ]; then
        _red "the engine left no fresh log under the sandbox ($sb/$rel/logs): user:// did not resolve there"; bad=1
    fi
    local leak rr="${SRP_REAL_REL:-$rel}"
    leak="$( { find "$real/$rr/smoke" -type f -newer "$since" 2>/dev/null; \
               find "$real/$rr/logs" -maxdepth 1 -name 'godot2*.log' -newer "$since" 2>/dev/null; } | head -3)"
    [ -z "$leak" ] || { _red "fresh files in the REAL profile: $(printf '%s' "$leak" | tr '\n' ' ')"; bad=1; }
    [ "$bad" = 0 ] && echo "[redirect] GREEN: the smoke ran in $rs (seen in $n process environ(s)) and left nothing new in the real profile"
    return "$bad"
}

selftest() {
    local T pass=0 fail=0 REL="godot/app_userdata/Cowardly Irregular"
    mkdir -p "$PWD/tmp"; T="$(mktemp -d "$PWD/tmp/srp_selftest.XXXXXX")"; trap 'rm -rf "$T"' RETURN
    # The fake smoke mimics Godot's resolution: "" and unset both fall back to $HOME/.local/share.
    # Its flag is --fake-render-smoke: a bash script, not the game, so the pad-jail guard must not read it as a
    # windowed game launch; SRP_MATCH's "render-smoke" still matches it.
    cat > "$T/fake_smoke.sh" <<'EOF'
d="${XDG_DATA_HOME:-}"; [ -n "$d" ] || d="$HOME/.local/share"
u="$d/godot/app_userdata/Cowardly Irregular"; mkdir -p "$u/smoke" "$u/logs"
sleep 0.8; echo shot > "$u/smoke/shot.png"; echo boot > "$u/logs/godot2026-11-01T00.00.00.log"; echo log > "$u/logs/godot.log"
EOF
    _arm() { # label want_ec env_mode(good|unset|empty|other)
        local label="$1" want="$2" mode="$3" H="$T/$1/home" SB="$T/$1/sandbox" OT="$T/$1/other" pid ec
        mkdir -p "$H/.local/share" "$SB" "$OT"; touch "$T/$1/since"; sleep 1.1
        case "$mode" in
            good)  env HOME="$H" XDG_DATA_HOME="$SB" bash "$T/fake_smoke.sh" --fake-render-smoke & ;;
            unset) env -u XDG_DATA_HOME HOME="$H" bash "$T/fake_smoke.sh" --fake-render-smoke & ;;
            empty) env HOME="$H" XDG_DATA_HOME= bash "$T/fake_smoke.sh" --fake-render-smoke & ;;
            other) env HOME="$H" XDG_DATA_HOME="$OT" bash "$T/fake_smoke.sh" --fake-render-smoke & ;;
        esac
        pid=$!; watch "$pid" "$T/$1/seen" & local wp=$!; wait "$pid"; wait "$wp"
        ec=0; verdict "$SB" "$T/$1/seen" "$REL" "$H/.local/share" "$T/$1/since" > "$T/$1/out" 2>&1 || ec=$?
        if [ "$ec" = "$want" ]; then pass=$((pass+1)); printf '  ok    %-44s exit %s  (seen: %s)\n' "$label" "$ec" "$(cut -d' ' -f2- "$T/$1/seen" | tr '\n' ' ')"
        else fail=$((fail+1)); printf '  FAIL  %-44s exit %s want %s\n' "$label" "$ec" "$want"; sed 's/^/        /' "$T/$1/out"; fi
    }
    _arm "good_sandbox_is_GREEN" 0 good
    _arm "unset_XDG_is_RED" 1 unset
    _arm "EMPTY_XDG_is_RED" 1 empty
    _arm "other_dir_is_RED" 1 other
    # NOT BLIND: each red arm must have been red for the ENVIRON reason too, with the exact value seen.
    # (The first version saw no process at all and its red arms still passed on the other arms.)
    _seen() { if cut -d' ' -f2- "$T/$1/seen" | command grep -qxF -- "$2"; then pass=$((pass+1)); printf '  ok    %-44s saw %s\n' "$1: environ arm" "$2"
              else fail=$((fail+1)); printf '  FAIL  %-44s saw [%s], want %s\n' "$1: environ arm" "$(cut -d' ' -f2- "$T/$1/seen" | tr '\n' ' ')" "$2"; fi; }
    _seen good_sandbox_is_GREEN "$(realpath "$T/good_sandbox_is_GREEN/sandbox")"
    _seen unset_XDG_is_RED "<unset>"
    _seen EMPTY_XDG_is_RED "<empty>"
    _seen other_dir_is_RED "$T/other_dir_is_RED/other"
    # the RED arms must also have planted into the FAKE profile (the leak arm fired, not only environ)
    for a in unset_XDG_is_RED EMPTY_XDG_is_RED; do
        if command grep -q 'fresh files in the REAL profile' "$T/$a/out"; then pass=$((pass+1)); printf '  ok    %-44s leak arm fired\n' "$a: fake profile written"
        else fail=$((fail+1)); printf '  FAIL  %-44s leak arm did not fire\n' "$a: fake profile written"; fi
    done
    # WINE (SRP_VAR=WINEPREFIX): the windows battle smoke's user:// lives inside the prefix, and wine with no
    # prefix falls back to $HOME/.wine. Flag --fake-battle-smoke so SRP_MATCH "battle-smoke" matches it.
    # "linux" makes the fake ALSO boot a linux engine on the fake HOME's profile: only SRP_REAL_REL can see that.
    cat > "$T/fake_wine.sh" <<'EOF2'
d="${WINEPREFIX:-}"; [ -n "$d" ] || d="$HOME/.wine"
u="$d/drive_c/users/u/AppData/Roaming/Godot/app_userdata/Cowardly Irregular"; mkdir -p "$u/logs"
sleep 0.8; echo boot > "$u/logs/godot2026-11-01T00.00.00.log"; echo log > "$u/logs/godot.log"
if [ "${1:-}" = linux ]; then l="$HOME/.local/share/godot/app_userdata/Cowardly Irregular/logs"; mkdir -p "$l"; echo boot > "$l/godot2026-11-01T00.00.00.log"; fi
EOF2
    local WREL="drive_c/users/u/AppData/Roaming/Godot/app_userdata/Cowardly Irregular"
    _warm() { # label want_ec mode(good|unset|linux) real_rel(""=unset)
        local label="$1" want="$2" mode="$3" H="$T/$1/home" SB="$T/$1/sandbox" pid ec wp
        mkdir -p "$H/.local/share" "$SB"; touch "$T/$1/since"; sleep 1.1
        case "$mode" in
            good)  env HOME="$H" WINEPREFIX="$SB" bash "$T/fake_wine.sh" x --fake-battle-smoke & ;;
            linux) env HOME="$H" WINEPREFIX="$SB" bash "$T/fake_wine.sh" linux --fake-battle-smoke & ;;
            unset) env -u WINEPREFIX HOME="$H" bash "$T/fake_wine.sh" x --fake-battle-smoke & ;;
        esac
        pid=$!; SRP_VAR=WINEPREFIX SRP_MATCH=battle-smoke watch "$pid" "$T/$1/seen" & wp=$!; wait "$pid"; wait "$wp"
        ec=0; SRP_VAR=WINEPREFIX SRP_REAL_REL="$4" verdict "$SB" "$T/$1/seen" "$WREL" "$H/.local/share" "$T/$1/since" > "$T/$1/out" 2>&1 || ec=$?
        if [ "$ec" = "$want" ]; then pass=$((pass+1)); printf '  ok    %-44s exit %s  (seen: %s)\n' "$label" "$ec" "$(cut -d' ' -f2- "$T/$1/seen" | tr '\n' ' ')"
        else fail=$((fail+1)); printf '  FAIL  %-44s exit %s want %s\n' "$label" "$ec" "$want"; sed 's/^/        /' "$T/$1/out"; fi
    }
    _warm "wine: prefix sandbox is GREEN" 0 good "$REL"
    _warm "wine: unset WINEPREFIX is RED" 1 unset "$REL"
    _warm "wine: linux boot on his profile is RED" 1 linux "$REL"
    # CONTROL for SRP_REAL_REL: the same leak with it unset looks under his profile at the WINE path and is blind.
    _warm "wine: same leak, no SRP_REAL_REL, is BLIND" 0 linux ""
    if command grep -q 'fresh files in the REAL profile' "$T/wine: linux boot on his profile is RED/out"; then pass=$((pass+1)); printf '  ok    %-44s leak arm fired\n' "wine linux boot: SRP_REAL_REL"
    else fail=$((fail+1)); printf '  FAIL  %-44s leak arm did not fire\n' "wine linux boot: SRP_REAL_REL"; fi
    if command grep -q "<unset>" "$T/wine: unset WINEPREFIX is RED/seen"; then pass=$((pass+1)); printf '  ok    %-44s saw <unset>\n' "wine unset: environ arm"
    else fail=$((fail+1)); printf '  FAIL  %-44s did not see <unset>\n' "wine unset: environ arm"; fi
    # value arm, both directions
    local R="$T/vals"; mkdir -p "$R/share/inside" "$R/sb"
    _v() { local ec=0; check_value "$2" "$R/share" 2>/dev/null || ec=$?; [ "$ec" = "$3" ] && { pass=$((pass+1)); printf '  ok    %-44s exit %s\n' "$1" "$ec"; } || { fail=$((fail+1)); printf '  FAIL  %-44s exit %s want %s\n' "$1" "$ec" "$3"; }; }
    _v "value: the sandbox is GREEN" "$R/sb" 0
    _v "value: EMPTY is RED" "" 1
    _v "value: inside his data home is RED" "$R/share/inside" 1
    _v "value: not a realpath is RED" "$R/sb/." 1
    _v "value: missing dir is RED" "$R/nope" 1
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" = 0 ]
}

case "${1:-}" in
    --check-value) [ $# -eq 3 ] || exit 2; check_value "$2" "$3" ;;
    --watch)       [ $# -eq 3 ] || exit 2; watch "$2" "$3" ;;
    --verdict)     [ $# -eq 6 ] || exit 2; verdict "$2" "$3" "$4" "$5" "$6" ;;
    --selftest)    selftest ;;
    *) sed -n '2,32p' "$0" >&2; exit 2 ;;
esac
