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
    --compare          the only check that sees a FRAME -- authoritative only once its
                       signal is shown to beat its own noise, which needs two captures

⛔ 2026-09-13 — ONE CAPTURE IS NOT ENOUGH, AND EVERY FINDING ABOVE WAS TAKEN FROM ONE.
Captured v3.33.345-alpha twice, same commit, same protocol. `tavern_interior` differed by
6.82% BETWEEN THE TWO RUNS -- MOVED on one, "same" on the other -- because villages and
interiors spawn wandering NPCs and marketing_shots.gd waits a fixed frame count. The 5%
threshold sits below that. Ten of eleven shots stay under 1.5% (median 1.04%), so the noise
is usually invisible and has a tail that clears the bar on its own.

Pass a SECOND fresh directory and the swing is measured per shot instead of assumed: a delta
must beat its own shot's swing by NOISE_MARGIN to count, and one that cannot lands in a
`~noise~` bucket that says so. With one directory the old behaviour is unchanged and the
footer says which threshold the answer rests on.

⛔ AND A STABLE MOVED IS STILL NOT A VERDICT. Of the three that survived both captures, the
`battle` frame was WORSE than the one it would have replaced -- two speech bubbles overlapping
each other and the action menu, text illegible, because the capture lands mid-dialogue. Bytes
grew because the frame gained clutter. Growth is not improvement; look at the image.

Usage:
    tools/store_shot_staleness.py --from <tag> --to <tag> [--shots DIR] [--json]
    tools/store_shot_staleness.py --compare <stored DIR> <fresh DIR> [FRESH2 DIR] [--json]
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

# A byte delta this large is worth a LOOK. It is not a claim that the frame changed --
# see NOISE_MARGIN, which is what stops that number being believed on its own.
MOVED_PCT = 5.0

# ⛔ 5% IS BELOW THIS CAPTURE'S OWN NOISE FLOOR. Two captures of the IDENTICAL commit,
# identical protocol, measured 2026-09-13 at v3.33.345-alpha:
#
#     tavern_interior   6.82%   <-- MOVED on one run, "same" on the other
#     eldertree 1.48 · ironhaven 1.38 · inn 1.34 · battle 1.16 · frosthold 1.04
#     sandrift 0.87 · harmonia 0.34 · grimhollow 0.21 · whispering_cave 0.02 · shop 0.00
#     median 1.04%
#
# Villages and interiors spawn wandering NPCs and marketing_shots.gd waits a fixed frame
# count, so the frame itself differs run to run. Ten of eleven stay under 1.5% and one
# clears the threshold on noise alone -- so a single capture can manufacture a MOVED.
# Pass a SECOND fresh directory and the noise is measured per shot instead of assumed:
# a delta must beat its own shot's run-to-run swing by this factor to count.
NOISE_MARGIN = 2.0


