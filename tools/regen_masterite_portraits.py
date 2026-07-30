#!/usr/bin/env python3
"""Generate 4 Masterite family portraits (Warden/Tempo/Arbiter/Curator)
for cutscene dialogue display.

Work order: struktured (2026-07-16 via cowir-main msg 2657 + cowir-cutscenes
msg 2662) — the Masterites currently render with procedural `mysterious`
portrait, no visual distinction between roles. One portrait per role, not
per world variant (24→4 dedup — all "Warden of X" are the same masterite
renamed per world).

Anchor: each portrait's identity references the medieval T1 battle strip
that struktured is currently fighting (visual canon in playtest). Persona
reads from data/monsters.json descriptions + boss_dialogue.json.

Pipeline: same as tools/regen_broken_portraits.py — one gpt-image-1 call
per portrait at the party-portrait framing anchor (cleric.png), plus each
Masterite's own battle-strip frame 0 as identity reference. 256×256
face+shoulders bust, transparent bg.

Output: assets/sprites/portraits/masterites/{warden,tempo,arbiter,curator}.png
Cost: 4 × $0.167 (high quality) = ~$0.67
"""
import argparse
import base64
import io
import json
import os
import sys
import time
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
OUT_DIR = GAME_REPO / "assets" / "sprites" / "portraits"
RAW_DIR = PROJECT / "tmp" / "masterite_portrait_regen"
RAW_DIR.mkdir(parents=True, exist_ok=True)

COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

# Party cleric.png = the framing anchor (the "known-good portrait" style)
STYLE_ANCHOR = GAME_REPO / "assets" / "sprites" / "portraits" / "cleric.png"

# Per-world variants: `masterite_<role>_<world>.png` output naming +
# battle-strip identity ref per (role, world). Cowir-cutscenes confirmed
# per-world IDs (msg 2665) — 4 medieval first, W2-W5 as struktured reaches.
ROLES = ("warden", "tempo", "arbiter", "curator")
WORLDS = ("medieval", "suburban", "industrial", "futuristic", "abstract")

def _identity_ref(role: str, world: str) -> Path:
    return GAME_REPO / "assets" / "sprites" / "monsters" / f"masterite_{role}_{world}.png"

STYLE_PROMPT_PREFIX = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "helm/hood, and upper shoulders — head fills roughly 60% of frame, "
    "shoulders visible at bottom. Centered composition on a fully "
    "transparent background. Same clean pixel-art style, palette, and "
    "shading discipline as classic Final Fantasy VI / Chrono Trigger "
    "villain portraits: bold outlines, soft cel shading, no anti-aliasing "
    "artifacts, no floating pixels, no duplicate limbs, no weapons in "
    "frame, no scenery. Menacing but composed — these are teacher-bosses, "
    "not raving monsters. "
)

PERSONAS = {
    "warden": (
        "Character: the WARDEN OF THE OLD GUARD — an ancient armored knight "
        "who has guarded the world's balance since its creation, armor scarred "
        "from a thousand tests of strength. Golden pauldrons and helm crown "
        "with red gem, gold-inlaid battered plate mail at the shoulders, cool "
        "gray eyes glinting under the helm-shadow, gray beard or heavy jaw. "
        "Authority-figure read: patient, uncompromising, respected. NOT feral, "
        "NOT snarling — a knight who has SEEN every possible strike. Deep "
        "blue-and-gold heraldic palette matching the medieval Warden battle "
        "strip. Weathered, powerful, still."
    ),
    "tempo": (
        "Character: TEMPO OF THE HUNT — a swift ranger-scout who appears and "
        "vanishes like the wind, testing whether you can match its relentless "
        "pace. Anthropomorphic fox-like features (pointed ears, sharp amber "
        "eyes, angular muzzle), dark forest-green hood pulled up over the head, "
        "sharp intense focused gaze, tattered leather scout armor at the "
        "shoulders. Restless-clockwork energy — reads like a predator mid-tempo "
        "already deciding on the next strike. Matches the medieval Tempo of "
        "the Hunt battle strip: fox-warrior scout with bow and shield. Ears "
        "and hood dominate the silhouette top."
    ),
    "arbiter": (
        "Character: ARBITER OF STEEL — a dual-wielding swordmaster who measures "
        "every blow with mathematical precision, seeks the perfect strike. "
        "Deep-red judicial robes with high collar, silver-white hair pulled "
        "severely back, cold pale piercing eyes (blue or gray), a small silver "
        "circlet or judge's band across the forehead, ascetic thin face. "
        "Cold-judicial read: uninterested in mercy, interested in whether your "
        "form was CORRECT. No visible weapons in the bust framing but the "
        "posture reads swordmaster-at-rest. Matches the medieval Arbiter of "
        "Steel battle strip: robed judge palette (dark red + gold accents)."
    ),
    "curator": (
        "Character: CURATOR OF THE FLAME — a robed figure wreathed in "
        "controlled flame, judges how wisely you spend your power. Deep-red "
        "ceremonial priest's robes with a tall crown or ornate hood, half the "
        "face wreathed in soft orange-gold flame that curls upward past the "
        "cheek (flame is CONTAINED, doesn't burn — a symbol of control not "
        "chaos), calm dark eyes visible through the flame's veil. Warm "
        "gold-and-crimson palette matching the medieval Curator of the Flame "
        "battle strip (fire-torch priest). Obsessive-archivist calm — "
        "cataloging your every move as they burn."
    ),
}


