#!/usr/bin/env python3
"""Draw the large keyed art a full-screen summon moment shows (T1), for the spectacle pass.

struktured 2026-11-01 (relayed, cowir-main 21004): "I want more flash. especially ridiculous summons ... animations
are clutch." The player's summons had no art at all, so the sequence had nothing to bring on screen. Each SPLASH is
one large still on a transparent background; the battle sequence owns the motion (rise, scale, shake, fade).

gpt-image-2 answers on a flat magenta backdrop, which is keyed out by border flood (gen_village_buildings.key_out),
cropped to the art and scaled to HEIGHT px. A splash that is a figure from the game takes its sheet's first idle frame
as a reference, so the summoned figure is the same person. Staged under tmp/summon_splash/; --deploy copies into
assets/sprites/effects/summons/. Every file here is T1; never point this at an artist file.

The four elemental summons are deliberately absent: their names were Final Fantasy's, and cowir-main 21010 ruled
they are renamed and redrawn as ORIGINAL designs once cowir-story settles the names.

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_summon_splash.py recursive_summoner summon_circle
    uv run python tools/gen_summon_splash.py --deploy recursive_summoner summon_circle
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_village_buildings import key_out  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/summon_splash"
OUT = ROOT / "assets/sprites/effects/summons"
MODEL = "gpt-image-2"
COLOURS = 64
MAX_W = 640

STYLE = ("16-bit SNES-era JRPG pixel art, the big dramatic summon artwork of a classic Square-style RPG: crisp dark "
         "outlines, rich shading, a limited glowing palette, readable at a glance. One subject, centred, nothing "
         "cropped. No text, no letters, no UI, no background scenery. The background is one flat, solid, pure magenta "
         "(#FF00FF) colour with no gradient.")

## key -> (what to draw, output height px, reference sheet image or None)
SPLASHES = {
    "recursive_summoner": (
        "The character in the reference image, redrawn as a towering SPECTRAL GIANT summoned from another plane: the "
        "same face, antlers, blue robe and gold ornaments, but huge and luminous, translucent cyan-and-gold spirit light (NO pink, NO magenta anywhere on the figure) "
        "pouring off the robe's edges, eyes glowing, both arms raised mid-incantation, and a small glowing summoning "
        "circle forming between the raised hands (they are about to summon someone else). Full body, front-facing.",
        320, "assets/sprites/jobs/summoner/idle.png"),
    ## the four elemental summons, renamed and redesigned as originals (cowir-main 21010/21014, names cowir-story 21016)
    "summon_overclock": (
        "OVERCLOCK, an original summon: a hulking furnace GOLEM of riveted iron plates, running far past its limits. "
        "Its chest is an open furnace door roaring with fire, the plates are cracked and glowing orange-white at the "
        "seams, heat-sink fins on its back glow red, little cooling fans on its shoulders spin uselessly, steam and "
        "sparks burst from every joint. One fist raised to slam down. Menacing and a little absurd. Full body.",
        400, None),
    "summon_cold_storage": (
        "COLD STORAGE, an original summon: a walking GLACIER, a towering mass of blue-white ice with a stern craggy face, "
        "stubby ice legs, frost breath, and icicles hanging from its brow. It wears an official lanyard with an ID "
        "badge around its neck and holds a clipboard in one icy hand. Slow, final and bureaucratic. Full body.",
        400, None),
    "summon_surge_protector": (
        "SURGE PROTECTOR, an original summon: a huge muscular OX made of dark storm cloud, crackling with yellow "
        "lightning, wearing a yellow construction hard hat. It drags a giant power strip by its cord, lightning "
        "arcing between the sockets. Head lowered to charge. Full body, three-quarter view.",
        360, None),
    "summon_legacy_system": (
        "LEGACY SYSTEM, an original summon: an ancient, enormous DRAGON so old it is overgrown with crumbling stone "
        "ruins, moss and rusted old machinery: pillars and arches on its back, iron cables and blinking amber "
        "indicator lights embedded in its scales, a weathered brass plate bolted to its chest. Wings spread wide, "
        "mouth open with a white-hot beam charging. Majestic and decrepit. Full body.",
        420, None),
    "summon_circle": (
        "A glowing magic SUMMONING CIRCLE seen almost flat from the front, slightly foreshortened into a wide ellipse: "
        "concentric rings of runes and geometric sigils, bright violet and cyan light, sparks rising from its rim. "
        "Only the circle.",
        160, None),
}


def _png(img: Image.Image, name: str):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    buf.seek(0)
    return (name, buf, "image/png")


def _reference(path: str) -> Image.Image:
    sheet = Image.open(ROOT / path).convert("RGBA")
    cell = sheet.crop((0, 0, sheet.height, sheet.height))
    out = Image.new("RGBA", (cell.width * 3, cell.height * 3), (255, 0, 255, 255))
    big = cell.resize((cell.width * 3, cell.height * 3), Image.NEAREST)
    out.alpha_composite(big)
    return out


## Enclosed backdrop pockets (under the ox, between the dragon's wings) and magenta-tinted steam: key every pixel.
KEY_EVERYWHERE = {"summon_overclock", "summon_cold_storage", "summon_surge_protector", "summon_legacy_system"}


def key_everywhere(img: Image.Image, tol: int = 110) -> Image.Image:
    """Clear EVERY backdrop-coloured pixel, then pull a purple cast (red AND blue over green) back to grey."""
    a = np.array(key_out(img))
    d = np.sqrt(((a[:, :, :3].astype(float) - np.array([255.0, 0.0, 255.0])) ** 2).sum(axis=2))
    a[d < tol, 3] = 0
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    cast = (r > g + 20) & (b > g + 20)
    grey = ((r + g + b) // 3).astype(np.uint8)
    for c in range(3):
        a[..., c] = np.where(cast, grey, a[..., c])
    return Image.fromarray(a, "RGBA")


def fit(raw: Image.Image, height: int, everywhere: bool = False) -> Image.Image:
    img = key_everywhere(raw) if everywhere else key_out(raw)
    img = Image.fromarray(np.where(np.array(img)[..., 3:] == 0, 0, np.array(img)).astype(np.uint8), "RGBA")  ## no key colour under alpha 0 for the resize to blend in
    box = img.split()[3].point(lambda v: 255 if v >= 128 else 0).getbbox()
    if box is None:
        raise SystemExit("the model returned an empty image")
    obj = img.crop(box)
    s = min(height / obj.height, MAX_W / obj.width)  ## cowir-battle 21015: a splash fits 640x480
    obj = obj.resize((max(1, round(obj.width * s)), max(1, round(obj.height * s))), Image.LANCZOS)
    rgb = obj.convert("RGB").quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(obj.split()[3].point(lambda v: 255 if v >= 128 else 0))
    return devolve_magenta(rgb)


def devolve_magenta(img: Image.Image) -> Image.Image:
    """Key-coloured glow the flood could not reach reads as a hole in the art: shift it to the circle's violet."""
    a = np.array(img)
    m = (a[:, :, 3] > 0) & (a[:, :, 0] > 200) & (a[:, :, 2] > 200) & (a[:, :, 1] < 90)
    a[m, 0] = (a[m, 0].astype(int) * 3 // 5).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def draw(key: str) -> Path:
    from openai import OpenAI
    what, height, ref = SPLASHES[key]
    prompt = f"{STYLE}\n\nThe subject: {what}"
    client = OpenAI()
    if ref:
        r = client.images.edit(model=MODEL, image=[_png(_reference(ref), "reference.png")], prompt=prompt,
                               size="1024x1536", n=1)
    else:
        r = client.images.generate(model=MODEL, prompt=prompt, size="1536x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGBA")
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{key}_raw.png")
    dst = STAGE / f"{key}.png"
    fit(raw, height, key in KEY_EVERYWHERE).save(dst)
    return dst


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*", help="splash keys (no names = all)")
    ap.add_argument("--deploy", action="store_true", help="copy staged splashes into assets/sprites/effects/summons/")
    args = ap.parse_args()
    for k in args.keys or sorted(SPLASHES):
        if k not in SPLASHES:
            raise SystemExit(f"unknown splash {k}")
        if args.deploy:
            src = STAGE / f"{k}.png"
            if not src.exists():
                raise SystemExit(f"{k}: nothing staged at {src}")
            OUT.mkdir(parents=True, exist_ok=True)
            (OUT / f"{k}.png").write_bytes(src.read_bytes())
            print(f"deployed {(OUT / f'{k}.png').relative_to(ROOT)}")
        else:
            print(f"staged {draw(k).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
