#!/usr/bin/env python3
"""Judge a store re-shoot in PIXELS: which fresh frames really differ from the shipped ones.

    tools/store_shot_pixels.py STORED FRESH_A FRESH_B     per-shot verdicts, exit 0
    tools/store_shot_pixels.py --selftest

WHY THIS EXISTS
---------------
store_shot_staleness.py --compare judges by FILE SIZE. Bytes are a candidate, never a verdict:
measured 2026-11-04 on the real stored set, half of harmonia_village colour-inverted read as
"~noise~ NOT a finding" by bytes. The re-shoots at .748/.750/.752 were decided in pixels instead,
by a throwaway lane script hardcoded to the title frames (the audit instrument held to a lower
standard than the tool it audited). This is that measurement as a tool.

THE MEASURE: the share of pixels whose largest per-channel difference exceeds 24 levels (the
.748 re-shoot's threshold, which separates real content from PNG/dither jitter). FRESH_B is a
second capture of the SAME tree: FRESH_A vs FRESH_B is that shot's run-to-run noise (walkers,
twinkling stars, animation phase).

VERDICT, per shot present in all three dirs:
    MOVED   noise == 0 and delta > 0                a DETERMINISTIC change: two runs agree to the pixel,
                                                    so any difference from the stored frame is real
            noise > 0: delta >= 1.0% AND > 3 x noise  a change bigger than the shot's own animation
    NOISE   delta > 0 but inside that bound         the difference is the shot's own animation
    The 1% floor only makes sense where the shot MOVES between runs. Measured 2026-11-05 on the .770
    re-shoot (noise 0.00% on every shot): a hidden door sign changed 0.07-0.90% of a frame and the
    title's version label 0.01%, and the floor called all of them NOISE while the capture log named
    the cause of each.
    SAME    delta == 0
    SIZE    the frames differ in size               always reported, never silently skipped
A shot missing from any dir is listed as MISSING. MOVED says which frames to LOOK at, not which
is better: a fresh frame can be worse (measured 2026-09-13).
"""
import os
import sys

from PIL import Image, ImageChops

LEVEL = 24
MIN_MOVED = 0.01
NOISE_FACTOR = 3.0
## A NOISE verdict is promoted to MOVED when this share of the frame changed OUTSIDE the shot's own animation (the
## pixels where its two runs disagree, dilated by NOISE_GROW px). Measured on the .773 recheck: sandrift read NOISE
## (0.66% vs 0.35% run noise) yet 3714 px (0.40%) of its change lay outside the noise, and at .774 they were the
## villagers .773 had moved; battle and tavern (noise, 0 changed px) stay SAME. 0.05% leaves an 8x margin under it.
MIN_STABLE = 0.0005
NOISE_GROW = 9


def delta(a_path, b_path):
    """Share of pixels whose max channel difference exceeds LEVEL, or None when sizes differ."""
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if a.size != b.size:
        return None
    diff = ImageChops.difference(a, b)
    mx = ImageChops.lighter(ImageChops.lighter(diff.getchannel(0), diff.getchannel(1)), diff.getchannel(2))
    hist = mx.histogram()
    over = sum(hist[LEVEL + 1:])
    return over / (a.size[0] * a.size[1])


def where(a_path, b_path):
    """(pixel count over LEVEL, bbox (x0, y0, x1, y1) inclusive) of the change, or (0, None).

    A share says HOW MUCH moved, never WHERE. Measured on the .772 recheck: three frames read MOVED,
    and it took hand-made crops to learn that title_screen was 15 px in a 5x6 box at the corner (the
    version label), tavern_interior the fireplace flame's phase, harmonia_village the pond water.
    A villager, a sign and a label corner all read as one percentage; a box tells them apart."""
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if a.size != b.size:
        return 0, None
    diff = ImageChops.difference(a, b)
    mx = ImageChops.lighter(ImageChops.lighter(diff.getchannel(0), diff.getchannel(1)), diff.getchannel(2))
    mask = mx.point(lambda v: 255 if v > LEVEL else 0)
    bb = mask.getbbox()
    if bb is None:
        return 0, None
    return mask.histogram()[255], (bb[0], bb[1], bb[2] - 1, bb[3] - 1)


def fmt_where(count, bb):
    if not bb:
        return ""
    x0, y0, x1, y1 = bb
    return f"   {count} px in {x0},{y0}-{x1},{y1} ({x1 - x0 + 1}x{y1 - y0 + 1})"


