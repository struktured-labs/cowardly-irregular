#!/usr/bin/env python3
"""Prove the SHIPPED web pck carries the music tier the chain says it staged.

WHY THIS EXISTS
---------------
make_web_stage.sh swaps assets/audio/music for a re-encoded tier and blocks if the tier holds
a different number of tracks than the masters. That guard compares COUNTS, not RATES (cowir-sfx,
2026-09-16): a leftover tier directory from a previous bitrate has the right count and the wrong
audio, and stages as if it were the requested one. Counting cannot see it; bytes can.

It reads the pck's OWN FILE TABLE rather than source bytes. Every byte figure that moved during
the 2026-09-16 cache-line thread was a source-byte model: 96k masters priced against a 48k pck,
artifact sizes against a compressed-or-not pck, a pre-filter tree's config against a staged
build. The table is the artifact describing itself.

TWO SIZES, AND THEY ARE NOT THE SAME NUMBER
    file size    what the browser caches and what itch's cap measures  <- the one that decides
    table total  the sum of the entries inside it
Measured on the first 40k stage: 156,260,016 B on disk vs 155,884,797 B of entries — 375,219 B
of header and file table. Both were under the line, so a check using the wrong one would have
been right by luck. The cache-line arm uses the FILE size.

THREE ARMS, STRONGEST FIRST
    stage vs tier   md5, exact, needs --stage. Did the stage swap in THIS tier's files?
    pck vs stage    per-file ratio band. Does the pck carry the audio the stage held?
    median ratio    population check, the backstop when --stage is unavailable.

RESOLVING A TRACK TO ITS ARTIFACT
    --stage=DIR     exact: reads each source's .import sidecar and takes its `path=`
    (no --stage)    basename join, which REFUSES when two artifacts share a basename
The basename path is the weak one and it fired on the first real run: assets/audio/music and
assets/audio/sfx both contain ambient_cave.ogg, ambient_forest.ogg, ambient_village.ogg and
victory.ogg. Attributing packed bytes by basename once produced a figure 13x too high in this
lane. Prefer --stage; the fallback exists so the tool still says something about a pck whose
stage is gone, and what it says there is "ambiguous", never a guess.

    tools/check_web_audio_tier.py <index.pck> <tier dir> [--stage=DIR] [--expect-tracks=N]
                                 [--cache-line=BYTES] [--require-under-cache-line]

The cache line is REPORTED, not enforced, unless --require-under-cache-line is passed. That
matches deploy_web.sh, where PCK_CACHE_LINE has always been advisory because what to cut is
struktured's call, not a script's. The TIER IDENTITY checks always block: shipping 48k audio
from a chain that says 40k is the pipeline lying about its own artifact.

Exit 0 every check passed · 5 a check failed · 2 usage or an input that cannot be measured.
"""
import collections
import hashlib
import os
import statistics
import time
import struct
import sys

# TWO ARMS, because one of them alone is not load-bearing. All four figures measured 2026-09-16
# on 161 real tracks, the same pcks both times:
#
#   pairing                     per-file ratio            median
#   40k pck vs 40k tier (right) 1.038 - 1.128             1.064
#   48k pck vs 40k tier (wrong) 1.106 - 1.547             1.257
#
# The per-file ranges OVERLAP at 1.106-1.128, so a per-file band cannot separate them: with
# [0.95, 1.30] only 40 of 161 wrong-tier files breach it, and the wrong tier's own median sits
# INSIDE the band. A 48->44 step would have breached it nowhere at all and passed clean. The
# MEDIAN is the discriminator — it is a population statistic over 161 files and it moves with the
# bitrate ratio, so a tier one step away (~10%) lands outside [1.00, 1.16] while the correct tier
# sits at 1.064 with room on both sides. It is also bitrate-independent by construction: every
# file is compared to ITS OWN source, so a correct 64k tier medians near 1.04 and a correct 24k
# one near 1.10, both inside.
#
# The per-file band stays, doing the job it CAN do: catching one truncated or corrupt artifact
# that a median over 161 files would absorb.
RATIO_LO, RATIO_HI = 0.95, 1.30
MEDIAN_LO, MEDIAN_HI = 1.00, 1.16
# WHERE the stage holds this tier's files. Music by default; the web voice tier passes
# --subdir=assets/audio/sfx (make_web_voice.sh). Both bands above were calibrated on MUSIC, so a
# non-music tier must bring its own measured bands (--ratio-band / --median-band) — this tool does
# not assume a 16 KB voice line carries the same packing overhead as a 500 KB bed.
SUBDIR = "assets/audio/music"