def _png_dim(path):
    with open(path, "rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    import struct
    return struct.unpack(">II", head[16:24])


def compare(stored_dir, fresh_dir, fresh_dir2=None):
    """Byte-and-dimension diff between the shipped set and a fresh capture run.

    Reports the two failures a size diff can actually see: a capture that photographed a void,
    and a frame whose bytes moved even though its script did not. It does NOT judge whether a
    change is an improvement -- that needs an eye, and the caption file records which shot
    leads and why.
    """
    for d in (stored_dir, fresh_dir) + ((fresh_dir2,) if fresh_dir2 else ()):
        if not os.path.isdir(d):
            sys.exit(f"BLOCKED: no directory at {d!r}. Refusing to report a comparison over a "
                     f"directory that does not exist.")
    stored = {os.path.splitext(f)[0] for f in os.listdir(stored_dir) if f.endswith(".png")}
    fresh = {os.path.splitext(f)[0] for f in os.listdir(fresh_dir) if f.endswith(".png")}
    if not fresh:
        sys.exit(f"BLOCKED: {fresh_dir!r} holds no .png -- an empty capture run reports every "
                 f"stored shot as missing, which is not a finding about the shots.")
    out = {"moved": [], "noise": [], "same": [], "void": [], "dim_mismatch": [],
           "only_stored": sorted(stored - fresh), "only_fresh": sorted(fresh - stored),
           "noise_measured": bool(fresh_dir2)}
    for name in sorted(stored & fresh):
        sp = os.path.join(stored_dir, name + ".png")
        fp = os.path.join(fresh_dir, name + ".png")
        sb, fb = os.path.getsize(sp), os.path.getsize(fp)
        sd, fd = _png_dim(sp), _png_dim(fp)
        # Run-to-run swing for THIS shot, if a second capture was supplied. A shot missing
        # from the second run gets None, and is judged on the bare threshold -- flagged, so
        # the report never implies a noise check that did not happen.
        noise_pct = None
        if fresh_dir2 is not None:
            fp2 = os.path.join(fresh_dir2, name + ".png")
            if os.path.isfile(fp2):
                fb2 = os.path.getsize(fp2)
                noise_pct = round(abs(fb2 - fb) / fb * 100.0, 2) if fb else None
        row = {"shot": name, "stored_bytes": sb, "fresh_bytes": fb,
               "pct": round((fb - sb) / sb * 100.0, 1) if sb else None,
               "stored_dim": sd, "fresh_dim": fd, "noise_pct": noise_pct}
        delta = abs(fb - sb) / sb * 100.0 if sb else 0.0
        # The bar is the threshold OR this shot's own measured swing, whichever is higher.
        bar = MOVED_PCT if noise_pct is None else max(MOVED_PCT, noise_pct * NOISE_MARGIN)
        row["bar_pct"] = round(bar, 2)
        if fb < VOID_BYTES:
            out["void"].append(row)          # a void is not a "change", it is a failed capture
        elif sd != fd:
            out["dim_mismatch"].append(row)  # different subject, not a comparable frame
        elif delta >= bar:
            out["moved"].append(row)
        elif delta >= MOVED_PCT:
            # Big enough to have been called MOVED on one capture, not big enough to
            # separate from this shot's own run-to-run swing. This is the bucket the
            # single-capture version could not express, and tavern_interior lived in it.
            out["noise"].append(row)
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
    ap.add_argument("--compare", nargs="+", metavar="DIR",
                    help="STORED FRESH [FRESH2]. A second fresh capture measures this "
                         "capture's own run-to-run noise per shot, which the MOVED "
                         "threshold alone sits below.")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.compare:
        if not 2 <= len(args.compare) <= 3:
            sys.exit("usage: --compare STORED FRESH [FRESH2]")
        res = compare(*args.compare)
        if args.json:
            print(json.dumps(res, indent=2)); return 0
        n = sum(len(res[k]) for k in ("moved", "noise", "same", "void", "dim_mismatch"))
        print(f"[shots] {n} comparable · stored {args.compare[0]} · fresh {args.compare[1]}")
        for r in res["void"]:
            print(f"  ⛔ VOID      {r['shot']:<26} fresh {r['fresh_bytes']:,} B < {VOID_BYTES:,} "
                  f"— the CAPTURE failed, this is not a frame change")
        for r in res["dim_mismatch"]:
            print(f"  ⛔ DIM       {r['shot']:<26} stored {r['stored_dim']} vs fresh {r['fresh_dim']} "
                  f"— different subject, not a comparable frame")
        for r in res["moved"]:
            band = "" if r["noise_pct"] is None else f"  [swing {r['noise_pct']:.2f}%, bar {r['bar_pct']:.2f}%]"
            print(f"  MOVED       {r['shot']:<26} {r['stored_bytes']:>9,} -> {r['fresh_bytes']:>9,} B "
                  f"({r['pct']:+.1f}%){band}")
        for r in res["noise"]:
            print(f"  ~noise~     {r['shot']:<26} {r['stored_bytes']:>9,} -> {r['fresh_bytes']:>9,} B "
                  f"({r['pct']:+.1f}%)  NOT a finding: this shot swings {r['noise_pct']:.2f}% "
                  f"between two captures of the SAME tree")
        for r in res["same"]:
            print(f"  same        {r['shot']:<26} {r['stored_bytes']:>9,} -> {r['fresh_bytes']:>9,} B "
                  f"({r['pct']:+.1f}%)")
        for k in ("only_stored", "only_fresh"):
            for name in res[k]:
                print(f"  {k:<11} {name}")
        print(f"[shots] MOVED is a re-shoot CANDIDATE, not a verdict — bytes cannot say which "
              f"frame is better. Measured 2026-09-13: of three stable MOVEDs, one fresh frame "
              f"was WORSE than the one it would have replaced.")
        if not res["noise_measured"]:
            print(f"[shots] ⚠ ONE capture only, so every MOVED here rests on the bare {MOVED_PCT:.0f}% "
                  f"threshold — and this capture's noise floor was measured at 6.82% on one shot. "
                  f"Pass a second fresh directory to separate signal from NPC wander.")
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

    # ── noise arms: a second fresh capture must be able to REFUSE a MOVED ────────────────
    # These encode the defect that made them necessary: tavern_interior swung 6.82% between
    # two captures of the same commit, clearing a 5% threshold on nothing but NPC wander.
    saw_noise = saw_moved_over_noise = False
    with tempfile.TemporaryDirectory() as d:
        st, f1, f2 = (os.path.join(d, x) for x in ("stored", "fresh1", "fresh2"))
        for x in (st, f1, f2):
            os.makedirs(x)
        # tavern-shaped: +6% against stored, but the two captures differ by 6.82%
        png(os.path.join(st, "tavern.png"), 1280, 720, 100_000)
        png(os.path.join(f1, "tavern.png"), 1280, 720, 106_000)
        png(os.path.join(f2, "tavern.png"), 1280, 720, 113_229)      # 6.82% off fresh1
        # whispering-shaped: a huge real move, with a quiet shot
        png(os.path.join(st, "cave.png"), 1280, 720, 100_000)
        png(os.path.join(f1, "cave.png"), 1280, 720, 350_000)
        png(os.path.join(f2, "cave.png"), 1280, 720, 350_070)        # 0.02% off fresh1
        # present in fresh1, ABSENT from fresh2: no noise data, must not pretend otherwise
        png(os.path.join(st, "lonely.png"), 1280, 720, 100_000)
        png(os.path.join(f1, "lonely.png"), 1280, 720, 120_000)

        one = compare(st, f1)
        chk("noise: ONE capture calls tavern MOVED (the defect)",
            "tavern" in [x["shot"] for x in one["moved"]], True)
        chk("noise: one capture reports noise_measured False", one["noise_measured"], False)

        two = compare(st, f1, f2)
        mv = [x["shot"] for x in two["moved"]]
        nz = [x["shot"] for x in two["noise"]]
        chk("noise: TWO captures move tavern out of MOVED", "tavern" in mv, False)
        chk("noise: …and into the noise bucket",            nz, ["tavern"])
        chk("noise: a real move survives the noise check",  "cave" in mv, True)
        chk("noise: a shot missing from run 2 still judged", "lonely" in mv, True)
        chk("noise: …and is flagged as unmeasured",
            [x["noise_pct"] for x in two["moved"] if x["shot"] == "lonely"], [None])
        chk("noise: the bar is raised above the swing",
            [x["bar_pct"] for x in two["noise"]], [round(6.82 * NOISE_MARGIN, 2)])
        chk("noise: two captures report noise_measured True", two["noise_measured"], True)
        saw_noise = bool(nz)
        saw_moved_over_noise = "cave" in mv

        # direction control: shrink the swing and tavern must come BACK as MOVED, or the
        # noise bucket is just swallowing everything.
        png(os.path.join(f2, "tavern.png"), 1280, 720, 106_050)      # 0.05% swing
        back = [x["shot"] for x in compare(st, f1, f2)["moved"]]
        chk("noise: a QUIET shot at the same delta is MOVED again", "tavern" in back, True)

    if not (saw_noise and saw_moved_over_noise):
        print(f"  FAIL  noise arms vacuous: noise bucket seen={saw_noise}, "
              f"moved-over-noise seen={saw_moved_over_noise}; both required")
        f += 1

    print(f"\nselftest: {p} passed, {f} failed")
    return 1 if f else 0


if __name__ == "__main__":
    sys.exit(main())
