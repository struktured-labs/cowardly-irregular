"""Regenerate one motion strip (attack / hit / dead / idle) for a T1 legacy monster sheet with an image-edit model. NOT shipped art:
output lands in tmp/gpt2_trial/out/ for an eye check, and nothing here touches assets/ or the manifest.
(struktured via grokbot 23752: the S4 regen, $100 total cap; tools/regen_s4_motion_batch.py enforces the cap and the tier refusal.)

The model draws a 2-panel canvas: the idle (x3) in each 768x1024 half, redrawn as two poses. normalise() turns that into two
256x256 frames on the idle's scale, palette and ground line.

A STRIKE CROSSES THE MIDDLE. A left-facing creature lunging left pushes its weapon or snout over x=768 into the wind-up panel.
Cutting at x=768 sheared that leading edge off the strike frame and left it as a "speck" in the wind-up frame, whose bbox it
widened, so the wind-up figure was also placed off-centre (13 of 83 batch-1 strips; the troll's axe head looked detached).
So each connected piece goes, whole, to the panel holding its centroid; the seam is never a cut.

Usage: uv run python tools/regen_s4_motion_frames.py <monster> <anim> [--quality medium] [--model M] [--dry]
       python3 tools/regen_s4_motion_frames.py --selftest
--selftest reaches numpy, PIL and scipy in memory only: no file opened, no directory walked, no subprocess, no network, nothing written."""
import base64, io, json, sys, time
import numpy as np
from PIL import Image
from scipy import ndimage

MODEL = "gpt-image-2.6-sunburst"   # struktured via grokbot 23750: gpt-image-2 was deprecated 2026-11-10
OUT = "tmp/gpt2_trial/out"
CANVAS = (1536, 1024)   # two 768x1024 panels, the idle drawn at x3 (768 px) in each, feet on one line
POSES = {
    "attack": ("ATTACKING", "LEFT panel: the wind-up, body coiled back, about to strike, still facing the same way as the reference. RIGHT panel: the strike at full extension, lunging FORWARD in the direction the reference creature faces, toward the side its face and chest point to; it never turns around."),
    "hit": ("TAKING A HIT", "LEFT panel: recoiling from a blow, flinching backward, eyes shut. RIGHT panel: staggered further back, off balance, still on its feet."),
    "idle": ("STANDING IDLE, breathing", "LEFT panel: exactly the reference pose, unchanged. RIGHT panel: the same pose one breath later: chest and shoulders risen by a pixel or two, nothing else moved."),
    "dead": ("DEFEATED", "LEFT panel: collapsing, knees buckling, halfway down. RIGHT panel: lying defeated on the ground, still, eyes closed."),
}
DESC = {
    "unassuming_dog": "a friendly-looking orange shiba-like dog with a white chest and collar, standing on four legs",
    "troll": "a hulking green troll with a small axe, tusks, and a brown loincloth",
    "cave_rat_king": "a grey rat king standing upright in a black cape and gold crown, holding a gold sceptre",
}
PROMPT = """This is a 2-frame sprite strip for a 16-bit JRPG enemy: {desc}. The reference image shows the SAME creature's idle pose twice, once in each half.
Redraw it as a 2-frame animation of the creature {verb}. {poses}
HARD RULES: it is the SAME individual creature in both panels as the reference: same species, same colours and palette, same markings, same outfit and props, same body proportions, same size on the canvas, facing the SAME direction as the reference. Feet (or the body's lowest point) rest on the same ground line as the reference in both panels. Exactly 2 figures, one centred in each half, nothing crossing the middle. Fully transparent background, no ground, no shadow, no floor, no text, no border, no effects outside the body. Crisp 16-bit pixel art with hard pixel clusters and a dark outline, no anti-aliasing blur, no gradients."""


def idle_frame(monster):
    m = json.load(open("data/sprite_manifest.json"))["monster_sheets"][monster]
    im = Image.open(m["path"].replace("res://", "")).convert("RGBA")
    fw = m["frame_width"]; i = m["animations"]["idle"]["start"]
    return im.crop((i * fw, 0, (i + 1) * fw, m["frame_height"]))


def reference(idle):
    big = idle.resize((768, 768), Image.NEAREST)
    c = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    for k in range(2):
        c.alpha_composite(big, (k * 768, 128))
    return c


def panel_masks(alpha):
    """alpha: the x1/3 canvas's alpha (341x512). Returns one bool mask per panel; every solid piece goes whole to the panel
    holding its centroid, so a piece crossing x=256 is never split."""
    solid = alpha >= 128
    lab, n = ndimage.label(solid, ndimage.generate_binary_structure(2, 2))
    if n == 0:
        return [solid & False, solid & False]
    cx = np.asarray(ndimage.center_of_mass(solid, lab, range(1, n + 1)))[:, 1]
    owner = np.concatenate([[-1], (cx >= alpha.shape[1] / 2).astype(int)])
    return [owner[lab] == k for k in range(2)]


