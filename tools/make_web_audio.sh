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
# ⛔ A FLAG MUST NOT BECOME A TIER NAME. This took $1 unvalidated, so any non-numeric argument
# was used as a bitrate: `make_web_audio.sh --selftest` created tmp/web_audio/music_--selftestk
# and ran ffmpeg with an invalid rate (measured 2026-09-17, EC=234). It fails, but only after
# making a directory a later reader could mistake for a tier, and the error names ffmpeg rather
# than the bad argument. A tool with no --selftest should SAY so, not transcode.
case "$BITRATE" in
    ''|*[!0-9]*)
        echo "[web-audio] REFUSED: bitrate must be a plain integer in kbps, got '${BITRATE}'." >&2
        echo "            This tool takes a BITRATE, not a flag, and has no --selftest." >&2
        exit 2 ;;
esac
if [ "$BITRATE" -lt 8 ] || [ "$BITRATE" -gt 320 ]; then
    echo "[web-audio] REFUSED: bitrate ${BITRATE} kbps is outside 8-320 — that is a typo, not a tier." >&2
    exit 2
fi
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

# ── CROSS-WORKTREE CACHE ─────────────────────────────────────────────────────────────────────
# The idempotence check below is mtime-based and lives INSIDE the worktree, so it does nothing
# for a publish: every release builds in a fresh `tmp/pub<N>` with no tmp/web_audio, and a git
# checkout stamps the masters with the checkout time, so even a copied tier would look stale.
# Measured across .363-.366: 107s, 108s, 107s, 110s — ~108 seconds per publish to re-encode a
# byte-identical 83 MB tier, because the masters had not changed.
#
# KEYED ON CONTENT, not on mtime or size. A size-keyed cache would serve a stale tier for an
# edited master that kept its byte count, and nothing downstream would catch it: deploy_web's
# gate 3b compares the STAGE against the TIER, and both would come from the same bad cache.
# Hashing 169 MB of masters costs 1.0s against the 108s it saves.
_CACHE_ROOT="${WEB_AUDIO_CACHE:-$HOME/.cache/cowir_web_audio}"
_key="$(printf '%s\n' "${SRCS[@]}" \
        | while read -r _f; do printf '%s %s\n' "$(basename "$_f")" "$(md5sum < "$_f" | cut -d' ' -f1)"; done \
        | md5sum | cut -d' ' -f1)"
_CACHE_DIR="${_CACHE_ROOT}/${BITRATE}k_${_key}"
if [ -d "$_CACHE_DIR" ] && [ "$(find "$_CACHE_DIR" -name '*.ogg' | wc -l)" -eq "$TOTAL" ]; then
    cp -a "$_CACHE_DIR/." "$OUT_DIR/" && find "$OUT_DIR" -name '*.ogg' -exec touch {} +
    echo "[web-audio] restored ${TOTAL} track(s) from the cache — no re-encode"
    echo "[web-audio]   ${_CACHE_DIR}"
else
    echo "[web-audio] cache miss (${BITRATE}k_${_key:0:8}) — encoding"
fi

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

# POPULATE ONLY A COMPLETE, VERIFIED TIER. The loop above aborts on an empty output, so reaching
# here means every track exists and is non-empty; writing the cache before that check would
# persist a broken tier for every future publish.
if [ ! -d "$_CACHE_DIR" ]; then
    mkdir -p "$_CACHE_DIR" && cp -a "$OUT_DIR/." "$_CACHE_DIR/" \
        && echo "[web-audio] cached this tier for the next build" \
        || echo "[web-audio] note: could not write the cache — this run is unaffected" >&2
    # Bound the disk: keep the three most recent tiers for THIS bitrate. A tier is 83 MB and a
    # key changes whenever any master does, so an unbounded cache grows with every audio edit.
    ls -1dt "${_CACHE_ROOT}/${BITRATE}k_"* 2>/dev/null | tail -n +4 | while read -r _old; do
        rm -rf "$_old" && echo "[web-audio] pruned an older cached tier: $(basename "$_old")"
    done
