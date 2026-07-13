#!/usr/bin/env python3
"""Regenerate a T1 monster sheet using gpt-image-1 anchored to artist references.

Pipeline (per monster, ~$0.042 at medium quality):
  1. Look up best artist reference(s) via reference_library.refs_for()
  2. Export .aseprite → PNG if needed
  3. Call gpt-image-1 ONCE, prompting for a 2×2 contact sheet with the
     four core poses (idle / attack windup / hit recoil / defeated)
  4. Split the 1024×1024 output into four 512×512 tiles
  5. Downscale each tile 512→256, arrange as an 8-frame 2048×256 strip
     with each unique pose duplicated (idle×2, attack×2, hit×2, dead×2)
  6. Save to assets/sprites/monsters/<id>.png, back up prior as
     <id>.pre_artist_style.png

Trade-off vs pixel-perfect artist redraw:
  + one API call per monster (~4¢), no LoRA training required
  + all four poses share identity (single latent, single generation)
  + style-anchored to the actual artist enemy (not generic pixel art)
  - each pose only has one frame, so animations are less lively than
    a hand-drawn 8-frame set. Still better than current AI sheets
    where hit/dead were multi-body grid dumps (see item 16 fix).

Usage:
    uv run python tools/regen_monster_artist_style.py cave_rat skeleton
    uv run python tools/regen_monster_artist_style.py cave_rat --quality high
    uv run python tools/regen_monster_artist_style.py --dry-run
"""
import argparse
import base64
import io
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT))
from tools.pipeline.reference_library import refs_for

GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
OUTPUT_DIR = PROJECT / "tmp" / "monster_artist_regen"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

COST_PER_IMAGE = {"low": 0.011, "medium": 0.042, "high": 0.167}

# Battle sheet layout (from sprite_manifest for T1 monsters):
#   frame 0-1  = idle
#   frame 2-3  = attack
#   frame 4-5  = hit
#   frame 6-7  = dead
POSE_PROMPTS = [
    ("idle",   "in a neutral resting stance, alert battle pose"),
    ("attack", "mid-swing during an attack action, weapon or claws forward"),
    ("hit",    "recoiling backward after taking a hit, staggered pained expression"),
    ("dead",   "collapsed on the ground defeated, limp body"),
]

