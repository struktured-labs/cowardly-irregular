#!/usr/bin/env bash
# make_web_stage.sh — build a staged project tree whose web export ships EVERY
# music track at a reduced bitrate, and export it.
#
# WHAT THIS SOLVES
#   The web build excluded 54 tracks — all of W4-W6's endings — to stay under
#   itch's HTML5 embed cap. struktured ruled (2026-07-30): ship them, compress to
#   fit. Measured outcome at 48 kbps:
#       before  156,329,808 B   98 tracks @96k
#       after   156,010,192 B  154 tracks @48k     MORE content, slightly SMALLER
#   154 tracks at 48k is less than 98 at 96k was, so the endings are free.
#
# WHY A STAGED COPY AND NOT A SWAP
#   The export must read compressed audio while assets/ keeps the 96k masters for
#   desktop. The fast way is to swap the files, export, and restore. This does
#   NOT do that, deliberately: a deploy killed mid-run is the NORMAL case here (a
#   gate crossing a harness timeout dies by SIGTERM — that is how the export-dir
#   restore was skipped and orphaned four snapshots in one hour), and a swap that
#   fails to restore leaves lo-fi audio where the irreplaceable masters belong.
#   A copy has no restore step to skip. Killed at any instant, assets/ is
#   byte-identical. It costs ~280 MB of disk and one slow first import.
#
#   Hardlinks were the obvious optimisation and are WRONG here: Godot rewrites
#   .import sidecars and the import cache in place, and through a hardlink that
#   corrupts the originals.
#
# Usage:  tools/make_web_stage.sh [bitrate]     default 48 (struktured's ruling)
#         tools/make_web_stage.sh --clean       delete the stage, free the disk
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

STAGE="tmp/web_stage"
[ "${1:-}" = "--clean" ] && { rm -rf "$STAGE"; echo "[stage] removed $STAGE"; exit 0; }

BITRATE="${1:-48}"
TIER="tmp/web_audio/music_${BITRATE}k"
PCK_LIMIT=199000000   # itch refuses an HTML5 embed containing any file >= 200 MB

# ── 1. the compressed tier ──────────────────────────────────────────────────
echo "[stage] 1/4 audio tier @ ${BITRATE} kbps"
./tools/make_web_audio.sh "$BITRATE" >/dev/null
TIER_N=$(find "$TIER" -name '*.ogg' | wc -l)
SRC_N=$(find assets/audio/music -name '*.ogg' | wc -l)
# Every master must have a transcode. A short tier silently ships fewer tracks
# than the masters have, which looks like a size win.
[ "$TIER_N" -eq "$SRC_N" ] || {
    echo "[stage] BLOCKED: tier has ${TIER_N} tracks, masters have ${SRC_N}." >&2
    echo "        Refusing to stage a tier that does not cover the masters." >&2; exit 2; }
echo "[stage]     ${TIER_N}/${SRC_N} tracks"

# ── 2. the copy ─────────────────────────────────────────────────────────────
echo "[stage] 2/4 copying project (real copy — see header on why not hardlinks)"
rm -rf "$STAGE"; mkdir -p "$STAGE"
tar -cf - --exclude=.git --exclude=tmp --exclude=build --exclude=builds --exclude=.godot . \
  | ( cd "$STAGE" && tar -xf - )