def stable_change(fresh_a, stored, fresh_b):
    """Share of pixels that changed vs the stored frame OUTSIDE the shot's own animation (A vs B, dilated)."""
    from PIL import ImageFilter
    a = Image.open(fresh_a).convert("RGB")
    s = Image.open(stored).convert("RGB")
    b = Image.open(fresh_b).convert("RGB")
    if a.size != s.size or a.size != b.size:
        return None

    def mask(x, y):
        d = ImageChops.difference(x, y)
        m = ImageChops.lighter(ImageChops.lighter(d.getchannel(0), d.getchannel(1)), d.getchannel(2))
        return m.point(lambda v: 255 if v > LEVEL else 0)

    moving = mask(a, b).filter(ImageFilter.MaxFilter(NOISE_GROW))
    outside = ImageChops.multiply(mask(a, s), ImageChops.invert(moving))
    return outside.histogram()[255] / (a.size[0] * a.size[1])


def verdict(d, noise, stable=None):
    if d is None or noise is None:
        return "SIZE"
    if d == 0:
        return "SAME"
    if noise == 0:
        return "MOVED"
    if d >= MIN_MOVED and d > NOISE_FACTOR * noise:
        return "MOVED"
    if stable is not None and stable >= MIN_STABLE:
        return "MOVED"   # the change sits where the shot does NOT animate, so its run noise cannot explain it
    return "NOISE"


def judge(stored, fa, fb):
    names = sorted({f[:-4] for d in (stored, fa, fb) if os.path.isdir(d) for f in os.listdir(d) if f.endswith(".png")})
    rows = []
    for n in names:
        paths = [os.path.join(d, n + ".png") for d in (stored, fa, fb)]
        if not all(os.path.isfile(p) for p in paths):
            rows.append((n, "MISSING", None, None))
            continue
        d = delta(paths[1], paths[0])
        noise = delta(paths[1], paths[2])
        st = stable_change(paths[1], paths[0], paths[2]) if (d and noise) else None
        rows.append((n, verdict(d, noise, st), d, noise))
    return rows


def fmt(x):
    return "   n/a" if x is None else f"{x:7.2%}"


def main(argv):
    if len(argv) != 3:
        print(__doc__.split("WHY")[0].strip(), file=sys.stderr)
        return 2
    stored, fa, fb = argv
    for d in (stored, fa, fb):
        if not os.path.isdir(d):
            print(f"[pixels] BLOCKED: no such directory {d}", file=sys.stderr)
            return 2
    rows = judge(stored, fa, fb)
    if not rows:
        print(f"[pixels] BLOCKED: no .png in any of the three dirs: a check over nothing passes everything", file=sys.stderr)
        return 2
    print(f"[pixels] {len(rows)} shot(s) · share of pixels over {LEVEL} levels · MOVED = any change when noise is 0, else >= {MIN_MOVED:.0%} and > {NOISE_FACTOR:g}x noise")
    for n, v, d, noise in rows:
        loc = fmt_where(*where(os.path.join(fa, n + ".png"), os.path.join(stored, n + ".png"))) if v in ("MOVED", "NOISE") else ""
        print(f"  {v:<7} {n:<30} vs stored {fmt(d)}   noise a/b {fmt(noise)}{loc}")
    counts = {}
    for _, v, _, _ in rows:
        counts[v] = counts.get(v, 0) + 1
    print("[pixels] " + " · ".join(f"{k} {counts[k]}" for k in ("MOVED", "NOISE", "SAME", "SIZE", "MISSING") if k in counts))
    return 0


