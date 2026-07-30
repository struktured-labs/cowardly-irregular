#!/usr/bin/env python3
"""Batch: 4 W1 shopkeeper portraits — retires the procedural
CharacterCustomization face composite (cowir-main msg 2772: struktured
saw "Chapel of Light keeper looks like a serial killer").

Personas derived from src/exploration/ShopkeeperData.gd docstrings +
CharacterCustomization feature enums (hair/eyes/skin/mouth). Same
gpt-image-1 pipeline as archetype portraits.

Output: assets/sprites/portraits/keepers/{willow,mortimer,lenora,brutus}.png
Cost: 4 × $0.167 (high) = ~$0.67
"""
import argparse, base64, io, os, sys, time
from pathlib import Path
from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
OUT_DIR = GAME_REPO / "assets" / "sprites" / "portraits" / "keepers"
RAW_DIR = PROJECT / "tmp" / "keeper_portrait_regen"
RAW_DIR.mkdir(parents=True, exist_ok=True)
COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

STYLE_ANCHOR = GAME_REPO / "assets" / "sprites" / "portraits" / "cleric.png"

STYLE_PROMPT_PREFIX = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "hair/hood, and upper shoulders — head fills roughly 60% of frame, "
    "shoulders visible at bottom. Centered composition on a fully "
    "transparent background. Clean pixel-art style with bold outlines, "
    "soft cel shading, no anti-aliasing artifacts, no floating pixels, "
    "no duplicate limbs, no weapons in frame, no scenery. Warm inviting "
    "shopkeep read — these are people the player transacts with every "
    "few minutes, they need to invite return visits, not unnerve. "
)

PORTRAITS = {
    "willow": (
        "Character: WILLOW — item-shop keeper, a friendly middle-aged "
        "HERBALIST woman with wide bright cheerful eyes (light brown), "
        "arched expressive eyebrows, small delicate nose, warm easy "
        "smile showing a hint of teeth, long forest-GREEN hair (bright "
        "moss-green natural-looking pixel-art hair color) styled in a "
        "single thick BRAID over one shoulder with a small sprig of "
        "dried lavender tucked into it, fair skin with a healthy pink "
        "tint at the cheeks, wearing a plain cream muslin blouse with "
        "a moss-green herbalist's apron-strap visible at the shoulders. "
        "Reads: welcoming, capable, always-has-a-remedy, warm-mother-"
        "figure. Verdant palette: forest green + cream + soft pink + "
        "dried-lavender purple accent."
    ),
    "mortimer": (
        "Character: MORTIMER — black-magic dealer, a mysterious dark-"
        "arts merchant with a lean angular face, NARROW piercing eyes "
        "(pale silver-gray), THIN sharp arched eyebrows, POINTED aquiline "
        "nose, a slight knowing SMIRK at one corner of the mouth (not "
        "sinister, more knowing-broker), LONG straight midnight-BLUE "
        "hair (deep indigo natural-looking pixel-art hair color) falling "
        "past the shoulders, dark rich brown skin, a small pale-cyan "
        "gem-earring visible in one ear, wearing a high-collared deep-"
        "black merchant's robe with pale silver stitching visible at "
        "the neckline (subtle arcane sigil pattern). Reads: shrewd "
        "arcane broker, discretion-guaranteed, has-what-you-need, "
        "not-your-friend-but-not-your-enemy. Cool palette: midnight "
        "indigo + black + pale cyan + rich brown skin + silver accents."
    ),
    "lenora": (
        "Character: SISTER LENORA — white-magic seller at the Chapel of "
        "Light, a SERENE and GENTLE religious sister in her late 20s "
        "with a soft round face, normal warm brown eyes with a calm "
        "kind expression (NOT staring, NOT unnerving — RELAXED gaze), "
        "gently arched normal-shape eyebrows, a small normal-shape "
        "nose, a soft closed-mouth compassionate smile at the corners "
        "(peaceful, not blank), RED hair (warm auburn-red pixel-art "
        "hair color) styled in a neat single PONYTAIL falling behind "
        "one shoulder, light fair skin with a healthy warm tone, "
        "wearing a plain cream-white sister's habit with a soft-gold "
        "trim at the collar and a small pale-gold sunburst pendant at "
        "the throat. Reads: healer, faithful, quietly-radiant, "
        "reassuring, someone-you-tell-your-troubles-to. CRITICAL: this "
        "is a KIND welcoming religious sister — NOT sinister, NOT "
        "staring, NOT unsettling; peaceful open expression, warm laugh-"
        "lines starting at the eyes. Warm palette: auburn-red hair + "
        "cream-white habit + soft gold accents + healthy fair skin."
    ),
    "brutus": (
        "Character: BRUTUS — the blacksmith, a BURLY and GRUFF adult "
        "man with a broad muscular build, wide square jaw, normal-"
        "shape steel-blue eyes (no-nonsense direct gaze), THICK dark "
        "eyebrows knitted slightly in a concentrated FROWN of professional "
        "focus (not angry, more assessing-the-work), BROAD flat pugilist "
        "nose, a downturned FROWN mouth partially hidden by a THICK full "
        "dark-BLACK bushy beard cut short and squared, SHORT close-cropped "
        "BLACK hair receding slightly at the temples, TAN weathered "
        "sun-and-forge skin with soot smudged along one cheek, wearing a "
        "heavy dark-brown leather forge apron over a sleeveless dark "
        "gray undershirt with both broad muscular shoulders visible, a "
        "small brass hammer-hook clasp at the throat. Reads: strength, "
        "craft-pride, hard-to-impress, respects-good-work-only, "
        "professional-not-personal. Palette: dark brown leather + black "
        "hair/beard + steel-gray + tan weathered skin + copper-hint from "
        "the forge."
    ),
}