def die(msg):
    print(f"[tier] BLOCKED: {msg}", file=sys.stderr)
    sys.exit(2)


def pck_entries(path):
    """Every (packed path -> declared size) in a GDPC v1/v2 pack."""
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            die(f"{path} is not a Godot pck (no GDPC magic).")
        ver = struct.unpack("<I", f.read(4))[0]
        f.read(12)                      # engine major/minor/patch
        if ver == 2:
            f.read(4)                   # pack flags
            f.read(8)                   # file base offset
        f.read(16 * 4)                  # reserved
        n = struct.unpack("<I", f.read(4))[0]
        out = {}
        for _ in range(n):
            ln = struct.unpack("<I", f.read(4))[0]
            p = f.read(ln).rstrip(b"\0").decode("utf-8", "replace").replace("res://", "")
            _off, size = struct.unpack("<QQ", f.read(16))
            f.read(16)                  # md5
            if ver == 2:
                f.read(4)               # entry flags
            out[p] = size
    return out


def import_artifact(stage, name):
    """The artifact a staged source declares, from its own .import sidecar."""
    sidecar = os.path.join(stage, SUBDIR, name + ".ogg.import")
    if not os.path.exists(sidecar):
        return None, f"{name}: no .import sidecar in the stage — the stage never imported it"
    with open(sidecar, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("path="):
                return line.split("=", 1)[1].strip().strip('"').replace("res://", ""), None
    return None, f"{name}: .import sidecar declares no path= — nothing to look up in the pck"


def main():
    argv = sys.argv[1:]
    args = [a for a in argv if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    flags = {a for a in argv if a.startswith("--") and "=" not in a}
    if len(args) != 2:
        print("usage: check_web_audio_tier.py <index.pck> <tier dir> [--stage=DIR] "
              "[--expect-tracks=N] [--cache-line=BYTES] [--require-under-cache-line]",
              file=sys.stderr)
        sys.exit(2)
    pck_path, tier = args
    for p in (pck_path, tier):
        if not os.path.exists(p):
            die(f"{p} does not exist. A check that cannot read its subject is not a passing one.")
    stage = opts.get("stage")
    if stage and not os.path.isdir(stage):
        die(f"--stage={stage} is not a directory. Silently falling back to a basename join would "
            f"answer a WEAKER question than the one asked for.")
    cache_line = int(opts.get("cache-line", 160 * 1024 * 1024))
    global SUBDIR, RATIO_LO, RATIO_HI, MEDIAN_LO, MEDIAN_HI
    SUBDIR = opts.get("subdir", SUBDIR).rstrip("/")
    for key in ("ratio-band", "median-band"):
        if key in opts:
            try:
                lo, hi = (float(x) for x in opts[key].split(","))
            except ValueError:
                die(f"--{key}={opts[key]} is not LO,HI — refusing to guess a band")
            if not (0 < lo < hi):
                die(f"--{key}={opts[key]} is not an increasing positive band")
            if key == "ratio-band":
                RATIO_LO, RATIO_HI = lo, hi
            else:
                MEDIAN_LO, MEDIAN_HI = lo, hi
    if SUBDIR != "assets/audio/music" and ("ratio-band" not in opts or "median-band" not in opts):
        die(f"--subdir={SUBDIR} needs its own --ratio-band and --median-band: the defaults were "
            f"calibrated on music and would judge another corpus by the wrong yardstick")
    if SUBDIR != "assets/audio/music" and opts.get("record"):
        die("--record writes the MUSIC reference that make_web_audio.sh's size projection reads "
            "(packed_music_bytes); a non-music tier must not overwrite it")

    entries = pck_entries(pck_path)
    file_size = os.path.getsize(pck_path)
    table_total = sum(entries.values())

    tracks = {f[:-4]: os.path.getsize(os.path.join(tier, f))
              for f in os.listdir(tier) if f.endswith(".ogg")}
    if not tracks:
        die(f"no .ogg in {tier} — an empty tier would satisfy every ratio below it.")

    by_basename = collections.defaultdict(list)
    if not stage:
        for p, size in entries.items():
            base = os.path.basename(p)
            if p.startswith(".godot/imported/") and ".ogg-" in base:
                by_basename[base.split(".ogg-")[0]].append((p, size))

    # ── the EXACT arm ────────────────────────────────────────────────────────────────────
    # With the stage on disk the tier question needs no statistics at all: the file the stage
    # swapped in either IS the tier file or it is not. This is what make_web_stage.sh's count
    # guard should have been. The ratio bands below cannot replace it — measured, the correct
    # median moves with the bitrate (1.064 at 40k, 1.098 at 48k), so a band wide enough not to
    # false-alarm on a future tier is too wide to catch a one-step mistake. Hashes do not care.
    swapped_bad = []
    if stage:
        for name, src_size in sorted(tracks.items()):
            staged = os.path.join(stage, SUBDIR, name + ".ogg")
            if not os.path.exists(staged):
                swapped_bad.append(f"{name}: in the tier but NOT in the stage — never swapped in")
                continue
            if os.path.getsize(staged) != src_size:
                swapped_bad.append(f"{name}: stage has {os.path.getsize(staged):,} B, tier has "
                                   f"{src_size:,} B — the stage is carrying OTHER audio")
                continue
            a = hashlib.md5(open(staged, "rb").read()).hexdigest()
            b = hashlib.md5(open(os.path.join(tier, name + ".ogg"), "rb").read()).hexdigest()
            if a != b:
                swapped_bad.append(f"{name}: same size, different bytes — stage {a[:12]} vs "
                                   f"tier {b[:12]}")
        if swapped_bad:
            print(f"[tier] stage vs tier: {len(tracks)-len(swapped_bad)}/{len(tracks)} identical")
        else:
            print(f"[tier] stage vs tier: {len(tracks)}/{len(tracks)} byte-identical "
                  f"(md5) — the stage carries EXACTLY this tier")

    bad, ratios, packed_total, matched = [], [], 0, 0
    bad.extend(swapped_bad[:8])
    if len(swapped_bad) > 8:
        bad.append(f"... and {len(swapped_bad)-8} more tracks differ between stage and tier")
    for name, src_size in sorted(tracks.items()):
        if stage:
            art, err = import_artifact(stage, name)
            if err:
                bad.append(err)
                continue
            if art not in entries:
                bad.append(f"{name}: staged and imported, but {art} is NOT in the pck")
                continue
            size = entries[art]
        else:
            hits = by_basename.get(name, [])
            if not hits:
                bad.append(f"{name}: staged in the tier but NOT in the pck")
                continue
            if len(hits) > 1:
                bad.append(f"{name}: {len(hits)} artifacts share this basename — attribution is "
                           f"ambiguous; pass --stage to resolve it exactly")
                continue
            size = hits[0][1]
        packed_total += size
        matched += 1
        ratio = size / src_size if src_size else 0
        ratios.append(ratio)
        if not (RATIO_LO <= ratio <= RATIO_HI):
            bad.append(f"{name}: packed {size:,} B vs tier {src_size:,} B — ratio {ratio:.3f} "
                       f"outside [{RATIO_LO}, {RATIO_HI}]; this is NOT the staged tier's audio")

    expect = int(opts.get("expect-tracks", len(tracks)))
    print(f"[tier] pck FILE {file_size:,} B = {file_size/1048576:.2f} MiB "
          f"(table entries {table_total:,} B; {file_size-table_total:,} B of header and table)")
    print(f"[tier] {SUBDIR}: {matched}/{len(tracks)} tier tracks resolved "
          f"{'via the stage .import sidecars' if stage else 'by basename'} · "
          f"{packed_total:,} B packed")
    if ratios:
        med = statistics.median(ratios)
        print(f"[tier] packed/tier ratio: min {min(ratios):.3f} · median {med:.3f} · "
              f"max {max(ratios):.3f} (per-file band [{RATIO_LO}, {RATIO_HI}], "
              f"median band [{MEDIAN_LO}, {MEDIAN_HI}])")
        if not (MEDIAN_LO <= med <= MEDIAN_HI):
            bad.append(f"MEDIAN packed/tier ratio {med:.3f} is outside [{MEDIAN_LO}, {MEDIAN_HI}] "
                       f"across all {len(ratios)} tracks — the pck's music is systematically "
                       f"{'larger' if med > MEDIAN_HI else 'smaller'} than this tier, so it was "
                       f"encoded at a DIFFERENT bitrate. This is the tier-identity arm; a "
                       f"per-file band cannot see it (the ranges overlap).")
    if matched != expect:
        bad.append(f"resolved {matched} entries under {SUBDIR}, expected {expect} — a TIER CHANGE must "
                   f"not remove tracks")
    if file_size >= cache_line:
        msg = (f"pck {file_size/1048576:.2f} MiB is AT OR OVER the {cache_line/1048576:.2f} MiB "
               f"browser cache line by {(file_size-cache_line)/1048576:.2f} MiB — a returning "
               f"player re-downloads the whole build every visit")
        if "--require-under-cache-line" in flags:
            bad.append(msg)
        else:
            print(f"[tier] NOTE (advisory, not a block): {msg}")
    else:
        print(f"[tier] UNDER the cache line by {(cache_line-file_size)/1048576:.2f} MiB")

    # ── the reference record ────────────────────────────────────────────────────────────
    # Written ONLY on a pass, because a failing check means these numbers describe a pck that
    # does not carry the tier it claims — the exact thing a future projection must not inherit.
    #
    # WHY IT EXISTS. make_web_audio.sh's size projection needs the NON-MUSIC payload of a real
    # build. It used to derive that by subtracting a tier DIRECTORY from a reference pck, which
    # is how it came to subtract a 40k tier from a 48k-era pck for thirteen releases (13.67 MiB
    # inflation, every publish). The two numbers it actually wants are both measured right here,
    # from the pck's own file table: the file's size and the bytes its music entries occupy.
    # Recording them makes the reference EXACT, self-describing, and as fresh as the last
    # successful publish — no tier on disk, no declared bitrate, no era to mismatch.
    #
    # The ratio goes in too: packed bytes are the IMPORTED artifacts and run ~1.06x the staged
    # tier, so a projection that adds raw tier bytes to a packed-derived payload under-counts.
    # That term was missing entirely from the old arithmetic.
    rec = opts.get("record")
    if rec and not bad:
        try:
            os.makedirs(os.path.dirname(rec), exist_ok=True)
            with open(rec, "w") as fh:
                fh.write(f"pck_bytes={file_size}\n")
                fh.write(f"packed_music_bytes={packed_total}\n")
                fh.write(f"packed_tier_ratio={statistics.median(ratios):.4f}\n" if ratios else "")
                fh.write(f"tier_dir={os.path.basename(os.path.normpath(tier))}\n")
                fh.write(f"recorded_at={int(time.time())}\n")
            print(f"[tier] reference recorded -> {rec}")
        except OSError as e:
            print(f"[tier] note: could not write the reference record ({e}) — this run is unaffected",
                  file=sys.stderr)

    for b in bad:
        print(f"[tier] FAIL: {b}", file=sys.stderr)
    return 5 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
