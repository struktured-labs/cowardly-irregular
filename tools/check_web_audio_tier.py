#!/usr/bin/env python3
"""Prove the SHIPPED web pck carries the music tier the chain says it staged.

WHY THIS EXISTS
---------------
make_web_stage.sh swaps assets/audio/music for a re-encoded tier and blocks if the tier holds
fewer tracks than the masters. That guard compares COUNTS, not RATES (cowir-sfx, 2026-09-16):
a leftover tier directory from a previous bitrate has the right count and the wrong audio, and
stages as if it were the requested one. Counting cannot see it; bytes can.

It also reads the pck's OWN FILE TABLE rather than source bytes. Every byte figure that moved
during the 2026-09-16 cache-line thread was a source-byte model: 96k masters priced against a
48k pck, artifact sizes against a compressed-or-not pck, a pre-filter tree's config against a
staged build. The table is the artifact describing itself.

    tools/check_web_audio_tier.py <index.pck> <tier dir> [--expect-tracks=N] [--cache-line=BYTES]
                                 [--require-under-cache-line]

The cache line is REPORTED, not enforced, unless --require-under-cache-line is passed. That
matches deploy_web.sh, where PCK_CACHE_LINE has always been an advisory number because what to
cut is struktured's call, not a script's. The TIER IDENTITY checks below always block: shipping
48k audio from a chain that says 40k is the pipeline lying about its own artifact.

Exit 0 every check passed · 5 a check failed · 2 usage/unreadable.
"""
import os, struct, sys, collections

RATIO_LO, RATIO_HI = 0.95, 1.30   # godot's .ogg artifact wraps the stream; measured 1.07-1.12


def pck_entries(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            print(f"[tier] BLOCKED: {path} is not a Godot pck (no GDPC magic).", file=sys.stderr); sys.exit(2)
        ver = struct.unpack("<I", f.read(4))[0]
        f.read(12)
        if ver == 2:
            f.read(4); f.read(8)
        f.read(16 * 4)
        n = struct.unpack("<I", f.read(4))[0]
        out = {}
        for _ in range(n):
            ln = struct.unpack("<I", f.read(4))[0]
            p = f.read(ln).rstrip(b"\0").decode("utf-8", "replace").replace("res://", "")
            _off, size = struct.unpack("<QQ", f.read(16))
            f.read(16)
            if ver == 2:
                f.read(4)
            out[p] = size
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = {a.split("=")[0]: a.split("=")[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
    if len(args) != 2:
        print("usage: check_web_audio_tier.py <index.pck> <tier dir> [--expect-tracks=N] [--cache-line=BYTES]", file=sys.stderr)
        sys.exit(2)
    pck_path, tier = args
    for p in (pck_path, tier):
        if not os.path.exists(p):
            print(f"[tier] BLOCKED: {p} does not exist. A check that cannot read its subject is not a passing one.",
                     file=sys.stderr); sys.exit(2)
    cache_line = int(opts.get("--cache-line", 160 * 1024 * 1024))
    entries = pck_entries(pck_path)
    total = sum(entries.values())

    tracks = {f[:-4]: os.path.getsize(os.path.join(tier, f))
              for f in os.listdir(tier) if f.endswith(".ogg")}
    if not tracks:
        print(f"[tier] BLOCKED: no .ogg in {tier} — an empty tier would pass every ratio below.", file=sys.stderr)
        sys.exit(2)

    # artifact -> the track it came from, by the source basename Godot embeds in the name.
    # Uniqueness is ASSERTED, not assumed: attributing packed bytes by basename without that
    # check once made a figure in this lane 13x too high.
    by_track = collections.defaultdict(list)
    for p, size in entries.items():
        if not p.startswith(".godot/imported/"):
            continue
        base = os.path.basename(p)
        if ".ogg-" not in base:
            continue
        by_track[base.split(".ogg-")[0]].append((p, size))

    bad, matched, packed_total = [], 0, 0
    for name, src_size in sorted(tracks.items()):
        hits = by_track.get(name, [])
        if len(hits) == 0:
            bad.append(f"{name}: staged in the tier but NOT in the pck")
            continue
        if len(hits) > 1:
            bad.append(f"{name}: {len(hits)} artifacts share this basename — attribution is ambiguous")
            continue
        _p, size = hits[0]
        packed_total += size
        matched += 1
        ratio = size / src_size if src_size else 0
        if not (RATIO_LO <= ratio <= RATIO_HI):
            bad.append(f"{name}: packed {size:,} B vs tier {src_size:,} B — ratio {ratio:.3f} outside "
                       f"[{RATIO_LO}, {RATIO_HI}]; this is NOT the staged tier's audio")

    expect = int(opts.get("--expect-tracks", len(tracks)))
    print(f"[tier] pck {total:,} B = {total/1048576:.2f} MiB · cache line {cache_line/1048576:.2f} MiB")
    print(f"[tier] music: {matched}/{len(tracks)} tier tracks matched in the pck · {packed_total:,} B packed")
    if matched != expect:
        bad.append(f"matched {matched} music entries, expected {expect} — a TIER CHANGE must not remove tracks")
    require_under = "--require-under-cache-line" in sys.argv
    if total >= cache_line:
        msg = (f"pck {total/1048576:.2f} MiB is AT OR OVER the {cache_line/1048576:.2f} MiB browser cache line "
               f"by {(total-cache_line)/1048576:.2f} MiB — a returning player re-downloads the whole build "
               f"every visit")
        if require_under:
            bad.append(msg)
        else:
            print(f"[tier] NOTE (advisory, not a block): {msg}")
    else:
        print(f"[tier] UNDER the cache line by {(cache_line-total)/1048576:.2f} MiB")
    for b in bad:
        print(f"[tier] FAIL: {b}", file=sys.stderr)
    return 5 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