def selftest():
    import tempfile
    fails = 0
    ran = 0
    t = tempfile.mkdtemp(prefix="pixels_selftest.", dir=os.path.join(os.getcwd(), "tmp") if os.path.isdir("tmp") else None)
    S, A, B = (os.path.join(t, x) for x in ("stored", "a", "b"))
    for d in (S, A, B):
        os.makedirs(d)
    base = Image.new("RGB", (100, 100), (40, 80, 120))

    def put(d, name, img):
        img.save(os.path.join(d, name + ".png"))

    def patch(img, box, colour):
        im = img.copy()
        im.paste(colour, box)
        return im

    # same: identical everywhere
    for d in (S, A, B):
        put(d, "same", base)
    # moved: a 30% block changed in BOTH fresh runs, which agree with each other
    moved = patch(base, (0, 0, 100, 30), (250, 250, 250))
    put(S, "moved", base); put(A, "moved", moved); put(B, "moved", moved)
    # noise: the two fresh runs disagree as much as fresh disagrees with stored (an animating shot)
    put(S, "noisy", base); put(A, "noisy", patch(base, (0, 0, 100, 20), (250, 0, 0))); put(B, "noisy", patch(base, (0, 50, 100, 70), (250, 0, 0)))
    # jitter: every pixel off by 10 levels (under LEVEL) -> SAME
    put(S, "jitter", base); put(A, "jitter", Image.new("RGB", (100, 100), (50, 90, 130))); put(B, "jitter", Image.new("RGB", (100, 100), (50, 90, 130)))
    # tiny, DETERMINISTIC: 0.5% changed, identical in both runs (noise 0) -> MOVED. The door-sign case.
    tiny = patch(base, (0, 0, 50, 1), (250, 250, 250))
    put(S, "tiny", base); put(A, "tiny", tiny); put(B, "tiny", tiny)
    # tiny, the runs disagree ELSEWHERE: 0.5% changed identically in both runs, the animation is a far-off row -> the
    # change sits outside the animation -> MOVED. This arm read NOISE until .775: the 1% floor excused it, and that is
    # how sandrift's moved villagers read NOISE at .773 (its water animated, the villagers did not).
    put(S, "tinynoisy", base); put(A, "tinynoisy", tiny); put(B, "tinynoisy", patch(tiny, (0, 99, 30, 100), (0, 250, 0)))
    # the change sits INSIDE the animation: both runs change the same strip, differently -> the noise explains it -> NOISE
    put(S, "animoverlap", base); put(A, "animoverlap", patch(base, (0, 0, 50, 2), (250, 0, 0))); put(B, "animoverlap", patch(base, (0, 0, 50, 2), (0, 250, 0)))
    # size: a resized capture
    put(S, "resized", base); put(A, "resized", Image.new("RGB", (100, 90), (40, 80, 120))); put(B, "resized", Image.new("RGB", (100, 90), (40, 80, 120)))
    # missing from one run
    put(S, "gone", base); put(A, "gone", base)

    got = {n: (v, d) for n, v, d, _ in judge(S, A, B)}
    want = {"same": "SAME", "moved": "MOVED", "noisy": "NOISE", "jitter": "SAME", "tiny": "MOVED", "tinynoisy": "MOVED", "animoverlap": "NOISE", "resized": "SIZE", "gone": "MISSING"}
    for n, w in want.items():
        v = got.get(n, ("absent", None))[0]
        ok = v == w
        fails += 0 if ok else 1; ran += 1
        print(f"  {'ok  ' if ok else 'FAIL'}  {n:<8} -> {v:<7} (want {w})")
    d = got["moved"][1]
    ok = d is not None and abs(d - 0.30) < 1e-9
    fails += 0 if ok else 1; ran += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  the moved block measures exactly 30.00% (got {fmt(d)})")
    # WHERE: the box and count, exact on fixtures whose geometry is known
    for name, want_w, label in (("moved", (3000, (0, 0, 99, 29)), "the moved block is located: 3000 px in 0,0-99,29"),
                                ("tiny", (50, (0, 0, 49, 0)), "a one-row strip is located: 50 px in 0,0-49,0"),
                                ("same", (0, None), "an identical frame has no box")):
        got_w = where(os.path.join(A, name + ".png"), os.path.join(S, name + ".png"))
        ok = got_w == want_w
        fails += 0 if ok else 1; ran += 1
        print(f"  {'ok  ' if ok else 'FAIL'}  {label} (got {got_w})")
    import io, contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main([S, A, B])
    lines = {ln.split()[1]: ln for ln in buf.getvalue().splitlines() if ln.startswith("  ") and len(ln.split()) > 1}
    ok = "3000 px in 0,0-99,29 (100x30)" in lines.get("moved", "") and " px in " not in lines.get("same", "x px in ")
    fails += 0 if ok else 1; ran += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  the report prints the box on a MOVED row and none on a SAME row")
    rc = main([S, A, os.path.join(t, "nowhere")])
    ok = rc == 2
    fails += 0 if ok else 1; ran += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  a missing directory BLOCKS (exit {rc})")
    empty = os.path.join(t, "empty")
    os.makedirs(empty)
    rc = main([empty, empty, empty])
    ok = rc == 2
    fails += 0 if ok else 1; ran += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  three empty dirs BLOCK, never 'all same' (exit {rc})")
    import shutil
    shutil.rmtree(t, ignore_errors=True)
    print(f"\nselftest: {ran - fails} passed, {fails} failed ({ran} checks ran)")
    return 1 if fails else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