# ── 3. swap the audio and drop the music exclusions, IN THE STAGE ONLY ──────
echo "[stage] 3/4 swapping audio + deriving the exclusion list"
rm -f "$STAGE"/assets/audio/music/*.ogg
cp "$TIER"/*.ogg "$STAGE/assets/audio/music/"

python3 - "$STAGE" <<'PY'
import sys, glob, os
stage = sys.argv[1]
p = os.path.join(stage, "export_presets.cfg"); s = open(p).read()
i = s.find('name="Web"'); j = s.find('exclude_filter="', i); k = s.find('"', j+16)
# ASSERT THE PARSE FOUND ITS TARGET. str.find returns -1 on a miss and Python happily
# slices with it: i=-1 makes the next find start at the LAST character, j=-1 makes the
# slice s[15:k] read the file HEADER, and the write at the bottom then emits
# s[:15] + kept + s[k:] -- a silently CORRUPTED export_presets.cfg in the staged copy.
# Nothing about that raises. The pipeline does catch the consequence downstream (the
# packed-vs-expected gate, exit 4), but that gate exists to detect DROPPED CONTENT and
# would report a content regression for what is actually a broken parse -- the wrong
# cause, which is the expensive kind of failure to debug at deploy time.
# Rename the preset, reorder the keys, or add a preset before Web, and this fires.
if i < 0 or j < 0 or k < 0:
    sys.exit(f"[stage] BLOCKED: could not locate the Web preset's exclude_filter in "
             f"{p} (name=\"Web\" at {i}, exclude_filter at {j}, closing quote at {k}). "
             f"The cfg format changed -- fix this parse rather than letting it write.")
pats = [x.strip() for x in s[j+16:k].split(",")]

# DERIVED, not a hand-list: drop every music pattern that actually matches a
# master. Anything else in the filter (art, docs, the dead sfx_ability sources)
# is left alone. A hardcoded list of seven would rot the moment a pattern moved.
kept, dropped = [], []
for x in pats:
    if x.startswith("assets/audio/music/") and not x.startswith("assets/audio/music/sfx_ability"):
        if glob.glob(x):          # matches a real master -> it was hiding tracks
            dropped.append(x); continue
        # matches nothing: a dead pattern. Keep it; removing it is not this
        # script's job and its presence costs nothing.
    kept.append(x)
print(f"[stage]     dropped {len(dropped)} live music exclusion(s), kept {len(kept)}")
for d in dropped: print(f"[stage]       - {d}")
open(p, "w").write(s[:j+16] + ", ".join(kept) + s[k:])

# DERIVE how many masters should survive the SURVIVING filters. Comparing against
# the raw master count is wrong: some exclusions are deliberately kept (the dead
# sfx_ability_* sources), so a correct build packs FEWER than the master count.
# I asserted the raw count first and it blocked a good build -- the assertion was
# wrong, not the artifact, and a hand-picked constant here would rot the moment
# another exclusion is added or removed.
import glob as _g
masters = set(_g.glob("assets/audio/music/*.ogg"))
excluded = set()
for x in kept:
    if x.startswith("assets/audio/music/"):
        # .ogg ONLY. A bare glob also matches the .ogg.import sidecars, which
        # doubled the excluded count (2 -> 4) and understated `expected` by 2 --
        # a weaker assertion that still passes, which is the direction that hides.
        excluded.update(f for f in _g.glob(x) if f.endswith(".ogg"))
expected = len(masters - excluded)
print(f"[stage]     expect {expected} of {len(masters)} masters packed "
      f"({len(excluded)} deliberately excluded)")
open(os.path.join(stage, ".expected_music"), "w").write(str(expected))
PY

# ── 4. import + export + measure the REAL artifact ─────────────────────────
echo "[stage] 4/4 import + export (first run builds a fresh cache, ~minutes)"
( cd "$STAGE" && mkdir -p builds/web \
  && godot --headless --audio-driver Dummy --import > ../stage_import.log 2>&1 ) &
IEC=0; wait $! || IEC=$?
test $IEC -eq 0 || { echo "[stage] BLOCKED: staged import failed — tmp/stage_import.log" >&2; exit 3; }

( cd "$STAGE" && godot --headless --audio-driver Dummy \
    --export-release "Web" builds/web/index.html > ../stage_export.log 2>&1 ) &
EEC=0; wait $! || EEC=$?
test $EEC -eq 0 || { echo "[stage] BLOCKED: staged export failed — tmp/stage_export.log" >&2; exit 3; }

PCK="$STAGE/builds/web/index.pck"
[ -s "$PCK" ] || { echo "[stage] BLOCKED: export reported success but produced no pck" >&2; exit 3; }
SZ=$(stat -c%s "$PCK")

# The projection in make_web_audio.sh is derived from a PREVIOUS pck. This is the
# artifact itself, which is what the cap is enforced against.
if [ "$SZ" -ge "$PCK_LIMIT" ]; then
    echo "[stage] BLOCKED: pck ${SZ} >= ${PCK_LIMIT} — lower the bitrate" >&2; exit 4
fi
python3 -c "
sz=$SZ; cap=$PCK_LIMIT
print(f'[stage] pck {sz:,} B = {sz/1048576:.1f} MiB · headroom {(cap-sz)/1048576:.1f} MiB · FITS')"

# Assert the endings actually arrived. A shrinking pck is ALSO what dropping
# content looks like, so size alone cannot tell success from regression.
PACKED=$(command grep -ac 'Storing File.*assets/audio/music/' tmp/stage_export.log || true)
EXPECT=$(cat "$STAGE/.expected_music")
echo "[stage] music files packed: ${PACKED} (expected ${EXPECT})"
[ "$PACKED" -ge "$EXPECT" ] || {
    echo "[stage] BLOCKED: only ${PACKED} music files packed, expected >= ${EXPECT}." >&2
    echo "        The pck shrank because content was DROPPED, not compressed." >&2; exit 4; }

echo "[stage] masters untouched: $(find assets/audio/music -name '*.ogg' | wc -l) tracks still at 96k in assets/"
echo "[stage] artifact: ${STAGE}/builds/web/  — nothing published."
