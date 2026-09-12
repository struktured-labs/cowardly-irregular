#!/usr/bin/env python3
"""Report which itch store screenshots depict something that has changed since they were taken.

WHY THIS EXISTS
---------------
The shot set was last re-taken at v3.33.267-alpha. On 2026-09-11 a hand-run sweep recorded
"at least 9 of 20 shots depict a scene that changed" against a store serving v3.33.299-alpha,
and committed that sentence to CAPTIONS.md. By v3.33.337-alpha the sentence was still there and
the number was no longer the answer to anything -- the store had moved 38 tags.

A staleness figure decays FASTER than the thing it measures, because it is pinned to a tag the
moment it is written. So this is a tool rather than a paragraph: re-derive it at any pair of
tags instead of trusting a figure whose re-measurement date nobody recorded.

WHAT IT DOES NOT DO
-------------------
It answers "did the scene SCRIPT move", never "does the FRAME differ". A shot goes stale
through a sprite, a font, a HUD overlay or a caption too, none of which this sees. So:

    changed    -> a candidate for a re-shoot, NOT proof the image is wrong
    unchanged  -> the script did not move, nothing wider
    unmapped   -> NOT examined. Battle surfaces and data-driven dungeons are not one script.

The three buckets are reported separately and the headline is a FLOOR, never a total -- an
exhaustive claim here would be false the next time a sprite lands.

⛔ WHY THERE IS NO "REFERENCED RESOURCE" AXIS. The obvious upgrade is to follow each scene's
res:// references and call a shot changed when any of them moved. Measured at three spans
against the real shot set, it is worthless:

    v3.33.267..343  (1507 commits)   script 10/11  ->  script-OR-refs 11/11   saturated
    v3.33.330..343  ( 173 commits)   script  4/11  ->  script-OR-refs  4/11   no change
    v3.33.342..343  (  24 commits)   script  0/11  ->  script-OR-refs  0/11   no change

Where it changes the answer it empties the unchanged column; where it would be safe it adds
nothing. An all-changed verdict is as useless as an all-unchanged one, because the point of
this report is a work LIST.

✅ WHAT DOES WORK IS --compare, and it is the check that found the real defect. On 2026-09-12
the script axis put `whispering_cave` in the UNCHANGED column -- correctly, WhisperingCave.gd
has not moved since .267 -- while a fresh capture was 4.5x the stored bytes (50,654 ->
230,970). Provenance checked before believing it: only marketing_shots.gd emits that name
(store_shots_225.gd: 0 matches), both runs used its fixed 2-frame protocol at 1280x720, and
DungeonLighting carries no fade, so the two frames are comparable and the difference is real.

    changed/unchanged  a cheap PRIORITISER over scene scripts
    --compare          the AUTHORITATIVE check, and the only one that sees a frame

Usage:
    tools/store_shot_staleness.py --from <tag> --to <tag> [--shots DIR] [--json]
    tools/store_shot_staleness.py --compare <stored DIR> <fresh DIR> [--json]
    tools/store_shot_staleness.py --selftest
"""
import argparse, json, os, re, subprocess, sys


def _git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout


def pascal(stem):
    """frosthold_village -> FrostholdVillage. The shot names are snake_case; scenes are Pascal."""
    return "".join(p[:1].upper() + p[1:] for p in stem.split("_") if p)


def scene_index(tag):
    """Basename (no extension) -> [paths], for .gd/.tscn under src/ at `tag`. test/ excluded."""
    idx = {}
    for path in _git("ls-tree", "--name-only", "-r", tag, "src/").splitlines():
        if not path.endswith((".gd", ".tscn")):
            continue
        idx.setdefault(os.path.splitext(os.path.basename(path))[0], []).append(path)
    return idx


def changed_paths(a, b):
    return set(_git("diff", "--name-only", f"{a}..{b}").splitlines())


def classify(shots, a, b):
    idx, changed = scene_index(b), changed_paths(a, b)
    out = {"changed": [], "unchanged": [], "unmapped": []}
    for shot in shots:
        paths = idx.get(pascal(shot))
        if not paths:
            out["unmapped"].append({"shot": shot})
        elif any(p in changed for p in paths):
            out["changed"].append({"shot": shot, "files": sorted(p for p in paths if p in changed)})
        else:
            out["unchanged"].append({"shot": shot, "files": sorted(paths)})
    return out



