#!/usr/bin/env bash
# Arms for check_audio_decodes.sh, refereed on REAL ogg masters.
#
# Every arm declares the REASON it expects, not just pass/fail. A gate that reds for the
# wrong cause is not a working gate, and "it failed" is a verdict broader than its code.
#
# Arm 9 is the one that makes the rest mean anything: the SAME truncated file with the
# tolerance widened to 999s must PASS. That proves the length comparison is what reds a
# truncation — not the mutation having broken the file in some other, louder way.
# Arm 10 restores through the same door it mutated through and must go green again.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

TOOL=./tools/check_audio_decodes.sh
SRC=assets/audio/music
SB=tmp/audio_decode_selftest
TRACKS=(job_time_mage_special job_guardian_special stinger_level_up)
VICTIM=job_guardian_special

[ -d "$SRC" ] || { echo "[selftest] no $SRC — wrong cwd?" >&2; exit 2; }
command -v ffmpeg >/dev/null || { echo "[selftest] ffmpeg not found" >&2; exit 2; }

rm -rf "$SB"; mkdir -p "$SB/tier" "$SB/masters" "$SB/empty_tier"
trap 'rm -rf "$SB"' EXIT
for t in "${TRACKS[@]}"; do
    [ -f "$SRC/$t.ogg" ] || { echo "[selftest] missing master $t.ogg" >&2; exit 2; }
    cp "$SRC/$t.ogg" "$SB/masters/" && cp "$SRC/$t.ogg" "$SB/tier/"
done
LONG_SRC="$SRC/menu.ogg"
[ -f "$LONG_SRC" ] || { echo "[selftest] missing $LONG_SRC" >&2; exit 2; }

B="$SB/tier/$VICTIM.ogg"
cp "$B" "$SB/pristine.ogg"
SZ=$(stat -c%s "$SB/pristine.ogg")

pass=0; fail=0
restore() { cp "$SB/pristine.ogg" "$B"; rm -f "$SB/tier/no_master_here.ogg"
            cp "$SRC/job_time_mage_special.ogg" "$SB/tier/"; }

# arm <name> <expected_ec> <expected_reason> <tier> <masters> [env assignment]
arm() {
    local name="$1" want_ec="$2" want="$3" tier="$4" mdir="$5" envset="${6:-}"
    local out ec
    if [ -n "$envset" ]; then out=$(env "$envset" "$TOOL" "$tier" "$mdir" 2>&1); ec=$?
    else                       out=$("$TOOL" "$tier" "$mdir" 2>&1); ec=$?; fi
    if [ "$ec" = "$want_ec" ] && printf '%s' "$out" | command grep -qF "$want"; then
        pass=$(( pass + 1 )); printf '  ok    %-26s EC=%s  %s\n' "$name" "$ec" "$want"
    else
        fail=$(( fail + 1 ))
        printf '  FAIL  %-26s EC=%s (want %s)  expected reason: %s\n' "$name" "$ec" "$want_ec" "$want"
        printf '%s\n' "$out" | sed 's/^/          | /' | head -6
    fi
}

echo "[selftest] check_audio_decodes.sh"

restore
arm intact            0 "3 track(s) decoded and matched" "$SB/tier" "$SB/masters"

head -c $(( SZ * 60 / 100 )) "$SB/pristine.ogg" > "$B"
arm truncated-60pct   1 "SHORT      $VICTIM.ogg"        "$SB/tier" "$SB/masters"

# ARM 9, paired with the one above: same bytes, wider tolerance, must PASS.
arm tolerance-control 0 "decoded and matched"           "$SB/tier" "$SB/masters" AUDIO_DECODE_TOL_S=999

restore
printf '\xff\xff\xff\xff\xff\xff\xff\xff' | dd of="$B" bs=1 seek=$(( SZ / 2 )) conv=notrunc status=none
arm byte-flipped      1 "SHORT      $VICTIM.ogg"        "$SB/tier" "$SB/masters"

restore; : > "$B"
arm empty-file        1 "UNREADABLE $VICTIM.ogg"        "$SB/tier" "$SB/masters"

restore; head -c 4096 "$SB/pristine.ogg" > "$B"
arm header-only       1 "UNREADABLE $VICTIM.ogg"        "$SB/tier" "$SB/masters"

restore; cp "$LONG_SRC" "$SB/tier/no_master_here.ogg"
arm track-with-no-master 1 "NOMASTER   no_master_here.ogg" "$SB/tier" "$SB/masters"

restore; cp "$LONG_SRC" "$SB/tier/job_time_mage_special.ogg"
arm decodes-too-long  1 "LONG       job_time_mage_special.ogg" "$SB/tier" "$SB/masters"

restore
arm empty-tier        1 "refusing to certify an empty tier" "$SB/empty_tier" "$SB/masters"
arm no-tier-dir       2 "no tier directory"     "$SB/does_not_exist" "$SB/masters"
arm no-master-dir     2 "no master directory"   "$SB/tier"           "$SB/nope"

# ARM 10: the mutated file is back; the gate must be green again, or every red above
# might just mean "the sandbox was broken from arm 2 onward".
restore
arm restored-goes-green 0 "worst +0.000s"       "$SB/tier" "$SB/masters"

echo "[selftest] $(( pass + fail )) arm(s), $fail failed"
[ "$fail" -eq 0 ]
