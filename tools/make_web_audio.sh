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
# BITRATE-SCOPED, and that is load-bearing. The idempotence check below compares
# mtimes and has no notion of bitrate, so a shared output directory makes
# `make_web_audio.sh 64` silently REUSE files transcoded at 48 and then report
# them as 64 kbps. Measured: a 64k run printed "reused 154 · 91.5 MiB at 64 kbps"
# for a tree that was entirely 48k — the script asserting a bitrate it did not
# produce. That is the label-implies-a-conclusion-its-predicate-doesn't-support
# class, in my own tool, and it fed a wrong number into a shipping decision.
# Scoping the path means two bitrates cannot share a directory, so the mtime
# check stays cheap and can no longer lie.
OUT_DIR="tmp/web_audio/music_${BITRATE}k"
PCK_LIMIT_MIB=189   # 199,000,000 bytes; see deploy_web.sh PCK_LIMIT
# Chromium refuses to CACHE a single resource above ~160 MiB, so a pck under the itch
# limit can still be re-downloaded in full on every visit (cowir-deploy, 2026-09-12).
# That is the binding constraint today: the shipped pck is 166.89 MiB, inside 189 and
# outside 160. A run that reports only the itch limit says FITS about the wrong question.
CACHE_LIMIT_MIB=160

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
python3 - "$src_bytes" "$out_bytes" "$TOTAL" "$BITRATE" "$PCK_LIMIT_MIB" "$CACHE_LIMIT_MIB" <<'PY'
import sys, os, glob, re
src, out, n, br, limit, cache = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], int(sys.argv[5]), int(sys.argv[6])
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
    # ⛔ WAS: masters of the tracks the WEB preset's exclude_filter keeps. Two errors,
    # partly cancelling: the published path is WEB_STAGE=1, whose make_web_stage.sh DROPS
    # every music exclusion (so all 161 ship, not 107), and the pck holds TIER bytes, not
    # master bytes. Measured 2026-09-12: derived 69.95 MiB where the truth is 71.77 — every
    # projection 1.82 MiB optimistic. Same class as reading export_presets.cfg and reporting
    # it as the shipped build, which cost this lane two retractions the same day.
    #
    # The reference pck was built at make_web_stage.sh's default bitrate (struktured's
    # ruling). Derive from THAT tier, and refuse rather than guess if it is not on disk.
    allm = set(glob.glob(d + "*.ogg"))
    shipped_br = 48
    try:
        with open("tools/make_web_stage.sh") as fh:
            m = re.search(r'BITRATE="\$\{1:-(\d+)\}"', fh.read())
            if m:
                shipped_br = int(m.group(1))
    except OSError:
        pass
    shipped_tier = glob.glob("tmp/web_audio/music_%dk/*.ogg" % shipped_br)
    if len(shipped_tier) != len(allm):
        print(f"[web-audio] the reference pck was built at {shipped_br}k and that tier is not on")
        print(f"[web-audio] disk ({len(shipped_tier)} of {len(allm)} files) — SKIPPING the projection")
        print(f"[web-audio] rather than deriving the non-music payload from master bytes.")
        print(f"[web-audio] Run: tools/make_web_audio.sh {shipped_br}")
        raise SystemExit(0)
    in_pck = sum(os.path.getsize(f) for f in shipped_tier)
    other = os.path.getsize(PCK) - in_pck
    if other <= 0:
        print("[web-audio] derived non-music payload came out <= 0 — the reference pck and")
        print("[web-audio] the exclusion list disagree. Not projecting from a broken figure.")
    else:
        tot = (out + other) / mib
        # Disclose the reference's AGE. The script already refuses to invent this constant;
        # it should also say how old the one it derived is, because the absolute projection is
        # only as fresh as that pck while the bitrate DELTAS are unaffected (same term).
        import time
        age_d = (time.time() - os.path.getmtime(PCK)) / 86400.0
        print(f"[web-audio] non-music payload {other/mib:.1f} MiB  (DERIVED from a pck built "
              f"{age_d:.0f}d ago, {os.path.getsize(PCK)/mib:.2f} MiB)")
        if age_d > 2:
            print(f"[web-audio]   ^ that reference is {age_d:.0f} days old, so the ABSOLUTE figures "
                  f"below lag the live store; the bitrate-to-bitrate deltas do not.")
        print(f"[web-audio] projected pck ~{tot:.2f} MiB vs {limit} MiB itch limit "
              f"({'FITS' if tot < limit else 'OVER — drop the bitrate'})")
        # The cache line binds before the itch limit does, and a player feels it every visit.
        print(f"[web-audio]               vs {cache} MiB browser cache line "
              f"({'CACHEABLE' if tot < cache else 'RE-DOWNLOADED EVERY VISIT'}"
              f", {abs(cache - tot):.2f} MiB {'spare' if tot < cache else 'over'})")
        # Forward-looking: cowir-music has ~48 unthemed regular monsters queued.
        # At the master bitrate that is ~69 MiB more source, which scales by the
        # ratio this run just measured rather than by an assumed one.
        future_src = src + 69 * mib
        future_out = future_src * (out / src)
        ftot = (future_out + other) / mib
        # ⛔ THE REMEDY IS DERIVED, NOT FROZEN. This read "OVER at this bitrate — 48k
        # needed" — a hardcoded string, so a run AT 48k was told to use 48k. Measured on
        # v3.33.301-alpha's archived log, which is exactly that case:
        #
        #   with the ~48 queued monster themes: ~201 MiB (OVER at this bitrate — 48k needed)
        #
        # The one line that warns this lane the web build is heading over the limit handed
        # back a no-op. It is the same defect as the hardcoded 68 MiB payload the comment
        # above describes — a constant driving a verdict — and it survived that fix because
        # it sits in the REMEDY rather than in the arithmetic.
        def _remedy(cur_br, music_mib, other_mib, cap):
            budget = cap - other_mib
            if budget <= 0:
                return f"OVER — the non-music payload alone is {other_mib:.0f} MiB"
            need = int(cur_br) * budget / music_mib
            if need < 24:
                return (f"OVER at {cur_br}k — even ~{need:.0f}k would not fit; "
                        f"the CONTENT has to shrink, not the bitrate")
            return f"OVER at {cur_br}k — needs ~{need:.0f}k, or fewer tracks"
        print(f"[web-audio] with the ~48 queued monster themes: ~{ftot:.0f} MiB "
              f"({'FITS' if ftot < limit else _remedy(br, future_out/mib, other/mib, limit)})")
        print("[web-audio] projections only. deploy_web.sh gate 3 measures the real pck.")
PY