# Per-monster identity notes (fold into prompt to reinforce reference)
MONSTER_DESC = {
    "cave_rat":       "large dark gray cave rat with scruffy fur, red eyes, exposed teeth, small clawed paws",
    "cave_rat_king":  "a DISAPPOINTINGLY LARGE quadruped rat, four legs firmly on the ground (NOT bipedal, NOT humanoid, NOT goblin-shaped), fat rotund pear-shaped body, matted brown-gray fur, tiny beady black eyes, whiskers, a long naked pink tail, small clawed paws, and — sitting comically small and lopsided on his head — a TINY bronze crown that is obviously too small for him. Whimsical menace: he looks silly but not friendly. Read: the joke IS the sprite. NO cloak, NO weapon, NO armor, NO humanoid stance. He is a rat wearing a bad crown",
    "rat_guard":      "bipedal humanoid rat guard wearing tattered leather armor, gripping a rusty short sword in two paws, hunched aggressive stance",
    "skeleton":       "undead human skeleton warrior with a tarnished rusted iron sword and battered wooden shield, hollow eye sockets, cracked yellowed bones, tattered belt cloth",
    "wolf":           "gaunt gray timber wolf with tangled fur, glowing amber eyes, curled black lips exposing white fangs",
    "cave_troll":     "hulking green-gray cave troll with a knotted wooden club, sagging leathery skin, tusked jaw, small angry eyes",
    "shadow_knight":  "dark armored knight in blackened plate mail with glowing violet visor eyes and a longsword wreathed in shadow",
    "cursed_armor":   "empty haunted suit of medieval plate armor animated by dark energy, wielding a rusted greatsword, purple wisps leaking from the joints",
    "spider":         "large hairy cave spider with 8 spindly legs, bulbous abdomen, glinting red multi-faceted eyes",
    "ghost":          "translucent pale spirit with tattered floating shroud, hollow blue eye sockets, wispy ethereal form",
    "imp":            "small mischievous red imp with bat-like wings, sharp horns and tail, wielding a tiny obsidian dagger, snarling grin",
    "troll":          "large ugly forest troll with warty green skin, sagging belly, knotted club, angry underbite",
    "snake":          "coiled dark scaled viper with venomous fangs bared, forked tongue flicking, patterned scales",
    "mushroom":       "hostile spore-belching giant purple mushroom creature with beady eyes on the cap and stubby legs",
    "elder_mushroom": "large ancient fungal creature, moss-covered cap with glowing spore vents, spindly wooden limbs",
    "fungoid":        "shambling fungus-based creature with a pale bulbous body and drooping caps for arms, spore mist trailing",
    # Spotlight-duel minibosses (msg 1950). Each solo-duels one PC job.
    "fighter_skeleton_knight":  "chivalric skeleton knight in polished plate armor, wielding a two-handed longsword and a kite shield with a fading heraldic emblem, hollow eye sockets glowing pale amber, worn cloth surcoat, honor-fight stance",
    "cleric_survive_target":    "tall grim spectral figure in tattered gray-white burial robes, faceless with two hollow black eye pits, floating slightly above the ground, arms outstretched palms-forward channeling continuous dark energy — an oppressive sustained-pressure enemy, not a striker",
    "rogue_lockward":           "hulking treasure-guardian construct wrapped in chains and lockplates, cracked stone body with steel banding, a heavy iron padlock sealing its chest cavity, ember-orange eyes, high-guard defensive stance with a giant iron key clutched as a mace",
    "mage_prismatic_construct": "geometric crystalline construct made of interlocking floating faceted prism shards in shifting fire-red / ice-blue / lightning-yellow hues, no organic body, central glowing core, arcane sigils floating in the negative space between shards",
    "bard_hostile_courtier":    "haughty aristocratic courtier in an elaborate deep-purple velvet doublet with gold trim, powdered gray wig with a small ribbon bow, holding a lace kerchief in one hand and a folded fan in the other, disdainful sneer — not a fighter, a talker",
    # Masterite Tempo family — 5 bosses, each a different concept of "time
    # applied against you." Bespoke identities so they DON'T homogenize into
    # the goblin-family read that the July bulk regen caused (playtest bug,
    # cowir-main msg 2516).
    "masterite_tempo_medieval": (
        "Tempo of the Hunt — lean human huntsman/scout in dark forest-green "
        "hooded leather cloak with the hood UP, face partly shadowed, sharp "
        "amber eyes glinting from under the hood, drawing a longbow with an "
        "arrow nocked, a quiver strapped diagonally across his back, worn "
        "leather boots and gloves, a low crouched stalking stance. "
        "NOT armored, NOT goblin-shaped, NOT a warrior — a predator that hunts "
        "by patience. Silhouette must read as 'ranger with drawn bow' at a "
        "glance"
    ),
    "masterite_tempo_suburban": (
        "Tempo of the Rush Hour — a harried modern middle-manager human man "
        "in a crumpled navy suit jacket with the tie loosened and askew, "
        "shirt untucked at the front, disheveled brown hair, a briefcase held "
        "up in one hand like a bludgeon (mid-swing) and a paper coffee cup "
        "clutched in the other, running/lunging forward, exhausted furious "
        "expression, dress shoes. NOT fantasy, NOT armored — modern office "
        "attire. Silhouette must read as 'stressed commuter attacking with "
        "briefcase' at a glance"
    ),
    "masterite_tempo_industrial": (
        "Tempo of the Shift — a factory shift-supervisor human man in a "
        "high-visibility neon-orange safety vest over a gray work coverall, "
        "a yellow hard hat with a small numeral 'B' on the front, "
        "steel-toe boots, holding a heavy metal clipboard in one hand and a "
        "punch-card timesheet in the other, oil-smudged face, tired angry "
        "expression, a wristwatch prominently visible on the raised arm. "
        "Silhouette must read as 'foreman on the clock' at a glance"
    ),
    "masterite_tempo_futuristic": (
        "Tempo of the Clock Cycle — a humanoid digital daemon whose BODY "
        "is a translucent clock face (roman numerals visible on the torso, "
        "spinning clock hands where the heart would be), head is a floating "
        "monospaced terminal-cursor block (a solid glowing rectangle for a "
        "face, no organic features), thin geometric limbs made of stacked "
        "digital-numeric segments, hovering slightly off the ground, "
        "cool cyan and violet neon palette. NOT organic, NOT armored. "
        "Silhouette must read as 'CPU-scheduler ghost' at a glance"
    ),
    "masterite_tempo_abstract": (
        "Tempo of Sequence — pure ORDER-as-form: a semi-transparent "
        "humanoid outline (a suggestion of a person, not a body) filled with "
        "cascading downward arrows, dashed timeline segments, and numbered "
        "sequence marks (1→2→3→) glowing in soft white and pale gold. The "
        "figure is more implied than drawn — motion-blur trails follow the "
        "silhouette. NOT a character, an INDEX. Silhouette must read as "
        "'sequence itself, given a shape' at a glance"
    ),
}


