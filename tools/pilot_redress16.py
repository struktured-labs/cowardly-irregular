#!/usr/bin/env python3
"""PILOT: re-dress the artist's own 16 walk frames, with no animate step.

Third approach to the overworld walk grid. The first two failed on the same axis:

  animate-with-text from the world BATTLE idle   441/440/459/445   no directions at all
  animate-with-text from the overworld chibi    2265/2266/2265/2265  one pose x4
  redress-then-animate                          1850/1598/1666/2354  geometry OK, art
                                                                     hallucinated wings

The third attempt's premise: the artist's overworld.png ALREADY contains a correct
16-frame, 4-direction walk cycle. If bitforge preserves pose from init_image, then
re-dressing each of those 16 frames changes only the clothes and keeps a human-authored
animation — and there is no animate step left to hallucinate.

The risk this pilot exists to measure is FLICKER: 16 independent generations may not agree
on the costume frame to frame, which a 4-frame walk loop would show as strobing.
"""
import base64
import io
import importlib.util
import os
import sys
from pathlib import Path

import httpx
from PIL import Image

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("_gw", HERE / "gen_world_job_sprites.py")
gw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gw)

JOB, WORLD = "fighter", "suburban"
J = gw.GAME_REPO / "assets" / "sprites" / "jobs" / JOB
DIRS = ["south", "west", "east", "north"]
OUT = HERE.parent / "tmp" / "review" / "redress16.png"


def b64(img):
    b = io.BytesIO()
    img.save(b, format="PNG")
    return base64.b64encode(b.getvalue()).decode()


def main():
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        print("ERROR: PIXELLAB_API_KEY not set", file=sys.stderr)
        return 1

    style = (Image.open(J / f"idle_{WORLD}.png").convert("RGBA")
             .crop((0, 0, 256, 256)).resize((64, 64), Image.LANCZOS))
    desc = (f"{gw.JOB_CORE[JOB]} RE-DRESSED in {gw.WORLD_DRESS[WORLD]} "
            f"Garments in {gw.JOB_SIGNATURE[JOB]}. Keep the reference pose and chibi "
            f"proportions EXACTLY; change ONLY the clothing.")
    src = Image.open(J / "overworld.png").convert("RGBA")
    grid = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    total, fails = 0.0, 0

    with httpx.Client(timeout=180) as c:
        for r in range(4):
            for col in range(4):
                frame = (src.crop((col * 32, r * 32, col * 32 + 32, r * 32 + 32))
                         .resize((64, 64), Image.LANCZOS))
                try:
                    resp = c.post("https://api.pixellab.ai/v1/generate-image-bitforge",
                        headers={"Authorization": f"Bearer {key}"}, json={
                            "description": desc,
                            "image_size": {"width": 64, "height": 64},
                            "init_image": {"type": "base64", "base64": b64(frame)},
                            "init_image_strength": 400,
                            "style_image": {"type": "base64", "base64": b64(style)},
                            "style_strength": 40,
                            "direction": DIRS[r], "view": "low top-down",
                            "no_background": True, "seed": 42})
                    resp.raise_for_status()
                    d = resp.json()
                    img = Image.open(io.BytesIO(
                        base64.b64decode(d["image"]["base64"]))).convert("RGBA")
                    total += float(d.get("usage", {}).get("usd", 0))
                    grid.paste(img.resize((32, 32), Image.NEAREST), (col * 32, r * 32))
                except Exception as e:
                    fails += 1
                    print(f"  r{r}c{col} FAILED: {e}", flush=True)
            print(f"  row {DIRS[r]} done (${total:.3f})", flush=True)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    grid.save(OUT)
    a = grid.split()[3]
    rows = [sum(1 for q in a.crop((0, r * 32, 128, r * 32 + 32)).get_flattened_data() if q > 40)
            for r in range(4)]
    print(f"\n16-frame redress: {16-fails}/16 frames, ${total:.3f}")
    print(f"row opaque: {rows}")
    print(f"artist base: [2050, 1414, 1414, 2130]")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