def load_ref_bytes(path: Path) -> bytes:
    img = Image.open(path).convert("RGBA")
    target = 1024
    scale = target / max(img.size)
    img = img.resize((int(img.size[0] * scale), int(img.size[1] * scale)),
                     Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target - img.width) // 2, (target - img.height) // 2), img)
    buf = io.BytesIO(); canvas.save(buf, format="PNG")
    return buf.getvalue()


def downscale(img_1024: Image.Image, target: int = 256) -> Image.Image:
    img = img_1024.convert("RGBA")
    img = img.resize((target * 4, target * 4), Image.LANCZOS)
    return img.resize((target, target), Image.BOX)


def transparent_bg(img: Image.Image, threshold: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load(); W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def call_gpt(client, prompt, refs, quality, max_retries=3):
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(model="gpt-image-1", image=refs,
                                       prompt=prompt, size="1024x1024",
                                       quality=quality, n=1)
            return Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg:
                time.sleep(30 * (attempt + 1))
            elif any(k in msg for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"  Error: {e}; retry"); time.sleep(5)
    raise RuntimeError("failed after retries")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", default=list(PORTRAITS))
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    ids = [i for i in args.ids if i in PORTRAITS]
    if args.dry_run:
        print(f"DRY RUN — {len(ids)} keeper portraits at {args.quality} "
              f"(~${COST[args.quality]*len(ids):.3f})")
        for i in ids: print(f"  {i}: persona-only")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI(); unit = COST[args.quality]; total = 0.0
    style_bytes = load_ref_bytes(STYLE_ANCHOR)
    for pid in ids:
        refs = [("ref_style.png", style_bytes, "image/png")]
        print(f"[{pid}] gpt-image-1 ({args.quality}, ${unit:.3f})")
        raw = call_gpt(client, STYLE_PROMPT_PREFIX + PORTRAITS[pid], refs, args.quality)
        raw.save(RAW_DIR / f"{pid}_raw_{args.quality}.png")
        portrait = transparent_bg(downscale(raw, 256))
        out = OUT_DIR / f"{pid}.png"
        portrait.save(out)
        print(f"  → {out.relative_to(GAME_REPO)}")
        total += unit
    print(f"\nTotal spent: ${total:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