fi
python3 - "$src_bytes" "$out_bytes" "$TOTAL" "$BITRATE" "$PCK_LIMIT_MIB" "$CACHE_LIMIT_MIB" <<'PY'
import sys, os, glob, re, time
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
PCK = os.path.expanduser(os.environ.get("WEB_REF_PCK",
                         "~/projects/cowir-main/builds/web/index.pck"))
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
    # ⛔ WAS: shipped_br parsed out of make_web_stage.sh's `BITRATE="${1:-48}"` — THE CALLEE'S
    # DEFAULT, which is true about that function and false about every real invocation, because
    # deploy_web.sh ALWAYS passes an argument. struktured's 40k ruling shipped in .357 and this
    # kept reading 48, so the projection below looked for a 48k tier, found `0 of 161` files and
    # SKIPPED — in .368 and .369 and every publish since the ruling. The refusal reads as care
    # ("rather than inventing a constant") while the reason for it IS a stale constant, and its
    # remediation line said `Run: tools/make_web_audio.sh 48` — the wrong bitrate, to the one
    # person in a position to notice. It also propagated: a lane read 48 out of that comment
    # tonight and nearly shipped it into a test header as the value players receive.
    #
    # The shipped bitrate has ONE home: deploy_web.sh's WEB_AUDIO_KBPS default, which is what
    # the caller passes down. Read THAT, and refuse rather than fall back to any constant — a
    # silent fallback is how a wrong number survives a rewrite of the thing that produced it.
    allm = set(glob.glob(d + "*.ogg"))
    shipped_br = None
    try:
        with open("tools/deploy_web.sh") as fh:
            m = re.search(r'WEB_AUDIO_KBPS="\$\{WEB_AUDIO_KBPS:-(\d+)\}"', fh.read())
            if m:
                shipped_br = int(m.group(1))
    except OSError:
        pass
    if shipped_br is None:
        print("[web-audio] could not read the shipped bitrate from tools/deploy_web.sh —")
        print("[web-audio] SKIPPING the projection rather than assuming one. If that default")
        print("[web-audio] moved, this parse moves with it; it must never fall back to a constant.")
        raise SystemExit(0)
    # ⛔ WAS: subtract the tier at SHIPPED_BR from the reference pck, guarded only by
    # `len(tier) != len(masters)` — a count of a DIRECTORY, which never asks whether the
    # reference pck's music IS that tier. It printed "the reference pck was built at {N}k"
    # as a statement of fact about the one thing it did not check, and its remediation line
    # said `Run: tools/make_web_audio.sh {shipped_br}` — i.e. BUILD THE WRONG TIER AND THE
    # GUARD WILL LET YOU THROUGH.
    #
    # ⚠️ NOT LATENT. A publish worktree always builds the shipped tier before this runs, so
    # the count matched on every publish and the subtraction was cross-era every time:
    #
    #     reference pck (48k era, 2026-09-06)     163.81 MiB
    #     minus the 40k tier the publish built    -82.54
    #     = "non-music payload"                    81.27 MiB   <- printed by .371 and .374
    #     minus the 48k tier it actually holds    -96.21
    #     = the truth                              67.60 MiB
    #     INFLATION                                13.67 MiB, every run, pessimistic
    #
    # And it is why "projected pck" equalled the reference's own size to the byte: with
    # other = pck - out, tot = out + other = pck identically. The identity and the inflation
    # are the same arithmetic seen from two sides.
    #
    # THE REFERENCE MUST DECLARE ITS OWN TIER. WEB_REF_PCK_KBPS says which bitrate the
    # reference pck's music was encoded at; that tier is what gets subtracted, and the
    # shipped tier is then added back on top. Undeclared is REFUSED, never assumed — the
    # whole defect was an assumption wearing a guard's clothes.
    # ── PREFERRED: the record the last successful publish left behind ───────────────────
    # check_web_audio_tier.py writes it from the pck's OWN FILE TABLE after gate 3b passes, so
    # the non-music payload is measured rather than derived from a tier directory that may be
    # from a different era. No tier on disk, no declared bitrate, nothing to mismatch — and it
    # is as fresh as the last release instead of however old the hardcoded pck happens to be.
    #
    # The ratio matters and was missing from the old arithmetic entirely: packed bytes are the
    # IMPORTED artifacts and run ~1.06x the staged tier, so adding raw tier bytes to a
    # packed-derived payload under-counts by that factor.
    rec_path = os.environ.get("WEB_REF_RECORD",
                              os.path.expanduser("~/.cache/cowir_web_audio/reference.txt"))
    rec = {}
    try:
        with open(rec_path) as fh:
            for line in fh:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    rec[k] = v
    except OSError:
        pass
    if {"pck_bytes", "packed_music_bytes"} <= set(rec):
        ref_bytes = int(rec["pck_bytes"])
        other = ref_bytes - int(rec["packed_music_bytes"])
        ratio = float(rec.get("packed_tier_ratio", 1.0))
        age_d = (time.time() - int(rec.get("recorded_at", 0))) / 86400.0
        print(f"[web-audio] non-music payload {other/mib:.1f} MiB  (MEASURED from the pck's own "
              f"table by the last passing publish, {age_d:.1f}d ago)")
        tot = (out * ratio + other) / mib
        # ⛔ THE IDENTITY SURVIVES INTO THIS PATH AND I NEARLY SHIPPED IT AGAIN. At the
        # record's OWN bitrate, out*ratio is just packed_music_bytes re-derived, so
        # tot = out*ratio + (pck - packed_music) ~= pck — the reference's size wearing a
        # projection's label, for the third time in this file. The residual (~0.13 MiB on
        # .374) is the ratio's approximation error, NOT predictive accuracy, and reporting
        # it as accuracy would be the same mistake one layer over.
        #
        # What the record actually buys is a CORRECT `other` (59.59 MiB measured from the
        # pck's table, against 81.27 MiB when a 40k tier was subtracted from a 48k-era pck)
        # and honest projections at OTHER bitrates, where `out` moves and `other` does not.
        rec_br = re.search(r"(\d+)k", rec.get("tier_dir", ""))
        if rec_br and rec_br.group(1) == str(br):
            print(f"[web-audio] at {br}k — the bitrate the record was MEASURED at — there is nothing")
            print(f"[web-audio] to project: out*ratio is packed_music re-derived, so this collapses to")
            print(f"[web-audio] the recorded build's own size. No ruling on the {limit} MiB itch limit")
            print(f"[web-audio] or the {cache} MiB cache line; deploy_web.sh gate 3 weighs the real pck.")
            print(f"[web-audio] Re-run at another bitrate for the deltas, which this does answer.")
            print("[web-audio] projections only. deploy_web.sh gate 3 measures the real pck.")
            raise SystemExit(0)
        print(f"[web-audio] projected pck ~{tot:.2f} MiB vs {limit} MiB itch limit "
              f"({'FITS' if tot < limit else 'OVER — drop the bitrate'})")
        print(f"[web-audio]               vs {cache} MiB browser cache line "
              f"({'CACHEABLE' if tot < cache else 'RE-DOWNLOADED EVERY VISIT'}"
              f", {abs(cache - tot):.2f} MiB {'spare' if tot < cache else 'over'})")
        future_out = (src + 69 * mib) * (out / src) * ratio
        ftot = (future_out + other) / mib
        print(f"[web-audio] with the ~48 queued monster themes: ~{ftot:.0f} MiB "
              f"({'FITS' if ftot < limit else 'OVER at ' + str(br) + 'k — needs fewer tracks or a lower bitrate'})")
        print("[web-audio] projections only. deploy_web.sh gate 3 measures the real pck.")
        raise SystemExit(0)

    ref_br = os.environ.get("WEB_REF_PCK_KBPS")
    if not ref_br:
        print(f"[web-audio] the reference pck's own bitrate is not declared, so the non-music")
        print(f"[web-audio] payload cannot be derived from it — subtracting a {shipped_br}k tier")
        print(f"[web-audio] from a pck encoded at some other bitrate inflates that payload and")
        print(f"[web-audio] every projection built on it. SKIPPING.")
        print(f"[web-audio] Set WEB_REF_PCK_KBPS=<bitrate of {os.path.basename(PCK)}> to enable it.")
        raise SystemExit(0)
    ref_br = int(ref_br)
    ref_tier = glob.glob("tmp/web_audio/music_%dk/*.ogg" % ref_br)
    if len(ref_tier) != len(allm):
        print(f"[web-audio] the reference pck declares {ref_br}k and THAT tier is not on disk")
        print(f"[web-audio] ({len(ref_tier)} of {len(allm)} files) — SKIPPING rather than subtracting")
        print(f"[web-audio] a tier the reference does not contain.")
        print(f"[web-audio] Run: tools/make_web_audio.sh {ref_br}   <- the REFERENCE's bitrate,")
        print(f"[web-audio] not this run's; building {shipped_br}k here would arm the bug this guard exists for.")
        raise SystemExit(0)
    in_pck = sum(os.path.getsize(f) for f in ref_tier)
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
        # ⛔ AT THE SHIPPING BITRATE THIS IS NOT A PROJECTION — IT IS AN IDENTITY.
        # `other` is (reference pck - the tier at shipped_br); `out` is the tier this run
        # built. When those are the SAME tier the arithmetic collapses:
        #
        #     tot = (out + other) = out + (pck - out) = pck        exactly, every time
        #
        # so "projected pck" re-reports the REFERENCE BUILD'S OWN SIZE and the verdicts
        # below rule on a build that is not this one. Measured in v3.33.371-alpha, the
        # first release where this code ran at all: reference 163.81 MiB, "projected"
        # 163.81 MiB, and it printed RE-DOWNLOADED EVERY VISIT, 3.81 MiB over — while
        # gate 3b weighed the real artifact of that same run at 147.28 MiB, 12.72 UNDER.
        # A verdict with the WRONG SIGN, from a number that could only ever have been the
        # reference's size. Same class as the hardcoded remedy below, one line up: a
        # constant driving a verdict, except the constant arrives by cancellation.
        #
        # Every publish runs at the shipping bitrate, so that is the degenerate case ALWAYS.
        # The projection earns its name only for a DIFFERENT bitrate, which is what the
        # deltas are for and what the comment above already claims.
        # The identity fires when the tier SUBTRACTED is the tier ADDED BACK, which is
        # ref_br vs br. It read shipped_br while the subtraction itself used the wrong
        # tier; correcting that moved the condition with it. Against a 48k reference a
        # 40k run is now a REAL projection, not a re-report of the reference's size.
        degenerate = (str(br) == str(ref_br))
        if degenerate:
            print(f"[web-audio] at {br}k — the REFERENCE's own bitrate — there is nothing to project: "
                  f"the figure would be")
            print(f"[web-audio] the REFERENCE build's own size ({os.path.getsize(PCK)/mib:.2f} MiB, "
                  f"{age_d:.0f}d old), not this one's.")
            print(f"[web-audio] No ruling on the {limit} MiB itch limit or the {cache} MiB cache "
                  f"line from a stale build:")
            print(f"[web-audio] deploy_web.sh gate 3 weighs the real pck and is the only thing "
                  f"that can say.")
            print(f"[web-audio] Re-run at another bitrate for the deltas, which staleness does "
                  f"not affect.")
        else:
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