# store_shots_225.gd's own constant: below this a capture is almost certainly an empty grey
# void. Its docstring records 7.7 KB where populated scenes are 50-300 KB, so a fresh capture
# under it photographed nothing and the exit code will not say so.
VOID_BYTES = 20000


def _png_dim(path):
    with open(path, "rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    import struct
    return struct.unpack(">II", head[16:24])


def compare(stored_dir, fresh_dir):
    """Byte-and-dimension diff between the shipped set and a fresh capture run.

    Reports the two failures a size diff can actually see: a capture that photographed a void,
    and a frame whose bytes moved even though its script did not. It does NOT judge whether a
    change is an improvement -- that needs an eye, and the caption file records which shot
    leads and why.
    """
    for d in (stored_dir, fresh_dir):
        if not os.path.isdir(d):
            sys.exit(f"BLOCKED: no directory at {d!r}. Refusing to report a comparison over a "
                     f"directory that does not exist.")
    stored = {os.path.splitext(f)[0] for f in os.listdir(stored_dir) if f.endswith(".png")}
    fresh = {os.path.splitext(f)[0] for f in os.listdir(fresh_dir) if f.endswith(".png")}
    if not fresh:
        sys.exit(f"BLOCKED: {fresh_dir!r} holds no .png -- an empty capture run reports every "
                 f"stored shot as missing, which is not a finding about the shots.")
    out = {"moved": [], "same": [], "void": [], "dim_mismatch": [],
           "only_stored": sorted(stored - fresh), "only_fresh": sorted(fresh - stored)}
    for name in sorted(stored & fresh):
        sp = os.path.join(stored_dir, name + ".png")
        fp = os.path.join(fresh_dir, name + ".png")
        sb, fb = os.path.getsize(sp), os.path.getsize(fp)
        sd, fd = _png_dim(sp), _png_dim(fp)
        row = {"shot": name, "stored_bytes": sb, "fresh_bytes": fb,
               "pct": round((fb - sb) / sb * 100.0, 1) if sb else None,
               "stored_dim": sd, "fresh_dim": fd}
        if fb < VOID_BYTES:
            out["void"].append(row)          # a void is not a "change", it is a failed capture
        elif sd != fd:
            out["dim_mismatch"].append(row)  # different subject, not a comparable frame
        elif abs(fb - sb) * 100 >= sb * 5:   # >=5% of the stored size
            out["moved"].append(row)
        else:
            out["same"].append(row)
    return out


def read_shots(d):
    # ⛔ A MISSING SHOT DIRECTORY MUST NOT REPORT "0 STALE". itch-assets/ is gitignored on main
    # and lives on the store-assets branch, so the overwhelmingly likely reason this directory
    # is absent is that the caller is in the wrong tree -- which is exactly when a cheerful
    # zero would be believed. Refuse instead.
    if not os.path.isdir(d):
        sys.exit(f"BLOCKED: no shot directory at {d!r}. itch-assets/ is gitignored on main and "
                 f"lives on the store-assets branch; pass --shots. Refusing to report a count "
                 f"over a directory that does not exist.")
    shots = sorted(os.path.splitext(f)[0] for f in os.listdir(d) if f.endswith(".png"))
    if not shots:
        sys.exit(f"BLOCKED: {d!r} exists but holds no .png -- an empty corpus reports 0 stale "
                 f"for the same reason a missing one does.")
    return shots


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="a")
    ap.add_argument("--to", dest="b")
    ap.add_argument("--shots", default="itch-assets/screenshots")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--compare", nargs=2, metavar=("STORED", "FRESH"))
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.compare:
        res = compare(*args.compare)
        if args.json:
            print(json.dumps(res, indent=2)); return 0
        n = sum(len(res[k]) for k in ("moved", "same", "void", "dim_mismatch"))
        print(f"[shots] {n} comparable · stored {args.compare[0]} · fresh {args.compare[1]}")
        for r in res["void"]:
            print(f"  ⛔ VOID      {r['shot']:<26} fresh {r['fresh_bytes']:,} B < {VOID_BYTES:,} "
                  f"— the CAPTURE failed, this is not a frame change")
        for r in res["dim_mismatch"]:
            print(f"  ⛔ DIM       {r['shot']:<26} stored {r['stored_dim']} vs fresh {r['fresh_dim']} "
                  f"— different subject, not a comparable frame")
        for r in res["moved"]:
            print(f"  MOVED       {r['shot']:<26} {r['stored_bytes']:>9,} -> {r['fresh_bytes']:>9,} B "
                  f"({r['pct']:+.1f}%)")
        for r in res["same"]:
            print(f"  same        {r['shot']:<26} {r['stored_bytes']:>9,} -> {r['fresh_bytes']:>9,} B "
                  f"({r['pct']:+.1f}%)")
        for k in ("only_stored", "only_fresh"):
            for name in res[k]:
                print(f"  {k:<11} {name}")
        print(f"[shots] MOVED is a re-shoot CANDIDATE, not a verdict — bytes cannot say which "
              f"frame is better.")
        return 0
    if not (args.a and args.b):
        sys.exit("usage: --from <tag> --to <tag> [--shots DIR] [--json]")
    for t in (args.a, args.b):
        if not _git("rev-parse", "--verify", f"{t}^{{commit}}").strip():
            sys.exit(f"BLOCKED: {t!r} does not resolve to a commit in this repo.")

    res = classify(read_shots(args.shots), args.a, args.b)
    if args.json:
        print(json.dumps(res, indent=2)); return 0
    n = sum(len(v) for v in res.values())
    print(f"[shots] {n} shot(s) · {args.a} -> {args.b}")
    print(f"[shots] AT LEAST {len(res['changed'])} of {n} depict a scene script that changed "
          f"(a floor: {len(res['unmapped'])} unmapped are UNEXAMINED)")
    for shot in res["changed"]:
        print(f"  changed    {shot['shot']:<32} {', '.join(shot['files'])}")
    for shot in res["unchanged"]:
        print(f"  unchanged  {shot['shot']:<32} {', '.join(shot['files'])}  (script only)")
    for shot in res["unmapped"]:
        print(f"  UNMAPPED   {shot['shot']:<32} not one scene script — NOT examined")
    return 0