def sheet_prompt(monster_id: str, ref_name: str) -> str:
    desc = MONSTER_DESC.get(monster_id, f"a {monster_id.replace('_', ' ')}")
    poses_str = ", ".join(
        f"Top-{p_pos}: same character {p_desc}"
        for p_pos, (_, p_desc) in zip(["left", "right", "left", "right"], POSE_PROMPTS)
    )
    poses_txt = (
        f"Top-left: same monster in a neutral resting stance, alert battle pose. "
        f"Top-right: same monster mid-swing during an attack action, weapon or claws forward. "
        f"Bottom-left: same monster recoiling backward after taking a hit, staggered pained expression. "
        f"Bottom-right: same monster collapsed on the ground defeated, limp body."
    )
    return (
        f"16-bit JRPG pixel-art battle sprite contact sheet. 2×2 grid layout, "
        f"four poses of the SAME monster, identical character identity across all four "
        f"tiles — same silhouette, same palette, same size, same lineart weight. "
        f"Fully transparent background between tiles, no scenery, no shadows. "
        f"Character: {desc}. "
        f"{poses_txt} "
        f"Style-match the reference sprite: same clean pixel-art discipline, bold "
        f"outlines, soft cel shading, no anti-aliasing artifacts, no floating pixels, "
        f"no duplicate limbs, no text, no labels. Each tile centered in its quadrant. "
        f"Reference character is a {ref_name} — copy the reference's outlining, "
        f"palette saturation, and shading style, not the reference's specific "
        f"anatomy (the target is {monster_id.replace('_', ' ')}, not a {ref_name})."
    )


