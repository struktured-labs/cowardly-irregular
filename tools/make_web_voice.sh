#!/usr/bin/env bash
# make_web_voice.sh — the WEB-ONLY voice tier: party voice lines re-encoded smaller for the web pck.
#
# WHY: struktured chose a 725-line party voice corpus (145 per job, 2026-09-25). At the masters'
# ~35 KB/clip that is ~25 MB of pck against 13.45 MB of headroom under deploy_web.sh's PCK_LIMIT
# (the .490 web pck measured 185,554,768 bytes). Desktop keeps the masters; only the web STAGE
# gets this tier (make_web_stage.sh). The encoding itself is @cowir-sfx's decision — this tool
# takes it as arguments and never picks one. deploy_web.sh's WEB_VOICE_KBPS=0 means "no tier":
# voice ships at master quality, exactly as before this tool existed.
#
# THE CORPUS: every assets/audio/sfx/voice_*.ogg EXCEPT voice_blip_* — those are 6 synthesised
# UI typing blips (44.1 kHz STEREO, 45-90 ms, loaded by path from CutsceneDialogue.gd), not
# speech, and not the growth problem. Everything else is a party line keyed voice_<job>_<trigger>.
#
# Measured on the 211 clips of v3.33.490-alpha (all ffmpeg libvorbis, mono):
#     24 kHz 32 kbps  3.49 MB   0/211 dts warnings
#     24 kHz 40 kbps  4.22 MB   0/211
#     32 kHz 48 kbps  4.62 MB  13/211   <- "non monotonically increasing dts" on decode
#     48 kHz 48 kbps  4.55 MB  11/211
#     masters         7.23 MB   0/211
# The warning is a bad granule position in the ENCODED stream (the masters have none), and the
# voice bubble's hold time is the clip's get_length() (BattleSpeechBubble.gd), so this tool
# refuses any output that does not decode with an EMPTY stderr — see the gate below.
#
# Usage: tools/make_web_voice.sh <kbps> <sample_rate_hz>
#   Prints the tier dir on its LAST stdout line, so a caller never re-derives the path.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

KBPS="${1:-}"
AR="${2:-}"
# A flag must not become a tier name (make_web_audio.sh learned this at EC=234): validate first.
case "$KBPS" in ''|*[!0-9]*) echo "[web-voice] REFUSED: kbps must be a plain integer, got '${KBPS}'." >&2; exit 2 ;; esac
case "$AR" in ''|*[!0-9]*) echo "[web-voice] REFUSED: sample rate must be a plain integer in Hz, got '${AR}'." >&2; exit 2 ;; esac
if [ "$KBPS" -lt 16 ] || [ "$KBPS" -gt 128 ]; then
    echo "[web-voice] REFUSED: ${KBPS} kbps is outside 16-128 for speech — a typo, not a tier." >&2; exit 2
fi
case "$AR" in 16000|22050|24000|32000|44100|48000) ;; *)
    echo "[web-voice] REFUSED: ${AR} Hz is not one of 16000 22050 24000 32000 44100 48000." >&2; exit 2 ;;
esac

SRC_DIR="assets/audio/sfx"
# Scoped by BOTH parameters: two encodings must never share a directory (make_web_audio.sh:53-61).
OUT_DIR="tmp/web_audio/voice_${KBPS}k_${AR}"
command -v ffmpeg >/dev/null || { echo "[web-voice] ffmpeg not found" >&2; exit 2; }
[ -d "$SRC_DIR" ] || { echo "[web-voice] no $SRC_DIR — wrong cwd?" >&2; exit 2; }

