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

Usage:
    tools/store_shot_staleness.py --from <tag> --to <tag> [--shots DIR] [--json]
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
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
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

    print(f"\nselftest: {p} passed, {f} failed")
    return 1 if f else 0


if __name__ == "__main__":
    sys.exit(main())