def load_reference_bytes(paths: list[Path]) -> bytes:
    """Combine 1-2 artist reference sheets into a single 1024×1024 anchor image."""
    if not paths:
        raise RuntimeError("no artist reference paths provided")
    # For each aseprite, export the first tag's frames as a strip
    ref_images = []
    for p in paths:
        if p.suffix == ".aseprite":
            tmp = OUTPUT_DIR / (p.stem + "_ref.png")
            subprocess.run(
                ["aseprite", "--batch", "--sheet", str(tmp), str(p)],
                check=True, capture_output=True,
            )
            ref_images.append(Image.open(tmp).convert("RGBA"))
        else:
            ref_images.append(Image.open(p).convert("RGBA"))

    target = 1024
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    # Stack vertically if 2 refs, single centered if 1
    if len(ref_images) == 1:
        img = ref_images[0]
        scale = min(target / img.width, target / img.height)
        new_w, new_h = int(img.width * scale), int(img.height * scale)
        img = img.resize((new_w, new_h), Image.NEAREST)
        canvas.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)
    else:
        half = target // 2
        for i, img in enumerate(ref_images[:2]):
            scale = min(target / img.width, half / img.height)
            new_w, new_h = int(img.width * scale), int(img.height * scale)
            img = img.resize((new_w, new_h), Image.NEAREST)
            y_offset = i * half + (half - new_h) // 2
            canvas.paste(img, ((target - new_w) // 2, y_offset), img)

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def call_gpt_image(client, prompt: str, ref_bytes: bytes, quality: str,
                   max_retries: int = 3) -> Image.Image:
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(
                model="gpt-image-1",
                image=("reference.png", ref_bytes, "image/png"),
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


def downscale_pose(tile_512: Image.Image, target: int = 256) -> Image.Image:
    img = tile_512.convert("RGBA")
    intermediate = target * 2
    img = img.resize((intermediate, intermediate), Image.LANCZOS)
    img = img.resize((target, target), Image.BOX)
    return img


def make_transparent_bg(img: Image.Image, threshold: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def assemble_sheet(sheet_1024: Image.Image, monster_id: str) -> Image.Image:
    """Split 1024×1024 into 4 tiles, downscale each, assemble as 2048×256 strip."""
    half = 512
    tiles = [
        sheet_1024.crop((0, 0, half, half)),        # idle (top-left)
        sheet_1024.crop((half, 0, 1024, half)),     # attack (top-right)
        sheet_1024.crop((0, half, half, 1024)),     # hit (bottom-left)
        sheet_1024.crop((half, half, 1024, 1024)),  # dead (bottom-right)
    ]
    tiles_256 = [make_transparent_bg(downscale_pose(t, 256)) for t in tiles]

    # 8-frame strip: idle×2 + attack×2 + hit×2 + dead×2
    # The second frame of each anim is shifted down 1px so test_idle_frames_differ
    # (and any equivalent frame-differ tests) sees a real change — creates a
    # subtle breathing-bob animation. Empty top row is transparent.
    strip = Image.new("RGBA", (2048, 256), (0, 0, 0, 0))
    for i in range(8):
        pose_idx = i // 2
        tile = tiles_256[pose_idx]
        if i % 2 == 1:  # second copy of each pose — 1px bob
            bobbed = Image.new("RGBA", tile.size, (0, 0, 0, 0))
            bobbed.paste(tile, (0, 1), tile)
            tile = bobbed
        strip.paste(tile, (i * 256, 0), tile)
    return strip


def regen_one(client, monster_id: str, quality: str) -> dict:
    refs = refs_for(monster_id)
    if not refs:
        return {"monster": monster_id, "status": "no-refs"}
    ref_name = refs[0].stem.split()[0].lower()  # "SLIME 1" → "slime"
    print(f"[{monster_id}] refs={[r.name for r in refs]}  ${COST_PER_IMAGE[quality]}")
    prompt = sheet_prompt(monster_id, ref_name)
    ref_bytes = load_reference_bytes(refs)
    result_1024 = call_gpt_image(client, prompt, ref_bytes, quality)
    raw_path = OUTPUT_DIR / f"{monster_id}_raw_{quality}.png"
    result_1024.save(raw_path)

    strip = assemble_sheet(result_1024, monster_id)
    out_path = GAME_REPO / "assets" / "sprites" / "monsters" / f"{monster_id}.png"
    if out_path.exists():
        backup = out_path.with_name(out_path.stem + ".pre_artist_style" + out_path.suffix)
        if not backup.exists():
            shutil.copy2(out_path, backup)
    strip.save(out_path)
    print(f"  → {out_path.relative_to(GAME_REPO)} (raw at {raw_path.relative_to(PROJECT)})")
    return {"monster": monster_id, "status": "ok", "cost": COST_PER_IMAGE[quality]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("monsters", nargs="+", help="monster ids to regen")
    parser.add_argument("--quality", choices=["low", "medium", "high"],
                        default="medium")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.dry_run:
        total = COST_PER_IMAGE[args.quality] * len(args.monsters)
        print(f"DRY RUN — would regen {len(args.monsters)} monsters at "
              f"{args.quality} (~${total:.3f})")
        for m in args.monsters:
            refs = refs_for(m)
            print(f"  {m}: refs={[r.name for r in refs]}")
        return 0

    client = OpenAI()
    results = []
    total = 0.0
    for m in args.monsters:
        try:
            r = regen_one(client, m, args.quality)
            results.append(r)
            total += r.get("cost", 0.0)
        except Exception as e:
            print(f"[{m}] FAILED: {e}")
            results.append({"monster": m, "status": "error", "error": str(e)})

    print(f"\nTotal spent: ${total:.3f} on {len(args.monsters)} monsters")
    log = OUTPUT_DIR / "_cost.json"
    prev = json.loads(log.read_text()) if log.exists() else {"sessions": [], "total": 0.0}
    prev["sessions"].append({"quality": args.quality, "results": results, "cost": total})
    prev["total"] = prev.get("total", 0.0) + total
    log.write_text(json.dumps(prev, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