# Sorted: this box's find (bfs) returns a different order every run.
mapfile -t SRCS < <(find "$SRC_DIR" -maxdepth 1 -name 'voice_*.ogg' ! -name 'voice_blip_*' | sort)
TOTAL=${#SRCS[@]}
[ "$TOTAL" -gt 0 ] || { echo "[web-voice] found 0 voice masters — refusing to build an empty tier" >&2; exit 2; }

# A fresh directory every run: a restore that does not clear first keeps strays, and the
# stage's count check would then compare against a tier that is not this one.
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
echo "[web-voice] ${TOTAL} voice masters -> ${KBPS} kbps mono @ ${AR} Hz, staging in ${OUT_DIR}"

# ── CACHE, keyed on the INPUT AND THE ENCODE ─────────────────────────────────────────────────
# A cache key certifies what it hashes and nothing else. The music key omits the ffmpeg
# arguments (only the bitrate is in the dir name); this one carries them, so changing the
# encode can never be served an old tier. Prefix `voice_` keeps these out of the music prune
# glob `${BITRATE}k_*`, which would otherwise evict music tiers.
_ENCODE_SIG="libvorbis b=${KBPS}k ac=1 ar=${AR} map_metadata=-1"
_CACHE_ROOT="${WEB_AUDIO_CACHE:-$HOME/.cache/cowir_web_audio}"
_key="$( { echo "$_ENCODE_SIG"; printf '%s\n' "${SRCS[@]}" \
        | while read -r _f; do printf '%s %s\n' "$(basename "$_f")" "$(md5sum < "$_f" | cut -d' ' -f1)"; done; } \
        | md5sum | cut -d' ' -f1)"
_CACHE_DIR="${_CACHE_ROOT}/voice_${KBPS}k_${AR}_${_key}"
if [ -d "$_CACHE_DIR" ] && [ "$(find "$_CACHE_DIR" -name '*.ogg' | wc -l)" -eq "$TOTAL" ]; then
    cp -a "$_CACHE_DIR/." "$OUT_DIR/"
    echo "[web-voice] restored ${TOTAL} clip(s) from the cache — no re-encode"
else
    echo "[web-voice] cache miss (voice_${KBPS}k_${AR}_${_key:0:8}) — encoding"
    for src in "${SRCS[@]}"; do
        ffmpeg -nostdin -v error -y -i "$src" -c:a libvorbis -b:a "${KBPS}k" -ac 1 -ar "$AR" \
               -map_metadata -1 "$OUT_DIR/$(basename "$src")"
    done
fi

src_bytes=0; out_bytes=0
for src in "${SRCS[@]}"; do
    out="$OUT_DIR/$(basename "$src")"
    [ -s "$out" ] || { echo "[web-voice] MISSING or EMPTY output for $src — aborting" >&2; exit 3; }
    src_bytes=$(( src_bytes + $(stat -c%s "$src") ))
    out_bytes=$(( out_bytes + $(stat -c%s "$out") ))
done
OUT_N=$(find "$OUT_DIR" -name '*.ogg' | wc -l)
[ "$OUT_N" -eq "$TOTAL" ] || { echo "[web-voice] tier holds ${OUT_N} clips, masters ${TOTAL} — aborting" >&2; exit 3; }

# ── GATE 1: DECODED LENGTH MATCHES THE MASTER (the music tier's gate, reused) ─────────────────
# A truncated ogg decodes with exit 0 and no stderr; this compares full decoded length against
# the master's, and it runs on the cache-restore path too, above the cache write.
"$(dirname "$0")/check_audio_decodes.sh" "$OUT_DIR" "$SRC_DIR" || {
    echo "[web-voice] tier failed the decode gate — NOT caching, NOT publishing" >&2
    exit 4
}

# ── GATE 2: EVERY CLIP DECODES WITH AN EMPTY STDERR ──────────────────────────────────────────
# Stricter than gate 1, and specific to what this encode was measured to do: 11-13 of 211 clips
# at 32k/48 kbps and 48k/48 kbps carry non-monotonic granule positions that decode "fine" (exit 0,
# length within tolerance) while ffmpeg complains. The masters and both 24 kHz settings have zero.
# A clean master that encodes dirty is this tool's defect, so it refuses the tier rather than ship it.
_dirty=0
for out in "$OUT_DIR"/*.ogg; do
    _err="$(ffmpeg -nostdin -v error -i "$out" -f null - 2>&1 || echo "EXIT $?")"
    if [ -n "$_err" ]; then
        _dirty=$(( _dirty + 1 ))
        if [ "$_dirty" -le 5 ]; then
            echo "[web-voice]   dirty decode: $(basename "$out") :: ${_err:0:140}" >&2
        fi
    fi
done
if [ "$_dirty" -gt 0 ]; then
    echo "[web-voice] ⛔ BLOCKED: ${_dirty}/${TOTAL} clip(s) decode with warnings at ${KBPS}k/${AR} Hz." >&2
    echo "[web-voice]   The masters decode clean, so the ENCODE introduced it. Pick another setting" >&2
    echo "[web-voice]   (both 24 kHz settings measured 0/211) — NOT caching, NOT publishing." >&2
    exit 4
fi

if [ ! -d "$_CACHE_DIR" ]; then
    mkdir -p "$_CACHE_DIR" && cp -a "$OUT_DIR/." "$_CACHE_DIR/" \
        && echo "[web-voice] cached this tier for the next build" \
        || echo "[web-voice] note: could not write the cache — this run is unaffected" >&2
    # Bound the disk: three newest VOICE tiers, never touching music's `<N>k_*` entries.
    ls -1dt "${_CACHE_ROOT}/voice_"* 2>/dev/null | tail -n +4 | while read -r _old; do
        rm -rf "$_old" && echo "[web-voice] pruned an older cached voice tier: $(basename "$_old")"
    done
fi

python3 - "$src_bytes" "$out_bytes" "$TOTAL" <<'EOF'
import sys
s, o, n = (int(x) for x in sys.argv[1:4])
print(f"[web-voice] {n} clips: masters {s/1e6:.2f} MB -> tier {o/1e6:.2f} MB "
      f"({o/n/1e3:.1f} KB/clip, saves {(s-o)/1e6:.2f} MB)")
EOF
echo "$OUT_DIR"