def selftest():
    p = f = 0
    def chk(name, got, want):
        nonlocal p, f
        if got == want: p += 1; print(f"  ok    {name:<54} {got}")
        else: f += 1; print(f"  FAIL  {name:<54} got {got!r} want {want!r}")

    chk("pascal: snake to Pascal", pascal("frosthold_village"), "FrostholdVillage")
    chk("pascal: single word", pascal("battle"), "Battle")
    chk("pascal: already-empty parts ignored", pascal("inn__interior"), "InnInterior")

    # Bucket assignment, driven by injected fakes so the arms do not depend on repo state.
    g = globals()
    real_idx, real_chg = g["scene_index"], g["changed_paths"]
    g["scene_index"] = lambda tag: {"AVillage": ["src/maps/AVillage.gd"],
                                    "BVillage": ["src/maps/BVillage.gd"]}
    g["changed_paths"] = lambda a, b: {"src/maps/AVillage.gd"}
    r = classify(["a_village", "b_village", "zzz_not_a_scene"], "T1", "T2")
    chk("a changed scene lands in changed",   [x["shot"] for x in r["changed"]],   ["a_village"])
    chk("an unchanged scene lands unchanged", [x["shot"] for x in r["unchanged"]], ["b_village"])
    # the control that matters: a shot with NO scene must never silently read as "unchanged"
    chk("an unmapped shot is NOT unchanged",  [x["shot"] for x in r["unmapped"]],  ["zzz_not_a_scene"])

    # direction control: with NOTHING changed, the same corpus must move a_village out of changed
    g["changed_paths"] = lambda a, b: set()
    r2 = classify(["a_village", "b_village"], "T1", "T2")
    chk("no changes -> changed bucket empties", len(r2["changed"]), 0)
    chk("...and both land in unchanged",        len(r2["unchanged"]), 2)
    g["scene_index"], g["changed_paths"] = real_idx, real_chg

    # Vacuity: a missing or empty directory must EXIT, not return an empty corpus.
    import tempfile
    for name, setup in (("missing dir refuses", lambda d: os.path.join(d, "nope")),
                        ("empty dir refuses",   lambda d: d)):
        with tempfile.TemporaryDirectory() as d:
            try:
                read_shots(setup(d)); chk(name, "returned", "SystemExit")
            except SystemExit:
                chk(name, "SystemExit", "SystemExit")

    # ── --compare arms ───────────────────────────────────────────────────────────────────
    # Synthetic PNGs: a real header (the dim reader needs one) padded to a chosen size, so each
    # bucket is reached by construction rather than by finding a file that happens to fit.
    import struct, tempfile
    def png(path, w, h, size):
        head = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dIHDR" + struct.pack(">II", w, h)
        with open(path, "wb") as fh:
            fh.write(head + b"\x00" * max(0, size - len(head)))
    with tempfile.TemporaryDirectory() as d:
        old_d, new_d = os.path.join(d, "stored"), os.path.join(d, "fresh")
        os.makedirs(old_d); os.makedirs(new_d)
        png(os.path.join(old_d, "grew.png"),   1280, 720, 100_000)
        png(os.path.join(new_d, "grew.png"),   1280, 720, 200_000)   # +100% -> MOVED
        png(os.path.join(old_d, "steady.png"), 1280, 720, 100_000)
        png(os.path.join(new_d, "steady.png"), 1280, 720, 101_000)   # +1%   -> same
        png(os.path.join(old_d, "voided.png"), 1280, 720, 100_000)
        png(os.path.join(new_d, "voided.png"), 1280, 720, 7_700)     # the measured void size
        png(os.path.join(old_d, "resized.png"), 1280, 720, 100_000)
        png(os.path.join(new_d, "resized.png"), 1920, 1080, 100_000)
        png(os.path.join(old_d, "stored_only.png"), 1280, 720, 100_000)
        png(os.path.join(new_d, "fresh_only.png"),  1280, 720, 100_000)
        r = compare(old_d, new_d)
        names = lambda k: [x["shot"] for x in r[k]]
        chk("compare: a grown frame is MOVED",        names("moved"), ["grew"])
        chk("compare: a 1% frame is same",            names("same"), ["steady"])
        chk("compare: a void is VOID, not MOVED",     names("void"), ["voided"])
        chk("compare: …and a void is NOT counted moved", "voided" in names("moved"), False)
        chk("compare: a resize is DIM, not MOVED",    names("dim_mismatch"), ["resized"])
        chk("compare: …and a resize is NOT moved",    "resized" in names("moved"), False)
        chk("compare: stored-only is named",          r["only_stored"], ["stored_only"])
        chk("compare: fresh-only is named",           r["only_fresh"], ["fresh_only"])
        # the 5% boundary decides MOVED vs same, so pin both sides of it
        png(os.path.join(old_d, "edge.png"), 1280, 720, 100_000)
        png(os.path.join(new_d, "edge.png"), 1280, 720, 104_900)      # +4.9%
        chk("compare: 4.9% stays same",  "edge" in [x["shot"] for x in compare(old_d, new_d)["same"]], True)
        png(os.path.join(new_d, "edge.png"), 1280, 720, 105_000)      # +5.0%
        chk("compare: 5.0% becomes MOVED", "edge" in [x["shot"] for x in compare(old_d, new_d)["moved"]], True)
    # vacuity: a missing directory, and an empty FRESH run, must EXIT rather than report
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "a"))
        for name, args in (("compare: missing dir refuses", (os.path.join(d, "nope"), os.path.join(d, "a"))),
                           ("compare: empty fresh run refuses", (os.path.join(d, "a"), os.path.join(d, "a")))):
            try:
                compare(*args); chk(name, "returned", "SystemExit")
            except SystemExit:
                chk(name, "SystemExit", "SystemExit")

    print(f"\nselftest: {p} passed, {f} failed")
    return 1 if f else 0


if __name__ == "__main__":
    sys.exit(main())
