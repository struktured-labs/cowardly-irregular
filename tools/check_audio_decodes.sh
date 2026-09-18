#!/usr/bin/env bash
# check_audio_decodes.sh — prove every track in an audio tier actually DECODES,
# by comparing its DECODED length against its master's declared length.
#
# WHY THIS IS NOT "ffmpeg && echo ok" (measured 2026-09-18, cowir-deploy):
#
#     intact.ogg    EC=0   no stderr
#     trunc.ogg     EC=0   no stderr      <- 60% of the bytes, 118.7s of a 187.0s track
#     flip.ogg      EC=0   2 stderr lines
#     empty.ogg     EC=187
#     headonly.ogg  EC=187
#
# A TRUNCATED OGG DECODES CLEANLY. ffmpeg plays what is there and stops, exit 0, silent.
# So an exit-code gate passes the exact defect this file exists to catch — the tier is
# assembled by a transcode loop and then CACHED, and the cache-restore path re-checks
# nothing but the file COUNT. An interrupted encode or a short copy caches once and
# ships forever, and every downstream size gate agrees with it because they all read
# that same cache.
#
# The discriminator is decoded LENGTH against an independent expected value. We decode
# the artifact we doubt and read the container of the master we trust (masters are
# LFS-verified upstream by gate 0c) — never the other way round.
#
# TOLERANCE IS DERIVED FROM THE REAL CORPUS, not picked. Over the 161-track live tier:
#     149/161 match the master EXACTLY;  mean |delta| 0.0018s;  worst |delta| 0.060s
#     delta does NOT scale with duration (0.060s occurs at 5.0s and at 138.3s) — it is
#     encoder frame granularity (1024 samples @ 48kHz = 0.021s), so the bound is ABSOLUTE.
# 0.25s sits 4.2x above the worst legitimate delta and 4.1x below the smallest corruption
# measured (the byte-flip, 1.024s short). Stated blind spot: a loss smaller than 0.25s on
# any one track passes. That is a quarter-second off a tail, not a track that will not play.
set -uo pipefail

TOL_S="${AUDIO_DECODE_TOL_S:-0.25}"
JOBS="${AUDIO_DECODE_JOBS:-8}"

_die() { echo "[audio-decode] $*" >&2; exit 2; }

# Measure ONE track. Prints: <status> <master_sec> <decoded_sec> <name>
# Kept as a function and re-entered via `$0 --one` so xargs can fan it out.
_one() {
    local f="$1" mdir="$2" base m md sr ch b
    base=$(basename "$f")
    m="$mdir/$base"
    [ -f "$m" ] || { echo "NOMASTER 0 0 $base"; return 0; }
    md=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$m" 2>/dev/null)
    sr=$(ffprobe -v error -show_entries stream=sample_rate  -of csv=p=0 "$f" 2>/dev/null | head -1)
    ch=$(ffprobe -v error -show_entries stream=channels     -of csv=p=0 "$f" 2>/dev/null | head -1)
    # An unreadable container cannot be compared; that is a RED, not a skip.
    case "$md" in ''|N/A) echo "BADMASTER 0 0 $base"; return 0 ;; esac
    case "$sr$ch" in '') echo "UNREADABLE 0 0 $base"; return 0 ;; esac
    [ "${sr:-0}" -gt 0 ] 2>/dev/null || { echo "UNREADABLE 0 0 $base"; return 0; }
    [ "${ch:-0}" -gt 0 ] 2>/dev/null || { echo "UNREADABLE 0 0 $base"; return 0; }
    # THE DECODE. s16le to a pipe: 2 bytes per sample per channel.
    b=$(ffmpeg -v error -i "$f" -f s16le - 2>/dev/null | wc -c)
    python3 -c "
import sys
b,sr,ch,md=$b,$sr,$ch,float('$md')
print(f'OK {md:.3f} {b/2/ch/sr:.3f} $base')"
}

if [ "${1:-}" = "--one" ]; then _one "$2" "$3"; exit 0; fi

_run() {
    local tier="$1" mdir="$2" rows rc
    [ -d "$tier" ] || _die "no tier directory: $tier"
    [ -d "$mdir" ] || _die "no master directory: $mdir"
    # Stage inside the repo's own tmp/, never /tmp: the box's rule, and it keeps the
    # row file next to the artifact it describes if a run dies mid-way.
    local _staged="$(cd "$(dirname "$0")/.." && pwd)/tmp"
    mkdir -p "$_staged" || _die "cannot create $_staged"
    rows=$(mktemp "$_staged/audio_decode.XXXXXX") || _die "cannot stage"
    # bfs returns a different order each run and does not sort — sort or the log is incomparable.
    # -n1 and -I{} are mutually exclusive; passing both makes xargs warn on every run.
    local _list="${rows}.list"
    find "$tier" -name '*.ogg' | sort > "$_list"
    xargs -P "$JOBS" -I{} "$0" --one {} "$mdir" < "$_list" > "$rows"
    # A measurement that DIES leaves no row, and a shorter table would otherwise be
    # reported as a smaller success. The expected count is the input list, not the output.
    python3 - "$rows" "$TOL_S" "$tier" "$(command wc -l < "$_list")" <<'PY'
import sys
rows_path, tol, tier, expected = sys.argv[1], float(sys.argv[2]), sys.argv[3], int(sys.argv[4])
rows = [l.split(None, 3) for l in open(rows_path) if l.strip()]
if len(rows) != expected:
    print(f"[audio-decode] FAIL: measured {len(rows)} track(s) but {expected} were found under "
          f"{tier} — {expected-len(rows)} measurement(s) produced no row", file=sys.stderr)
    sys.exit(1)
# VACUITY CONTROL: an empty corpus must never read as a pass. This is the shape that
# printed "0 shell tool(s) scanned" beside a PASS earlier today.
if not rows:
    print(f"[audio-decode] FAIL: 0 tracks found under {tier} — refusing to certify an empty tier", file=sys.stderr)
    sys.exit(1)
bad = []
for st, md, dd, name in rows:
    name = name.strip()
    if st != "OK":
        bad.append((name, st, None)); continue
    delta = float(dd) - float(md)
    if abs(delta) > tol:
        bad.append((name, "SHORT" if delta < 0 else "LONG", delta))
n = len(rows)
if bad:
    print(f"[audio-decode] FAIL: {len(bad)} of {n} track(s) do not decode to their master's length", file=sys.stderr)
    for name, why, delta in bad[:20]:
        d = f"  ({delta:+.3f}s vs master, tolerance {tol}s)" if delta is not None else ""
        print(f"[audio-decode]   {why:<10} {name}{d}", file=sys.stderr)
    if len(bad) > 20:
        print(f"[audio-decode]   ... and {len(bad)-20} more", file=sys.stderr)
    sys.exit(1)
# Rank by magnitude, REPORT with sign: a track that is short must not read as long.
worst = max((((float(d)-float(m)), nm.strip()) for _, m, d, nm in rows), key=lambda t: abs(t[0]))
print(f"[audio-decode] {n} track(s) decoded and matched their master "
      f"(worst {worst[0]:+.3f}s on {worst[1]}, tolerance {tol}s)")
PY
    rc=$?
    rm -f "$rows" "$_list"
    return $rc
}

case "${1:-}" in
    --selftest) exec "$(dirname "$0")/check_audio_decodes_selftest.sh" ;;
    -h|--help|'') echo "usage: $0 <tier_dir> <master_dir>   |   $0 --selftest" >&2; exit 2 ;;
    *) _run "$1" "${2:-assets/audio/music}" ;;
esac
