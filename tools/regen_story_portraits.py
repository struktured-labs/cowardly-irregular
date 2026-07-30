#!/usr/bin/env python3
"""Tier-1 story-face portraits: Calibrant, Orrery, Mordaine.

Per cowir-cutscenes msg 2680: story tier goes at `portraits/` root
(matches Masterite convention). Highest lines-per-portrait ratio in
the current gap (98 / 97 / 36 lines respectively).

Anchors:
- calibrant, orrery: no visual predecessor — creative canonical read
  from data/monsters.json + boss_dialogue.json personas
- mordaine: assets/sprites/npcs/shadow_knight.png battle placeholder
  as identity anchor
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
OUT_DIR = GAME_REPO / "assets" / "sprites" / "portraits"
RAW_DIR = PROJECT / "tmp" / "story_portrait_regen"
RAW_DIR.mkdir(parents=True, exist_ok=True)
COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

STYLE_ANCHOR = GAME_REPO / "assets" / "sprites" / "portraits" / "cleric.png"

STYLE_PROMPT_PREFIX = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "hair/hood, and upper shoulders — head fills roughly 60% of frame, "
    "shoulders visible at bottom. Centered composition on a fully "
    "transparent background. Clean pixel-art style with bold outlines, "
    "soft cel shading, no anti-aliasing artifacts, no floating pixels, "
    "no duplicate limbs, no weapons in frame, no scenery. "
)

PORTRAITS = {
    "calibrant": {
        "identity_ref": None,  # no visual predecessor
        "prompt": (
            "Character: THE CALIBRANT — a solemn ageless keeper-of-balances "
            "figure who speaks in careful measured cadence about weights and "
            "wrongs. Not a monster, not a hero — a JUDGE-of-forces made "
            "human. Silver-gray hair pulled back severely, angular pale "
            "face with high cheekbones and calm gray eyes, wearing a "
            "high-collared deep-teal robe with pale gold hexagon-lattice "
            "trim at the neckline (subtle mathematical/scale motif). "
            "Small pale halo or floating brass ring visible faintly "
            "hovering just behind the head like a suspended balance-point. "
            "Read: nothing feral, nothing warm — a person whose job is "
            "SEEING what tipped and by how much. Palette: deep teals + "
            "silvers + pale gold accents."
        ),
    },
    "orrery": {
        "identity_ref": None,  # no visual predecessor
        "prompt": (
            "Character: MADAME ORRERY — a fortune-teller archetype who works "
            "with clockwork tarot: a warm middle-aged woman with laugh-line "
            "eyes and a knowing half-smile, brown hair pulled up in a messy "
            "bun with a few small brass gears tucked into it decoratively. "
            "Wearing a deep-plum shawl over a cream blouse, with a "
            "gold-and-copper pendant at the throat shaped like a small "
            "orrery (astronomical sun-and-planet model). Reads: warm, "
            "amused, has-seen-all-the-cards-already, trickster-mentor. "
            "NOT sinister, NOT prophetic-stern — she is the friendly "
            "wisecracking wizard-aunt who deals your cards. Warm palette: "
            "plums + creams + copper + a touch of teal at the pendant."
        ),
    },
    "mordaine": {
        "identity_ref": GAME_REPO / "assets" / "sprites" / "npcs" / "shadow_knight.png",
        "prompt": (
            "Character: MORDAINE — a fallen paladin in ruined blackened "
            "plate armor, once-noble features now hollowed and pale. "
            "Grief-worn masculine face with short dark hair falling over "
            "the brow, sunken eyes with a faint cold-violet glow (not "
            "hot magic-glow, more like moonlight on ice), a jagged old "
            "scar down one cheek. Cracked pauldrons visible at the "
            "shoulders in dark iron with faded gold-inlay filigree "
            "(what was once heraldic, now worn illegible). Read: not "
            "monstrous, not raving — a knight who KEPT his vow after "
            "everyone else broke theirs, and it broke HIM. Dignified "
            "sadness, dangerous stillness. Palette: dark blackened iron "
            "+ cold violet + tarnished gold accents."
        ),
    },
}


def load_ref_bytes(path: Path, is_battle_strip: bool = False) -> bytes:
    img = Image.open(path).convert("RGBA")
    if is_battle_strip:
        H = img.size[1]
        img = img.crop((0, 0, H, H))
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

    if args.dry_run:
        print(f"DRY RUN — {len(args.ids)} portraits at {args.quality} "
              f"(~${COST[args.quality]*len(args.ids):.3f})")
        for i in args.ids: print(f"  {i}: anchor={'text-only' if not PORTRAITS[i]['identity_ref'] else PORTRAITS[i]['identity_ref'].name}")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI(); unit = COST[args.quality]; total = 0.0
    for pid in args.ids:
        if pid not in PORTRAITS:
            print(f"SKIP {pid}: unknown"); continue
        cfg = PORTRAITS[pid]
        style_bytes = load_ref_bytes(STYLE_ANCHOR)
        refs = [("ref_style.png", style_bytes, "image/png")]
        if cfg["identity_ref"] and cfg["identity_ref"].exists():
            id_bytes = load_ref_bytes(cfg["identity_ref"], is_battle_strip=True)
            refs.append(("ref_identity.png", id_bytes, "image/png"))
        print(f"[{pid}] gpt-image-1 ({args.quality}, ${unit:.3f})")
        raw = call_gpt(client, STYLE_PROMPT_PREFIX + cfg["prompt"], refs, args.quality)
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