def normalise(raw, idle):
    """Split the 2 panels by piece ownership, snap alpha, shrink x1/3 on the idle's scale, lock to the idle palette, anchor bottom-centre on the idle's feet."""
    ia = np.array(idle); ys, xs = np.where(ia[..., 3] >= 128)
    base, cx = int(ys.max()), int((xs.min() + xs.max()) // 2)
    pal = np.unique(ia[ia[..., 3] >= 128][:, :3], axis=0).astype(int)
    raw = raw.convert("RGBA").resize(CANVAS, Image.LANCZOS) if raw.size != CANVAS else raw.convert("RGBA")
    full = np.array(raw.resize((512, 341), Image.BOX))   # the same x1/3 each panel had, taken across the whole canvas
    frames = []
    for mask in panel_masks(full[..., 3]):
        out = np.zeros((256, 256, 4), np.uint8)
        if mask.sum() > 30:
            ys, xs = np.where(mask)
            fig = full[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
            fs = mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
            rgb = fig[..., :3].astype(int).reshape(-1, 1, 3)
            near = pal[np.argmin(((rgb - pal[None]) ** 2).sum(axis=2), axis=1)].reshape(fig.shape[0], fig.shape[1], 3)
            fig[..., :3] = near; fig[..., 3] = np.where(fs, 255, 0)
            h, w = fig.shape[:2]
            y0 = base - h + 1; x0 = cx - w // 2
            sy0, sx0 = max(0, -y0), max(0, -x0); y0, x0 = max(0, y0), max(0, x0)
            hh, ww = min(h - sy0, 256 - y0), min(w - sx0, 256 - x0)
            out[y0:y0 + hh, x0:x0 + ww] = fig[sy0:sy0 + hh, sx0:sx0 + ww]
        frames.append(Image.fromarray(out))
    return frames


def grade(frames, idle):
    i = np.array(idle)[..., 3] >= 128
    res = []
    for f in frames:
        a = np.array(f)[..., 3] >= 128
        res.append({"overlap": round(float((a & i).sum() / max((a | i).sum(), 1)), 3), "area_ratio": round(float(a.sum() / max(i.sum(), 1)), 2)})
    return res


def _width(frame):
    xs = np.where((np.array(frame)[..., 3] >= 128).any(axis=0))[0]
    return int(xs.max() - xs.min() + 1) if len(xs) else 0


def selftest():
    """In memory only. A synthetic strike whose arm crosses the seam must stay whole in the strike frame and leave the wind-up alone."""
    idle = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    idle.paste((40, 160, 40, 255), (98, 150, 158, 251))
    def canvas(arm):
        c = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        c.paste((40, 160, 40, 255), (300, 400, 480, 1000))      # wind-up: 180 px wide, inside the left panel
        c.paste((40, 160, 40, 255), (900, 400, 1260, 1000))     # strike body: 360 px wide
        if arm:
            c.paste((40, 160, 40, 255), (660, 520, 900, 580))   # strike arm, connected to the body, 108 px over the seam
        return c
    fails = []
    wind, strike = normalise(canvas(True), idle)
    if _width(strike) != (1260 - 660) // 3:
        fails.append(f"the strike frame lost what crossed the seam: width {_width(strike)}, expected {(1260 - 660) // 3}")
    if _width(wind) != 180 // 3:
        fails.append(f"the wind-up frame picked up the strike's arm: width {_width(wind)}, expected {180 // 3}")
    c_wind, c_strike = normalise(canvas(False), idle)   # CONTROL: nothing crosses; both frames are the plain blocks
    if (_width(c_wind), _width(c_strike)) != (60, 120):
        fails.append(f"CONTROL: with nothing crossing, widths are {(_width(c_wind), _width(c_strike))}, expected (60, 120)")
    lone = canvas(False); lone.paste((40, 160, 40, 255), (700, 700, 730, 730))   # a separate piece left of the seam stays left
    if _width(normalise(lone, idle)[1]) != 120:
        fails.append("a separate piece on the left of the seam was given to the strike frame")
    for f in fails:
        print("SELFTEST FAIL:", f)
    print("selftest:", "FAIL" if fails else "ok (seam-crossing strike kept whole; control; a lone piece stays in its panel)")
    return 1 if fails else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    monster, anim = sys.argv[1], sys.argv[2]
    quality = sys.argv[sys.argv.index("--quality") + 1] if "--quality" in sys.argv else "medium"
    model = sys.argv[sys.argv.index("--model") + 1] if "--model" in sys.argv else MODEL
    tag = f"{monster}__{anim}__{int(time.time())}"
    idle = idle_frame(monster)
    if "--dry" in sys.argv:   # no API call: the reference canvas stands in for the model's answer, to test the code path
        frames = normalise(reference(idle), idle)
        print(json.dumps({"dry": True, "grade": grade(frames, idle)})); sys.exit(0)
    from openai import OpenAI   # late, so the selftest and --dry need no key and no package
    buf = io.BytesIO(); reference(idle).save(buf, "PNG"); buf.seek(0); buf.name = "reference.png"
    verb, poses = POSES[anim]
    desc = DESC.get(monster) or "{name}: {description}".format(**json.load(open("data/monsters.json"))[monster])
    t0 = time.time()
    resp = OpenAI().images.edit(model=model, image=buf, prompt=PROMPT.format(desc=desc, verb=verb, poses=poses),
                                size="1536x1024", quality=quality, background="transparent", output_format="png", n=1)
    dt = time.time() - t0
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
    raw.save(f"{OUT}/{tag}__raw.png")
    frames = normalise(raw, idle)
    strip = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    for k, f in enumerate(frames): strip.alpha_composite(f, (k * 256, 0))
    strip.save(f"{OUT}/{tag}__strip.png")
    usage = resp.usage.model_dump() if getattr(resp, "usage", None) else None
    rec = {"tag": tag, "model": model, "monster": monster, "anim": anim, "quality": quality, "seconds": round(dt, 1), "usage": usage, "grade": grade(frames, idle), "raw_mode": raw.mode, "raw_size": raw.size}
    open(f"{OUT}/calls.jsonl", "a").write(json.dumps(rec) + "\n")
    print(json.dumps(rec))