def load_ref_bytes(path: Path, is_battle_strip: bool = False) -> bytes:
    """Load a reference PNG, cropping to first frame if it's a battle strip."""
    img = Image.open(path).convert("RGBA")
    if is_battle_strip:
        # Battle strips are horizontal — take the first square frame
        H = img.size[1]
        img = img.crop((0, 0, H, H))
    # Upscale to 1024 for the API (nearest to preserve pixel art)
    target = 1024
    scale = target / max(img.size)
    new_w, new_h = int(img.size[0] * scale), int(img.size[1] * scale)
    img = img.resize((new_w, new_h), Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)
    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def downscale_to_portrait(img_1024: Image.Image, target: int = 256) -> Image.Image:
    img = img_1024.convert("RGBA")
    intermediate = target * 4
    img = img.resize((intermediate, intermediate), Image.LANCZOS)
    img = img.resize((target, target), Image.BOX)
    return img


def remove_flat_background(img: Image.Image, threshold: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def call_gpt_image(client, prompt: str, ref_files: list, quality: str,
                   max_retries: int = 3) -> Image.Image:
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(
                model="gpt-image-1",
                image=ref_files,
                prompt=prompt,
                size="1024x1024",
                quality=quality,
                n=1,
            )
            b64 = resp.data[0].b64_json
            return Image.open(io.BytesIO(base64.b64decode(b64)))
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg:
                wait = 30 * (attempt + 1)
                print(f"    Rate limit; backing off {wait}s...")
                time.sleep(wait)
            elif any(k in msg for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"    Error: {e}; retry {attempt+1}/{max_retries}")
                time.sleep(5)
    raise RuntimeError(f"Failed after {max_retries} retries")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--roles", nargs="+", default=list(ROLES))
    ap.add_argument("--worlds", nargs="+", default=["medieval"],
                    help="World variants to generate (default: medieval only)")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    pairs = [(r, w) for r in args.roles for w in args.worlds if r in PERSONAS]
    if args.dry_run:
        total = COST[args.quality] * len(pairs)
        print(f"DRY RUN — would generate {len(pairs)} portraits at "
              f"{args.quality} (~${total:.3f})")
        for r, w in pairs:
            ref = _identity_ref(r, w)
            print(f"  {r}/{w}: identity ref = {ref.name} (exists: {ref.exists()})")
        return 0

    if not STYLE_ANCHOR.exists():
        print(f"ERROR: style anchor missing: {STYLE_ANCHOR}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI()
    total_cost = 0.0
    unit = COST[args.quality]

    for role, world in pairs:
        ref_battle = _identity_ref(role, world)
        if not ref_battle.exists():
            print(f"SKIP {role}/{world}: battle ref missing at {ref_battle}")
            continue

        prompt = STYLE_PROMPT_PREFIX + PERSONAS[role]
        style_bytes = load_ref_bytes(STYLE_ANCHOR, is_battle_strip=False)
        identity_bytes = load_ref_bytes(ref_battle, is_battle_strip=True)
        refs = [
            ("ref_style.png", style_bytes, "image/png"),
            ("ref_identity.png", identity_bytes, "image/png"),
        ]

        print(f"[{role}/{world}] gpt-image-1 ({args.quality}, ${unit:.3f}) "
              f"identity={ref_battle.name}")
        raw = call_gpt_image(client, prompt, refs, args.quality)
        raw_path = RAW_DIR / f"masterite_{role}_{world}_raw_{args.quality}.png"
        raw.save(raw_path)

        portrait = downscale_to_portrait(raw, 256)
        portrait = remove_flat_background(portrait)
        out_path = OUT_DIR / f"masterite_{role}_{world}.png"
        portrait.save(out_path)
        print(f"  → {out_path.relative_to(GAME_REPO)}")

        total_cost += unit

    print(f"\nTotal spent: ${total_cost:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
