"""Append frames cut from a paid regen_s4_motion_frames raw to a T1 monster sheet, as a new animation. Spends nothing.
Each panel is cut whole (regen_s4_motion_frames.panel_masks), locked to the idle's palette, optionally mirrored so it faces
the way the idle does, and seated on the idle's ground line. A figure wider than a frame keeps its LEADING edge (the side the
idle faces: the weapon, the snout) and loses the trailing one (cape, tail), which is the cosmetic edge.
Refuses a sheet whose tier is not T1, and an animation name the sheet already has.

Usage: uv run python tools/append_motion_frames.py <monster> <anim> <raw.png> [--mirror 1] [--write]
       python3 tools/append_motion_frames.py --selftest
--selftest is in memory only: no file opened, nothing written."""
import json, sys
import numpy as np
from PIL import Image

sys.path.insert(0, "tools")
from regen_s4_motion_frames import panel_masks, CANVAS

MANIFEST = "data/sprite_manifest.json"


def faces_left(entry):
    """The manifest records the authored facing: flip_h is set on exactly the 256 px sheets authored facing LEFT (its
    flip_h_reason says so), and the rest face right. A pixel guess was tried and failed: a held sceptre outweighs the head."""
    return bool(entry.get("flip_h", False))


def cut(raw, idle, mirror=()):
    """Unclipped, palette-locked figures, one per panel; mirror holds the panel indexes to flip."""
    ia = np.array(idle)
    pal = np.unique(ia[ia[..., 3] >= 128][:, :3], axis=0).astype(int)
    raw = raw.convert("RGBA").resize(CANVAS, Image.LANCZOS) if raw.size != CANVAS else raw.convert("RGBA")
    full = np.array(raw.resize((512, 341), Image.BOX))
    figs = []
    for k, mask in enumerate(panel_masks(full[..., 3])):
        ys, xs = np.where(mask)
        fig = full[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
        fs = mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        rgb = fig[..., :3].astype(int).reshape(-1, 1, 3)
        fig[..., :3] = pal[np.argmin(((rgb - pal[None]) ** 2).sum(axis=2), axis=1)].reshape(fig.shape[0], fig.shape[1], 3)
        fig[..., 3] = np.where(fs, 255, 0)
        figs.append(fig[:, ::-1].copy() if k in mirror else fig)
    return figs


def seat(fig, idle, lead_left):
    """One 256x256 frame: bottom on the idle's ground line, centred on the idle's centre; wider than the frame keeps the lead."""
    ia = np.array(idle)
    ys, xs = np.where(ia[..., 3] >= 128)
    base, cx = int(ys.max()), int((xs.min() + xs.max()) // 2)
    h, w = fig.shape[:2]
    out = np.zeros((256, 256, 4), np.uint8)
    if w > 256:
        fig = fig[:, :256] if lead_left else fig[:, w - 256:]
        w = 256
        x0 = 0
    else:
        x0 = min(max(0, cx - w // 2), 256 - w)
    y0 = base - h + 1
    sy = max(0, -y0)
    out[max(0, y0):max(0, y0) + h - sy, x0:x0 + w] = fig[sy:, :]
    return out


def selftest():
    fails = []
    idle = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    idle.paste((40, 160, 40, 255), (98, 150, 158, 251))
    if not faces_left({"flip_h": True}) or faces_left({}):
        fails.append("facing is not read from flip_h (set = left, absent = right)")
    wide = np.zeros((100, 300, 4), np.uint8); wide[..., 3] = 255
    wide[:, :10, :3] = (255, 0, 0)                               # the lead: a red tip on the left
    wide[:, -10:, :3] = (0, 0, 255)                              # the trailing cape: blue on the right
    f = seat(wide, idle, lead_left=True)
    if not (f[..., 0] == 255).any():
        fails.append("a frame-wide lunge lost its leading tip")
    if (f[..., 2] == 255).any():
        fails.append("a frame-wide lunge kept its trailing edge instead of its lead")
    g = seat(wide[:, ::-1], idle, lead_left=False)
    if not (g[..., 0] == 255).any():
        fails.append("CONTROL: a right-leading lunge lost its tip")
    if int(np.where(f[..., 3] > 0)[0].max()) != 250:
        fails.append("the frame is not seated on the idle's ground line (row 250)")
    for m in fails:
        print("SELFTEST FAIL:", m)
    print("selftest:", "FAIL" if fails else "ok (facing read from flip_h; a wide lunge keeps its lead; seated on the ground line)")
    return 1 if fails else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    monster, anim, raw_path = sys.argv[1], sys.argv[2], sys.argv[3]
    mirror = {int(x) for x in sys.argv[sys.argv.index("--mirror") + 1].split(",")} if "--mirror" in sys.argv else set()
    man = json.load(open(MANIFEST))
    e = man["monster_sheets"][monster]
    if e.get("tier") != "T1":
        sys.exit(f"REFUSED {monster}: tier {e.get('tier')!r} is not T1; artist sheets are never regen targets")
    if anim in e["animations"]:
        sys.exit(f"REFUSED {monster}: it already has an {anim!r} animation")
    path = e["path"].replace("res://", "")
    sheet = Image.open(path).convert("RGBA")
    fw = e["frame_width"]; i0 = e["animations"]["idle"]["start"]
    idle = sheet.crop((i0 * fw, 0, (i0 + 1) * fw, e["frame_height"]))
    lead_left = faces_left(e)
    frames = [seat(f, idle, lead_left) for f in cut(Image.open(raw_path), idle, mirror)]
    n = sheet.width // fw
    print(json.dumps({"monster": monster, "anim": anim, "frames": [n, n + len(frames) - 1], "idle_faces_left": lead_left, "mirror": sorted(mirror)}))
    if "--write" in sys.argv:
        out = Image.new("RGBA", (sheet.width + fw * len(frames), sheet.height), (0, 0, 0, 0))
        out.alpha_composite(sheet, (0, 0))
        for k, f in enumerate(frames):
            out.alpha_composite(Image.fromarray(f), ((n + k) * fw, 0))
        out.save(path)
        print("wrote", path, out.size)
