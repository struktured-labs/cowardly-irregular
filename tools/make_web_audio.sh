#!/usr/bin/env bash
# make_web_audio.sh — generate the WEB audio tier from the desktop masters.
#
# WHY THIS EXISTS
#   assets/audio is 180 MB of a ~250 MB asset pool and music is 173 MB of that.
#   itch.io refuses an HTML5 embed containing any file >= 200 MB, and a phone
#   browser has far less headroom than that cap implies. The web build therefore
#   needs smaller audio than the desktop build.
#
#   THE RULE THIS ENCODES (struktured, 2026-07-29): audio quality is the pressure
#   valve, NEVER visual assets. The artist reviews sprites on the WEB build, so
#   excluding art to fit the pck would hand a collaborator an incomplete review.
#   Music bitrate absorbs the pressure instead.
#
#   Consequence, measured rather than projected: at 48 kbps the whole 154-track
#   library is ~53% of source (~92 MB) — SMALLER than the ~98 MB web ships today
#   with 75 MB of the library excluded by export_presets. So this replaces
#   exclusion with transcoding and web ends up with MORE music, not less.
#
# WHAT IT DOES NOT DO
#   It never writes into assets/. The masters stay 96 kbps for desktop. Output is
#   a staging tree the web export reads instead; assets/ is untouched by design,
#   so an interrupted run cannot leave lo-fi files where the masters belong.
#
# MEASURED DEAD END, so nobody repeats it: downsampling to 32 kHz made files
#   BIGGER at the same bitrate (1.30 MB vs 1.12 MB on a real track). libvorbis is
#   already choosing its own spectral cutoff. Bitrate is the only lever; leave the
#   sample rate alone.
#
# Usage: tools/make_web_audio.sh [bitrate_kbps]      (default 64)
#   64k is the safe default for struktured's ear. 48k is the aggressive option
#   and is what the size arithmetic above assumes.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

BITRATE="${1:-64}"
SRC_DIR="assets/audio/music"
OUT_DIR="tmp/web_audio/music"
PCK_LIMIT_MIB=189   # 199,000,000 bytes; see deploy_web.sh PCK_LIMIT

command -v ffmpeg >/dev/null || { echo "[web-audio] ffmpeg not found" >&2; exit 2; }
[ -d "$SRC_DIR" ] || { echo "[web-audio] no $SRC_DIR — wrong cwd?" >&2; exit 2; }

mkdir -p "$OUT_DIR"

# Enumerate from the filesystem, sorted, so the list is deterministic.
# bfs (this box's `find`) returns a DIFFERENT ORDER each run and its output is
# not sorted, so a bare `find` here would make every log incomparable.
mapfile -t SRCS < <(find "$SRC_DIR" -name '*.ogg' | sort)
TOTAL=${#SRCS[@]}
[ "$TOTAL" -gt 0 ] || { echo "[web-audio] found 0 source tracks — refusing to report a size" >&2; exit 2; }

echo "[web-audio] ${TOTAL} masters -> ${BITRATE} kbps mono, staging in ${OUT_DIR}"

src_bytes=0; out_bytes=0; transcoded=0; reused=0
for src in "${SRCS[@]}"; do
    out="$OUT_DIR/$(basename "$src")"
    sb=$(stat -c%s "$src")
    src_bytes=$(( src_bytes + sb ))

    # Skip if the output is newer than its source AND non-empty. Cheap
    # idempotence so a re-run after adding 13 tracks costs 13 transcodes.
    if [ -s "$out" ] && [ "$out" -nt "$src" ]; then
        reused=$(( reused + 1 ))
    else
        # -map_metadata -1: strip tags. They are a rounding error per file but
        # they are also pure waste in a build nobody reads metadata from.
        ffmpeg -v error -y -i "$src" -c:a libvorbis -b:a "${BITRATE}k" -ac 1 \
               -map_metadata -1 "$out"
        transcoded=$(( transcoded + 1 ))
    fi

    ob=$(stat -c%s "$out")
    # A zero-byte output is a silent failure that would look like a size win.
    [ "$ob" -gt 0 ] || { echo "[web-audio] EMPTY output for $src — aborting" >&2; exit 3; }
    out_bytes=$(( out_bytes + ob ))
done

echo "[web-audio] transcoded ${transcoded}, reused ${reused}"
python3 - "$src_bytes" "$out_bytes" "$TOTAL" "$BITRATE" "$PCK_LIMIT_MIB" <<'PY'
import sys, os, glob
src, out, n, br, limit = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], int(sys.argv[5])
mib = 1024 * 1024
print(f"[web-audio] masters   {src/mib:7.1f} MiB  ({n} tracks)")
print(f"[web-audio] web tier  {out/mib:7.1f} MiB  at {br} kbps  -> {out/src*100:.0f}% of source")
print(f"[web-audio] saving    {(src-out)/mib:7.1f} MiB")

# The non-music web payload is DERIVED from the last shipped pck, never guessed.
# An earlier version of this script hardcoded 68 MiB and reported OVER for a
# bitrate that fits with 13 MiB to spare — a made-up constant driving a verdict,
# which is the same coincidental-magnitude trap as a test floor pinned to
# whatever number happened to be true of its author's default path.
#
#   non-music = (shipped pck) - (music currently INSIDE that pck)
# and "currently inside" is itself derived from export_presets' exclude_filter
# rather than assumed, so it stays correct as the exclusion list changes.
PCK = os.path.expanduser("~/projects/cowir-main/builds/web/index.pck")
EXCLUDED = ["*industrial*", "*digital*", "*abstract*",
            "cutscene_w4*", "cutscene_w5*", "cutscene_w6*"]
d = "assets/audio/music/"
if not os.path.exists(PCK):
    print("[web-audio] no reference pck on disk — SKIPPING the projection rather than")
    print("[web-audio] inventing a constant. Export once, then re-run for a fit estimate.")
else:
    ex = set()
    for p in EXCLUDED:
        ex.update(f for f in glob.glob(d + p) if f.endswith(".ogg"))
    allm = set(glob.glob(d + "*.ogg"))
    in_pck = sum(os.path.getsize(f) for f in (allm - ex))
    other = os.path.getsize(PCK) - in_pck
    if other <= 0:
        print("[web-audio] derived non-music payload came out <= 0 — the reference pck and")
        print("[web-audio] the exclusion list disagree. Not projecting from a broken figure.")
    else:
        tot = (out + other) / mib
        print(f"[web-audio] non-music payload {other/mib:.1f} MiB  (DERIVED from the shipped pck)")
        print(f"[web-audio] projected pck ~{tot:.0f} MiB vs {limit} MiB limit "
              f"({'FITS' if tot < limit else 'OVER — drop the bitrate'})")
        # Forward-looking: cowir-music has ~48 unthemed regular monsters queued.
        # At the master bitrate that is ~69 MiB more source, which scales by the
        # ratio this run just measured rather than by an assumed one.
        future_src = src + 69 * mib
        future_out = future_src * (out / src)
        ftot = (future_out + other) / mib
        print(f"[web-audio] with the ~48 queued monster themes: ~{ftot:.0f} MiB "
              f"({'FITS' if ftot < limit else 'OVER at this bitrate — 48k needed'})")
        print("[web-audio] projections only. deploy_web.sh gate 3 measures the real pck.")
PY
