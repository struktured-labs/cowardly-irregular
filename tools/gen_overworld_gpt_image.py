#!/usr/bin/env python3
"""
Generate 4-direction overworld walk-cycle sprites via GPT-Image-1
with TWO reference images:

  1. Artist battle sprite (idle frame) → character identity (palette, equipment)
  2. Proc-gen chibi (existing overworld.png) → format/scale/angle (4x4 grid layout)

GPT-Image returns a 1024x1024 image organized as a 4x4 grid; we downscale to
128x128 game format and split into a 16-frame strip for aseprite assembly.

Pipeline (mirrors gen_overworld_pixellab.py but uses gpt-image-1):
  1. Load + pad both refs to 1024x1024
  2. Call client.images.edit with both refs + structured prompt
  3. Receive 1024x1024 output
  4. Downscale 1024→128 (LANCZOS for quality, then NEAREST step for crispness)
  5. Build tagged aseprite via tools/build_overworld_aseprite.lua
  6. Upload .aseprite to gdrive: cowir/.../<JOB>/claude/
  7. Deploy 128x128 PNG to game repo's assets/sprites/jobs/<job>/overworld.png

Cost: ~$0.07 (medium) or ~$0.19 (high) per call. Idempotent unless --force.

Supports both PC jobs (fighter/cleric/rogue/mage) and NPC archetypes
(old_man/old_woman/young_man/young_woman/child/guard/merchant/scholar).
NPCs use a PC's battle sprite for palette/style anchoring and a PC's existing
overworld chibi for scale/angle anchoring; the prompt provides the NPC's
distinct identity. NPC outputs deploy to assets/sprites/npcs/<name>/.

Usage:
    source setenv.sh
    uv run python tools/gen_overworld_gpt_image.py --entity fighter
    uv run python tools/gen_overworld_gpt_image.py --entity old_man --quality medium
    uv run python tools/gen_overworld_gpt_image.py --entity guard --dry-run
"""

import argparse
import base64
import io
import json
import os
import subprocess
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DRIVE_LOCAL = REPO / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters"
# Default to THIS checkout. The old default named a specific sibling worktree, and step 6
# writes there — a bare run deployed into a tree it did not own. Override with GAME_REPO.
GAME_REPO = Path(os.environ.get("GAME_REPO", REPO))
GAME_JOBS = GAME_REPO / "assets" / "sprites" / "jobs"
TMP = REPO / "tmp" / "overworld_gpt_image"
TMP.mkdir(parents=True, exist_ok=True)

# Default deploy root under the game repo's `assets/sprites/`.
# Per-entry override via "dest_root". Drive root is always
# `cowir/assets/sprites/Game graphics - <DRIVE_ROOT>/<drive_dir>/`.
DEFAULT_DEST_ROOT = "jobs"
DEFAULT_DRIVE_ROOT = "Characters"


JOB_SOURCES = {
    "fighter": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "FIGHTER/claude",
        "char_desc": (
            "dark-brown-haired knight fighter in deep red tunic with leather/copper "
            "shoulder armor, cradling a steel sword, dark leather boots and gloves"
        ),
    },
    "bard": {
        "ase_rel": "BARD/Bard Base sprite.aseprite",
        "idle_tag": "Idle",
        "drive_dir": "BARD/claude",
        "char_desc": (
            "young female bard with long orange hair in a loose ponytail and a "
            "distinctive curl on top, crimson-and-plum leather doublet with dark "
            "purple accents, no hat, carrying her piano-key-bladed scythe "
            "instrument slung on her back — exactly one instrument, kept small "
            "and on the back so the body silhouette stays readable"
        ),
    },
    "cleric": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "CLERIC/claude",
        "char_desc": (
            "white-robed cleric healer holding EXACTLY ONE ornate golden ankh-tipped "
            "staff in one hand, soft gentle aura, hooded head, simple boots — only one "
            "staff, no extra floating staffs or duplicate weapons in the frame"
        ),
    },
    "rogue": {
        "ase_rel": "ROGUE/Rogue Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "ROGUE/claude",
        "char_desc": (
            "agile rogue archer with bow, dark leather armor, slim build, "
            "brown/gray earth-tone colors, light boots"
        ),
    },
    "mage": {
        "ase_rel": "MAGE/Mage Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "MAGE/claude",
        "char_desc": (
            "young wizard mage with VISIBLE pale skin face and small dark eyes "
            "(NOT a shadowed silhouette face — face must be clearly drawn with "
            "skin tones), wearing deep teal/navy robes with purple pointed hat, "
            "holding a wooden staff topped with a golden flame, friendly JRPG "
            "chibi style"
        ),
    },
}


# NPC archetypes — no artist-made references yet, so we lean on PC battle
# sprites for STYLE/PALETTE anchoring and use the prompt to specify the NPC's
# distinct identity. Each entry picks a PC ref whose palette/silhouette is
# closest to the target NPC archetype.
#
# Game-side deploy:  assets/sprites/npcs/<key>/overworld.png
# Drive aseprite:    cowir/assets/sprites/Game graphics - NPCs/<NPC>/claude/
NPC_SOURCES = {
    "old_man": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",  # white robe palette
        "idle_tag": "idle",
        "drive_dir": "OLD_MAN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "elderly village man with long white beard, gray-brown robe, simple "
            "leather boots, hunched posture, walking stick in one hand, kindly "
            "weathered face"
        ),
    },
    "old_woman": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "OLD_WOMAN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "elderly village woman with gray hair tied in a bun, blue shawl over "
            "shoulders, plain dark green dress, simple boots, carrying a wicker "
            "basket, kindly weathered face"
        ),
    },
    "young_man": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",  # rugged peasant palette
        "idle_tag": "idle",
        "drive_dir": "YOUNG_MAN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "young peasant man, brown hair, simple tan tunic, brown breeches, "
            "sturdy work boots, friendly open face, plain commoner clothes "
            "(NOT armored, NOT a knight)"
        ),
    },
    "young_woman": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "YOUNG_WOMAN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "young peasant woman, brown hair pulled back into a low ponytail, "
            "simple cream-colored dress with brown apron, sturdy boots, friendly "
            "open face, plain commoner clothes"
        ),
    },
    "child": {
        "ase_rel": "ROGUE/Rogue Main design.aseprite",  # slim/small palette anchor
        "idle_tag": "idle",
        "drive_dir": "CHILD/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "small child of about seven years, tousled brown hair, bright red "
            "shirt, brown short pants, bare feet, energetic excited posture — "
            "smaller in stature than adult NPCs (about 75% the height of the "
            "PC chibi reference)"
        ),
    },
    "guard": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "GUARD/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "town guard in studded leather armor over a dark blue tunic, simple "
            "iron helmet, holding a wooden spear with a steel tip, brown leather "
            "boots, sturdy alert posture (NOT a hero or knight — just a town "
            "watchman)"
        ),
    },
    "merchant": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "MERCHANT/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "village merchant in a forest-green vest over white shirt, brown "
            "leather apron, slightly portly build, dark hair with mustache, "
            "leather boots, friendly inviting posture (no weapons)"
        ),
    },
    "scholar": {
        "ase_rel": "MAGE/Mage Main design.aseprite",  # robe palette anchor
        "idle_tag": "idle",
        "drive_dir": "SCHOLAR/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "scholarly older man in a dark blue belted robe, round wire-frame "
            "spectacles, gray hair receding, holding a leather-bound book under "
            "one arm, simple sandals, contemplative posture (NOT a wizard with "
            "a magic staff)"
        ),
    },
    "innkeeper": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "INNKEEPER/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "middle-aged innkeeper man with rotund belly, brown hair and full "
            "mustache, white shirt with rolled sleeves, brown leather apron over "
            "the shirt, dark trousers, sturdy boots, holding a wooden mug, warm "
            "welcoming smile (NOT a knight, NOT armored, NOT a hero)"
        ),
    },
    "blacksmith": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "BLACKSMITH/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "muscular blacksmith with bare brawny arms, leather work apron over "
            "a sleeveless tunic, dark trousers, heavy work boots, soot-stained "
            "face, holding a heavy iron smithing hammer, full dark beard, "
            "powerful working-class build (NOT a knight, NOT a warrior with armor)"
        ),
    },
    "priestess": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "PRIESTESS/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "young priestess with long auburn hair, pure white robe with gold "
            "trim and a high collar, gold sash at the waist, hands clasped in "
            "front in prayer (NO staff, NO weapon — empty hands), simple white "
            "sandals, serene devout posture (visually distinct from any cleric "
            "with an ankh staff — this priestess holds NOTHING in her hands)"
        ),
    },
    "noble": {
        "ase_rel": "MAGE/Mage Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "NOBLE/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "young nobleman in a fine deep-purple velvet doublet with gold "
            "embroidery and silver buttons, white silk shirt visible at collar "
            "and cuffs, dark slim trousers, polished black leather shoes, "
            "ringed fingers, refined upright posture, dark hair styled neatly "
            "(NOT a wizard, NOT holding any staff or magic item)"
        ),
    },
    "noblewoman": {
        "ase_rel": "MAGE/Mage Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "NOBLEWOMAN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "elegant noblewoman in a long flowing emerald-green gown with gold "
            "trim and lace at the neckline, dark hair gathered in an elaborate "
            "updo, pearl necklace, refined posture, hands folded in front "
            "(NOT a wizard, NOT holding any staff)"
        ),
    },
    "king": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "KING/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "regal king with full white beard, large ornate gold crown studded "
            "with red gems, deep crimson royal robe with white ermine fur "
            "trim, gold-embroidered tunic underneath, holding a tall gold "
            "scepter topped with a sapphire, commanding broad-shouldered "
            "posture (NOT a knight in armor — wearing royal robes)"
        ),
    },
    "queen": {
        "ase_rel": "MAGE/Mage Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "QUEEN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "regal queen with long dark hair gathered under a gold crown "
            "studded with blue gems, flowing royal-blue gown with silver "
            "embroidery and white ermine collar, gold belt, hands folded "
            "elegantly (NOT a wizard, NOT holding any staff — empty hands)"
        ),
    },
    "soldier": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "SOLDIER/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "uniformed kingdom soldier in a polished steel breastplate over a "
            "blue tabard with a yellow lion crest, conical steel helmet, "
            "round wooden shield strapped to back, sheathed sword at hip, "
            "blue trousers, brown boots, disciplined alert military posture "
            "(more elite and uniformed than a town guard)"
        ),
    },
    "farmer": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "FARMER/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "weathered peasant farmer with sun-tanned face, plain off-white "
            "shirt with rolled sleeves, brown suspenders, beige trousers, "
            "worn boots, wide-brimmed straw hat, holding a wooden hoe over "
            "one shoulder, friendly hardworking posture (NOT armored, NOT "
            "carrying any weapon — just a farming tool)"
        ),
    },
    "fisherman": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "FISHERMAN/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "weather-beaten coastal fisherman with grizzled gray beard, navy "
            "blue knit cap, brown weatherproof oilskin coat over a striped "
            "shirt, knee-high rubber boots, holding a long bamboo fishing "
            "rod over one shoulder, leathery tanned face (NOT a sailor "
            "captain, NOT a pirate — just a humble fisherman)"
        ),
    },
    "monk": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "MONK/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "contemplative monk in a simple coarse brown monastic robe with "
            "the hood pulled up, rope belt at the waist, wooden prayer beads "
            "around the neck, plain leather sandals, hands folded inside the "
            "sleeves in front, partially-shaved tonsured head visible inside "
            "the hood, peaceful meditative posture (NOT holding any staff or "
            "weapon, NOT a cleric with an ankh — pure ascetic)"
        ),
    },
    "traveler": {
        "ase_rel": "ROGUE/Rogue Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "TRAVELER/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "weathered wandering traveler with a brown leather travel cloak "
            "over a green tunic, brown trousers, sturdy boots, large bulging "
            "leather backpack on shoulders, wide-brimmed brown hat, holding "
            "a plain wooden walking staff (NOT magical, just for hiking), "
            "dusty road-worn appearance (NOT an archer, NOT a rogue assassin "
            "— just a wandering pilgrim)"
        ),
    },
    "dr_temporal": {
        "ase_rel": "MAGE/Mage Main design.aseprite",  # robed silhouette anchor
        "idle_tag": "idle",
        "drive_dir": "DR_TEMPORAL/claude",
        "drive_root": "NPCs",
        "dest_root": "npcs",
        "char_desc": (
            "eccentric mad-scientist time researcher in a long off-white lab "
            "coat over a deep purple waistcoat and dark trousers, wild grey "
            "hair sticking up at odd angles, brass steampunk goggles pushed "
            "up onto the forehead, holding a glowing brass pocket-watch in "
            "one hand and a leather notebook tucked under the other arm, "
            "polished black shoes, slightly hunched scholarly posture, "
            "ink-stained fingers (NOT a wizard with a magic staff, NOT a "
            "cleric — pure 19th-century inventor/researcher aesthetic, "
            "the kind of person who would build a portal in their workshop)"
        ),
    },
}

PROMPT_TEMPLATE = """Generate a 4-direction walk-cycle sprite sheet for a {char_desc}.

Output format — match this exactly:
  - 1024x1024 canvas, transparent background, organized as a 4-row by 4-column GRID of 256x256 cells
  - Each cell contains ONE frame of the character at chibi scale (the character should fill ~70% of the cell vertically)
  - Top-down 3/4 JRPG overworld view (camera angle ~30 degrees above horizon, similar to classic 16-bit RPGs)

Row layout (top to bottom):
  Row 0: walking SOUTH (facing the viewer, front view — face visible, character's chest/front)
  Row 1: walking WEST (side profile facing left, only one ear visible)
  Row 2: walking EAST (side profile facing right, only one ear visible — mirror of row 1)
  Row 3: walking NORTH (back view — character is FACING AWAY from camera. ONLY the back of
         the head is visible — NO eyes, NO mouth, NO front-facing facial features. The
         character's hair/hood/hat is shown from behind. Their back/shoulders are visible,
         not their chest. Same outfit but viewed from the rear. THIS IS NOT NEGOTIABLE —
         row 3 MUST show the character from behind, not another front or side view.)

Column layout (left to right) — standard 4-frame walk cycle:
  Col 0: standing pose (legs together)
  Col 1: right-foot-forward stride
  Col 2: standing pose (legs together)
  Col 3: left-foot-forward stride

Style:
  - 16-bit JRPG pixel-art aesthetic (think Final Fantasy V, Chrono Trigger, EarthBound overworld sprites)
  - Crisp pixel boundaries, NO anti-aliasing, NO smooth gradients
  - Character identity (palette, hair, equipment) MUST match Reference Image 1 (the artist's battle sprite)
  - Frame format, chibi proportions, and viewing angle MUST match Reference Image 2 (the existing chibi reference)
  - Transparent background (alpha channel)
  - Each cell is 256x256, character roughly centered, no overflow between cells

Return only the 4x4 grid sprite sheet — no labels, no borders, no annotations."""


def pad_to_square(img: Image.Image, size: int = 1024) -> bytes:
    """Pad image with transparency to a square of the given size, return PNG bytes."""
    img = img.convert("RGBA")
    w, h = img.size
    scale = min(size / w, size / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    img = img.resize((nw, nh), Image.NEAREST)
    sq = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sq.paste(img, ((size - nw) // 2, (size - nh) // 2), img)
    buf = io.BytesIO()
    sq.save(buf, format="PNG")
    return buf.getvalue()


def export_idle_frame(ase_path: Path, idle_tag: str, out_png: Path) -> None:
    subprocess.run(
        ["aseprite", "-b", "--tag", idle_tag, "--frame-range", "0,0",
         "--sheet", str(out_png), str(ase_path)],
        check=True, capture_output=True,
    )


def _git_show_png(rel: str, out_png: Path) -> bool:
    """Recover a tracked PNG from git HEAD of the game repo. HEAD, not the worktree:
    a reference has to be the committed art, or a half-finished edit anchors the run."""
    res = subprocess.run(
        ["git", "show", f"HEAD:{rel}"],
        cwd=GAME_REPO, capture_output=True,
    )
    if res.returncode != 0:
        return False
    out_png.write_bytes(res.stdout)
    return True


def get_proc_gen_chibi(job: str, out_png: Path) -> bool:
    """Recover the proc-gen 128x128 chibi reference from git HEAD of the game repo."""
    return _git_show_png(f"assets/sprites/jobs/{job}/overworld.png", out_png)


def _manifest_frame_size(rel: str) -> tuple[int, int] | None:
    """Declared (frame_width, frame_height) for a sheet path, from the game's own manifest. None
    when the sheet is unregistered — then the caller infers and divisibility is the only guard.
    Returns BOTH dimensions deliberately: reading width and then reusing it as height is the same
    majority-as-universal mistake one level down, and is how a second wrong constant hides behind
    a corrected first one (cowir-story on cowir-music's 48k/mono, 2026-09-11)."""
    try:
        man = json.loads((GAME_REPO / "data" / "sprite_manifest.json").read_text())
    except Exception:
        return None
    want = f"res://{rel}"
    for section in man.values():
        if not isinstance(section, dict):
            continue
        for entry in section.values():
            if isinstance(entry, dict) and entry.get("path") == want:
                fw, fh = entry.get("frame_width"), entry.get("frame_height")
                return (int(fw), int(fh)) if fw and fh else None
    return None


def export_battle_frame(rel: str, frame: int, out_png: Path) -> bool:
    """Cut one frame out of a horizontal battle strip as the identity reference.
    Monsters have no artist .aseprite — their own battle sheet IS the identity anchor."""
    raw = TMP / "_strip_src.png"
    if not _git_show_png(rel, raw):
        return False
    strip = Image.open(raw).convert("RGBA")
    # Prefer the MANIFEST's declared frame width over inferring it from the sheet. Inference
    # ("strips are square-framed") is true for 112 of 112 registered monster sheets as of
    # 2026-09-11 — a corpus fact, not a law, and cowir-music lost 19 of 165 audio beds to exactly
    # this shape: a majority measured, written down as universal, and the word "measured" is what
    # stopped anyone re-checking it. The manifest states the answer, so do not guess it.
    declared = _manifest_frame_size(rel)
    fw, fh = declared if declared else (strip.height, strip.height)
    if strip.width % fw != 0:
        print(f"ERROR: {rel} is {strip.size} — not a whole number of {fw}px-wide frames")
        return False
    if strip.height != fh:
        print(f"ERROR: {rel} is {strip.height}px tall but the manifest declares {fh}px frames")
        return False
    n = strip.width // fw
    if not 0 <= frame < n:
        print(f"ERROR: {rel} has {n} frames; asked for index {frame}")
        return False
    strip.crop((frame * fw, 0, (frame + 1) * fw, fh)).save(out_png)
    return True


def build_aseprite_from_strip(strip_png: Path, out_aseprite: Path) -> None:
    subprocess.run(
        ["aseprite", "-b", "--script-param", f"strip={strip_png}",
         "--script-param", f"out={out_aseprite}",
         "--script", str(REPO / "tools" / "build_overworld_aseprite.lua")],
        check=True, capture_output=True,
    )


def upload_to_drive(local_file: Path, drive_subdir: str, drive_root: str = DEFAULT_DRIVE_ROOT) -> None:
    drive_path = f"gdrive: cowir/assets/sprites/Game graphics - {drive_root}/{drive_subdir}"
    subprocess.run(
        ["rclone", "copy", str(local_file), drive_path],
        check=True, capture_output=True,
    )


def _pc_from_ase_rel(ase_rel: str) -> str:
    """Extract PC job name from an ase_rel like 'CLERIC/Cleric Main design.aseprite'."""
    return ase_rel.split("/", 1)[0].lower()


# Monsters — the same two-reference pattern, both references sourced differently.
# Identity is the monster's OWN battle strip (no artist .aseprite exists); format is an
# existing 128x128 overworld monster grid rather than a PC's chibi.
#
# Game-side deploy:  assets/sprites/monsters/overworld/<key>.png   (FLAT, not <key>/overworld.png)
# Drive aseprite:    cowir/assets/sprites/Game graphics - Monsters/<MONSTER>/claude/
MONSTER_SOURCES = {
    "dark_knight": {
        "identity_rel": "assets/sprites/monsters/dark_knight.png",
        "identity_frame": 0,
        # skeleton is the format anchor because its four rows genuinely DIFFER — front,
        # two profiles and a real back view. Most monster sheets repeat one pose 4x.
        "format_rel": "assets/sprites/monsters/overworld/skeleton.png",
        "drive_dir": "DARK_KNIGHT/claude",
        "drive_root": "Monsters",
        "dest_root": "monsters/overworld",
        "dest_flat": True,
        "char_desc": (
            "towering armoured sentinel in near-black weathered plate mail, a tattered "
            "dark cloak, and a heavy greatsword held POINT-DOWN and PLANTED in the ground "
            "in front of it with both gauntlets resting on the pommel. Its face is a "
            "featureless black helm with a narrow visor slit lit by a VIOLET glow — the "
            "violet eye-slit is the only bright colour anywhere on the figure and must "
            "stay visible in every frame. It stands at rest, motionless and watching, "
            "never mid-charge and never with the sword raised"
        ),
        # RoamingMonster holds col 0 whenever _dir is zero and _face_player() re-frames to
        # (row, 0) — a stationary field elite renders col 0 of all FOUR rows and nothing else.
        # The walk strides are format filler here; the four resting poses are the whole asset.
        "prompt_extra": (
            "\n\nCRITICAL for this subject: it is a STATIONARY sentinel that turns in place "
            "to watch the player. Column 0 of every row is the pose that will actually be "
            "displayed — make all four column-0 frames a complete, symmetrical, weight-on-both-"
            "feet standing guard pose with the greatsword planted, and make row 3's column 0 an "
            "unmistakable view from BEHIND (back of the helm, cloak falling down the back, no "
            "visor and no violet glow visible from the rear). The four rows must be four clearly "
            "DIFFERENT viewing angles, not the same pose repeated."
        ),
    },
}


# Merged dispatch table — PC jobs, then NPCs, then monsters. Names must not collide.
ENTITY_SOURCES: dict[str, dict] = {**JOB_SOURCES, **NPC_SOURCES, **MONSTER_SOURCES}
assert len(ENTITY_SOURCES) == len(JOB_SOURCES) + len(NPC_SOURCES) + len(MONSTER_SOURCES), \
    "JOB_SOURCES, NPC_SOURCES and MONSTER_SOURCES must not share keys"


def refuse_hollow_grid(grid: Image.Image, entity: str, target: int = 32) -> None:
    """Refuse to write a sheet whose frames are empty. A keyed-out subject leaves a file with
    the right name, size and frame count, so nothing downstream notices; the 2026-09-09
    dark_knight run deployed 13-94 px frames and looked like a success in every log line.
    Thresholds match test_overworld_sheet_frame_contract: relative to the sheet's own median
    (catches a partial wipe) plus an absolute floor (catches a uniform one, where the median
    is empty too and the ratio reads a healthy 1.0)."""
    cols, rows = grid.width // target, grid.height // target
    a = grid.convert("RGBA").split()[3]
    ns = []
    for r in range(rows):
        for c in range(cols):
            cell = a.crop((c * target, r * target, (c + 1) * target, (r + 1) * target))
            ns.append(((r, c), sum(1 for v in cell.getdata() if v > 10)))
    counts = sorted(n for _, n in ns)
    med = counts[len(counts) // 2] if len(counts) % 2 else (counts[len(counts) // 2 - 1] + counts[len(counts) // 2]) / 2
    bad = [f"({c},{r})={n}px" for (r, c), n in ns
           if n < 32 or (med > 0 and n / med < 0.35)]
    if bad:
        raise SystemExit(
            f"REFUSING to write {entity}: {len(bad)} of {len(ns)} frames are empty "
            f"(median {int(med)}px) -- {', '.join(bad[:8])}. The art was lost in assembly, "
            f"not in generation; inspect the raw before spending another call."
        )


def grid_to_strip(grid: Image.Image) -> Image.Image:
    """Convert an N×4 by N×4 grid (frame size N inferred from height/4) to a (16N)×N strip."""
    N = grid.height // 4
    strip = Image.new("RGBA", (16 * N, N))
    for row in range(4):
        for col in range(4):
            cell = grid.crop((col * N, row * N, (col + 1) * N, (row + 1) * N))
            strip.paste(cell, ((row * 4 + col) * N, 0))
    return strip


def _strip_white_bg(img: Image.Image, color_tol: int = 28) -> Image.Image:
    """Border-flood chromakey: any pixel reachable from a canvas border via a
    similar-color flood is treated as background and set to transparent.

    GPT-Image-1 frequently ships an opaque background, sometimes pure white
    (255,255,255), sometimes off-white (e.g. 221,220,220 or 236,231,221).
    A simple threshold-based strip can't handle all of these without either
    leaking BG (when sum is below threshold) or eating valid near-white
    character pixels (priestess's white robe, queen's white ermine collar).

    Border flood is robust:
      • Sample the actual BG color at each of the 4 corners.
      • Mark all pixels within `color_tol` per-channel as candidate BG.
      • Use connected-components labelling; any component that touches a
        border AND contains a corner-seed color is marked transparent.
      • Inner near-white pixels (robes, highlights) are surrounded by
        figure pixels — distinct components — so they survive.

    `color_tol` is per-channel. 28 is wide enough to handle JPEG-y BG ripples
    without bleeding into character pixels.

    Also strips any pixels with alpha < 255 already (preserves prior alpha=0).
    """
    import numpy as np
    from scipy.ndimage import label

    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]
    rgb = arr[:, :, :3].astype(int)
    alpha = arr[:, :, 3]

    # Combine: any pixel within `color_tol` of ANY corner is a BG candidate.
    # Skip transparent corners: their RGB is meaningless (usually 0,0,0), and
    # seeding from it marks every near-black character pixel (hair, boots) as
    # BG — the alpha==0 rule below already covers transparent regions.
    bg_candidate = np.zeros((h, w), dtype=bool)
    for sy, sx in [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]:
        if alpha[sy, sx] == 0:
            continue
        seed_rgb = rgb[sy, sx]
        diff = np.abs(rgb - seed_rgb).max(axis=2)
        bg_candidate |= (diff <= color_tol)
    # Already-transparent pixels are also BG.
    bg_candidate |= (alpha == 0)

    # Connected components on the BG-candidate mask. 4-connectivity (default).
    labelled, n_components = label(bg_candidate)
    if n_components == 0:
        return img

    # Find every component that touches the canvas border. Those are real BG.
    border_labels = set()
    border_labels.update(np.unique(labelled[0, :]))
    border_labels.update(np.unique(labelled[-1, :]))
    border_labels.update(np.unique(labelled[:, 0]))
    border_labels.update(np.unique(labelled[:, -1]))
    border_labels.discard(0)  # 0 = "not BG candidate"

    if not border_labels:
        return img

    bg_mask = np.isin(labelled, list(border_labels))
    arr[bg_mask] = (0, 0, 0, 0)
    return Image.fromarray(arr, "RGBA")


def _binarize_alpha(img: Image.Image, threshold: int = 128) -> Image.Image:
    """Snap alpha to 0 or 255 — kills LANCZOS halos for crisp pixel-art edges."""
    r, g, b, a = img.split()
    a = a.point(lambda v: 255 if v >= threshold else 0)
    return Image.merge("RGBA", (r, g, b, a))


def _cell_to_chibi(cell: Image.Image, target: int = 32, *, strip: bool = True) -> Image.Image:
    """Strip near-white BG, square-pad, downscale to target×target chibi (LANCZOS→NEAREST), binarize alpha.

    strip=False for a cell cut from an ALREADY-stripped band. Re-keying a narrow cell is not
    idempotent and can wipe the subject: _strip_white_bg seeds from the four corners, and a
    241px-wide crop around a near-black figure can put a CORNER on the figure's own cloak.
    The seed is then near-black, `diff <= color_tol` marks every dark pixel in the cell as
    background, and the component reaches the border — so the whole figure is keyed out.
    Measured on dark_knight: the same figure kept 2658 of ~59000 px through the second strip
    while the band-wide strip left it perfectly intact. The existing alpha==0 corner guard
    does not cover this: the poisoned corner is opaque, just dark."""
    if strip:
        cell = _strip_white_bg(cell.copy())
    bbox = cell.getbbox()
    if bbox:
        cell = cell.crop(bbox)
    cw, ch = cell.size
    side = max(cw, ch)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(cell, ((side - cw) // 2, (side - ch) // 2), cell)
    intermediate = max(target, target * 2 + target // 2)  # e.g. 80 for target=32, 160 for target=64
    chibi = sq.resize((intermediate, intermediate), Image.LANCZOS).resize((target, target), Image.NEAREST)
    return _binarize_alpha(chibi)


def _cell_to_chibi_32(cell: Image.Image) -> Image.Image:
    """Backwards-compatible alias for the 32×32 path."""
    return _cell_to_chibi(cell, 32)


def _detect_chibi_x_ranges(row_band: Image.Image, min_blob_width: int = 40) -> list[tuple[int, int]]:
    """
    Find x-ranges of distinct chibis in a horizontal band.
    Two-stage: try density-gap detection first (works when chibis have gaps); fall
    back to local-minima split (works when chibis are touching).
    """
    import numpy as np
    arr = np.array(row_band)  # H x W x 4
    col_density = (arr[:, :, 3] > 0).sum(axis=0).astype(float)
    smoothed = np.convolve(col_density, np.ones(8) / 8, mode="same")
    W = len(smoothed)

    # Stage 1: density-gap detection (chibis separated by clear empty gutters)
    threshold = max(5.0, float(smoothed.max()) * 0.15)
    gap_blobs: list[tuple[int, int]] = []
    in_blob, start = False, 0
    for x in range(W):
        if smoothed[x] > threshold and not in_blob:
            start, in_blob = x, True
        elif smoothed[x] <= threshold and in_blob:
            if x - start >= min_blob_width:
                gap_blobs.append((start, x))
            in_blob = False
    if in_blob and W - start >= min_blob_width:
        gap_blobs.append((start, W))

    # If gap detection produced multiple chibis, trust it.
    if len(gap_blobs) >= 2:
        return gap_blobs

    # Stage 2: chibis are touching with shallow valleys between them.
    # Find density peaks (chibi centers) by looking for local maxima, then split
    # the row at the midpoints between consecutive peaks.
    if not gap_blobs:
        return []
    full = gap_blobs[0]
    blob_start, blob_end = full
    inside_density = smoothed[blob_start:blob_end]
    if len(inside_density) < min_blob_width * 2:
        return [full]

    big_smooth = np.convolve(col_density, np.ones(40) / 40, mode="same")[blob_start:blob_end]
    peaks: list[int] = []
    window = min_blob_width
    peak_threshold = float(big_smooth.max()) * 0.7
    for x in range(window, len(big_smooth) - window):
        if big_smooth[x] < peak_threshold:
            continue
        lo, hi = max(0, x - window), min(len(big_smooth), x + window)
        if big_smooth[x] >= big_smooth[lo:hi].max() - 1e-6:
            if not peaks or x - peaks[-1] >= min_blob_width:
                peaks.append(x)

    if len(peaks) < 2:
        return [full]

    # Cut at midpoints between consecutive peaks
    cuts = [(peaks[i] + peaks[i + 1]) // 2 for i in range(len(peaks) - 1)]

    out: list[tuple[int, int]] = []
    prev = 0
    for c in cuts:
        if c - prev >= min_blob_width:
            out.append((blob_start + prev, blob_start + c))
            prev = c
    if len(big_smooth) - prev >= min_blob_width:
        out.append((blob_start + prev, blob_end))

    return out if len(out) >= 2 else [full]


class RowCountMismatch(RuntimeError):
    """The raw has a row count the assembler cannot use. Recoverable by RE-ROLLING the
    generation, so batch callers catch this and retry; SystemExit would abort the batch on the
    first bad roll, which is worse than the defect it refuses."""


def _raw_row_runs(raw: Image.Image, min_band_h: int = 20) -> list[tuple[int, int]]:
    """Contiguous vertical runs of content. The single source both the band detector and the
    wrong-row-count refusal read, so they can never disagree about how many rows there are."""
    a = _strip_white_bg(raw.copy()).split()[3]
    W, H = raw.size
    px = a.load()
    filled = [any(px[x, y] > 10 for x in range(0, W, 2)) for y in range(H)]
    runs: list[tuple[int, int]] = []
    run: int | None = None
    for y, v in enumerate(filled):
        if v and run is None:
            run = y
        elif not v and run is not None:
            runs.append((run, y))
            run = None
    if run is not None:
        runs.append((run, H))
    return [r for r in runs if r[1] - r[0] >= min_band_h]


def _count_row_bands(raw: Image.Image) -> int:
    return len(_raw_row_runs(raw))


def _detect_row_bands(raw: Image.Image, expected: int = 3, min_band_h: int = 20) -> list[tuple[int, int]] | None:
    """Row bands from CONTENT gaps rather than an equal split of the canvas.

    This is a SCALE fix, not a correctness one — the subject-wiping bug that led here was
    _cell_to_chibi's second chromakey, fixed separately. An equal split assumes the model
    centres each row in its third; measured on the dark_knight run content sat at y 46-391 /
    416-759 / 776-1024 against assumed 0-341 / 341-682 / 682-1023. A band that does not hug
    its row carries dead space into _cell_to_chibi's square-pad, and the figure is shrunk to
    fit it: row 2 came out 492/470/483 opaque px on equal bands versus 706/680/693 on these,
    the same art at 43% more pixels. Returns None when the gap structure does not yield
    exactly `expected` bands, so the caller keeps the equal split rather than guessing.
    """
    H = raw.size[1]
    bands = _raw_row_runs(raw, min_band_h)
    if len(bands) != expected:
        return None
    # Grow each band into its neighbouring gap so outlines are not clipped, without
    # letting two bands overlap.
    out: list[tuple[int, int]] = []
    for i, (y0, y1) in enumerate(bands):
        top = 0 if i == 0 else (bands[i - 1][1] + y0) // 2
        bot = H if i == len(bands) - 1 else (y1 + bands[i + 1][0]) // 2
        out.append((top, bot))
    return out


def _extract_row_chibis(raw: Image.Image, y0: int, y1: int, target: int = 32) -> list[Image.Image]:
    """
    Detect chibi positions in a horizontal band and return a target×target chibi for each.
    Strips white BG before detection so positions are accurate.
    """
    band = raw.crop((0, y0, raw.width, y1))
    band_stripped = _strip_white_bg(band.copy())
    ranges = _detect_chibi_x_ranges(band_stripped)
    chibis: list[Image.Image] = []
    for x0, x1 in ranges:
        # Pad a bit horizontally so we don't clip outline edges
        pad = 8
        x0p = max(0, x0 - pad)
        x1p = min(raw.width, x1 + pad)
        chibis.append(_cell_to_chibi(
            band_stripped.crop((x0p, 0, x1p, band_stripped.height)), target, strip=False))
    return chibis


def _build_4frame_walk(chibis: list[Image.Image]) -> list[Image.Image]:
    """
    Pad the detected chibis to a 4-frame walk cycle [F0, F1, F0, F2] — classic
    stand/right-stride/stand/left-stride. Whatever GPT produced becomes:
      3 chibis  → [c0, c1, c0, c2]   ← typical case
      2 chibis  → [c0, c1, c0, c1]
      1 chibi   → [c0, c0, c0, c0]   ← static, fallback
      4+ chibis → first 4
    """
    if not chibis:
        empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        return [empty] * 4
    if len(chibis) == 1:
        return [chibis[0]] * 4
    if len(chibis) == 2:
        return [chibis[0], chibis[1], chibis[0], chibis[1]]
    if len(chibis) >= 3:
        return [chibis[0], chibis[1], chibis[0], chibis[2]]
    return chibis[:4]


def head_lock_row(row_frames: list[Image.Image], head_frac: float = 0.65) -> list[Image.Image]:
    """Lock the upper-body of frames 1+ to match frame 0.

    GPT-Image-1 produces each frame independently, so head/torso/arm position
    drifts subtly from frame to frame. The 45% threshold (initial impl)
    caught the head but let the chest/shoulders through, which the user
    reported as "the body kinda swivels a bit too in an unnatural fashion"
    after the first head-lock pass. Default raised to 65% — locks the full
    upper body (head + shoulders + torso + arms), animating only the legs.
    Closer to genuine SNES JRPG sprite convention.

    Mirror property: applied BEFORE side-row mirroring in assemble_game_grid,
    so row 1 = mirror(row 2) still holds after locking (the mirrored upper
    body is itself an identical mirror of frame 0's mirrored upper body).
    """
    import numpy as np
    if len(row_frames) < 2:
        return row_frames
    f0_arr = np.array(row_frames[0])
    if f0_arr.shape[2] != 4:
        return row_frames
    alpha0 = f0_arr[:, :, 3] > 0
    if not alpha0.any():
        return row_frames
    ys = np.where(alpha0.any(axis=1))[0]
    y_top = int(ys.min())
    y_bot = int(ys.max())
    head_h = max(1, int((y_bot - y_top + 1) * head_frac))
    y_lock_end = min(f0_arr.shape[0], y_top + head_h)

    head_slice = f0_arr[y_top:y_lock_end, :, :].copy()

    out = [row_frames[0]]
    for f in row_frames[1:]:
        a = np.array(f).copy()
        # Wholesale replace the head-band region (preserves transparency around
        # the head from frame 0, doesn't smear with target's existing head).
        a[y_top:y_lock_end, :, :] = head_slice
        out.append(Image.fromarray(a, "RGBA"))
    return out


def assemble_game_grid(raw_1024: Image.Image, target: int = 32, *, head_lock: bool = True) -> Image.Image:
    """
    Build a 4-row N×N walk-cycle grid (N = target * 4) from GPT's 3-row chibi output.
    Side row is mirrored to fill east. Frames within each row use a
    [F0, F1, F0, F2] stand/right/stand/left cycle.

    Row mapping (matches game-side OverworldPlayer Direction enum order):
      row 0 = DOWN  (front)
      row 1 = LEFT  ← mirrored GPT side row (GPT defaults to right-facing)
      row 2 = RIGHT ← unmodified GPT side row
      row 3 = UP    (back)

    head_lock: when True (default), each row's frames 1/2/3 have their
    upper ~65% replaced with frame 0's upper region — kills the inter-frame
    head AND body swivel artefacts while preserving leg motion. Side rows
    are locked BEFORE mirroring so row 1 = mirror(row 2) still holds.
    """
    from PIL import ImageOps
    H = raw_1024.height
    NUM_ROWS = 3
    row_h = H // NUM_ROWS
    bands = _detect_row_bands(raw_1024, NUM_ROWS)
    if bands is None:
        # Detection failed OR the model returned a different number of rows. Those need opposite
        # responses, and conflating them is what produced 40 broken sheets on 2026-09-07: the
        # 3-row assumption applied to a 2-ROW raw puts band 1 on the inter-row GAP plus the TOP
        # of row 2, so every sheet came out with a floating hat/hair/crown and no body in the
        # side rows. The detector SAW the count was wrong and the fallback threw that away.
        found = _count_row_bands(raw_1024)
        if found >= 1 and found != NUM_ROWS:
            raise RowCountMismatch(
                f"REFUSING to assemble: the raw has {found} content row(s), not {NUM_ROWS}. "
                f"Splitting it {NUM_ROWS} ways lands a band on the gap between rows and yields "
                f"heads without bodies. Re-roll the generation; do not widen this check."
            )
        bands = [(i * row_h, (i + 1) * row_h) for i in range(NUM_ROWS)]
    sheet_w = target * 4
    sheet_h = target * 4

    grid = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

    # Row 0: walk_down (front)
    front = _build_4frame_walk(_extract_row_chibis(raw_1024, *bands[0], target))
    if head_lock:
        front = head_lock_row(front)
    for col, frame in enumerate(front):
        grid.paste(frame, (col * target, 0))

    # Rows 1+2: walk_left / walk_right.
    # GPT outputs the side view as RIGHT-facing (industry-default chibi
    # orientation). Game expects row 1 = LEFT, row 2 = RIGHT, so the GPT
    # frame is *mirrored* into row 1 and placed unmodified into row 2.
    # Head-lock is applied to the unmirrored row first; the mirroring then
    # produces a left-row whose head is the mirror of the right-row's head,
    # which is also pixel-identical across its own frames. Mirror property
    # asserted by test_overworld_facing_regression.gd is preserved.
    side = _build_4frame_walk(_extract_row_chibis(raw_1024, *bands[1], target))
    if head_lock:
        side = head_lock_row(side)
    for col, frame in enumerate(side):
        grid.paste(ImageOps.mirror(frame), (col * target, target))
        grid.paste(frame, (col * target, target * 2))

    # Row 3: walk_up (back)
    back = _build_4frame_walk(_extract_row_chibis(raw_1024, *bands[2], target))
    if head_lock:
        back = head_lock_row(back)
    for col, frame in enumerate(back):
        grid.paste(frame, (col * target, target * 3))

    return grid


def head_lock_existing_grid(grid: Image.Image, head_frac: float = 0.65) -> Image.Image:
    """Apply head-lock to an already-assembled 4-row N-frame walk grid.

    For starters whose canonical PNG is on `main` (e.g. cowir-main re-swapped
    rogue/cleric rows manually after my pipeline change), we want to head-lock
    in place WITHOUT going through the GPT pipeline.

    Splits the input grid into 4 rows, head-locks each row independently,
    re-pastes. Each row's mirror property must already be correct in the
    input (we don't re-mirror).
    """
    W, H = grid.size
    target = H // 4
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for row_idx in range(4):
        frames = []
        for col in range(4):
            cell = grid.crop((col * target, row_idx * target, (col + 1) * target, (row_idx + 1) * target))
            frames.append(cell)
        locked = head_lock_row(frames, head_frac=head_frac)
        for col, f in enumerate(locked):
            out.paste(f, (col * target, row_idx * target))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--entity", "--job", dest="entity", required=True,
        choices=sorted(ENTITY_SOURCES.keys()),
        help="PC job (fighter/cleric/...) or NPC archetype (old_man/guard/...)",
    )
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-upload", action="store_true",
                    help="Skip Drive upload (for local testing)")
    args = ap.parse_args()

    cfg = ENTITY_SOURCES[args.entity]
    dest_root = cfg.get("dest_root", DEFAULT_DEST_ROOT)
    drive_root = cfg.get("drive_root", DEFAULT_DRIVE_ROOT)
    is_npc = args.entity in NPC_SOURCES
    is_monster = args.entity in MONSTER_SOURCES

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ERROR: OPENAI_API_KEY not set. Run: source setenv.sh")
        sys.exit(1)

    entity_tmp = TMP / args.entity
    entity_tmp.mkdir(parents=True, exist_ok=True)
    artist_png = entity_tmp / "ref_artist_battle.png"
    chibi_png = entity_tmp / "ref_procgen_chibi.png"
    raw_out = entity_tmp / "gpt_raw_1024.png"
    grid_out = entity_tmp / f"{args.entity}_overworld_grid.png"
    strip_out = entity_tmp / f"{args.entity}_overworld_strip.png"
    aseprite_out = entity_tmp / f"{args.entity}_overworld.aseprite"

    if grid_out.exists() and aseprite_out.exists() and not args.force:
        print("outputs exist — pass --force to regenerate")
        return

    # 1. Prepare references
    print("[1] preparing references")
    if is_monster:
        # Identity from the monster's own battle strip; format from a sibling overworld grid.
        if not export_battle_frame(cfg["identity_rel"], cfg["identity_frame"], artist_png):
            print(f"ERROR: cannot cut identity frame from {cfg['identity_rel']} at game repo HEAD")
            sys.exit(1)
        format_src = cfg["format_rel"]
        if not _git_show_png(format_src, chibi_png):
            print(f"ERROR: cannot recover format ref {format_src} from game repo HEAD")
            sys.exit(1)
    else:
        ase_path = DRIVE_LOCAL / cfg["ase_rel"]
        if not ase_path.exists():
            print(f"ERROR: artist source missing: {ase_path}")
            sys.exit(1)
        export_idle_frame(ase_path, cfg["idle_tag"], artist_png)

        # NPCs have no proc-gen overworld of their own — borrow the chibi format
        # reference from the PC whose ase_rel they're anchored to (e.g. old_man
        # uses cleric's overworld.png as its scale/angle reference).
        chibi_ref_job = _pc_from_ase_rel(cfg["ase_rel"]) if is_npc else args.entity
        if not get_proc_gen_chibi(chibi_ref_job, chibi_png):
            print(f"ERROR: cannot recover proc-gen chibi ref ({chibi_ref_job}) from game repo HEAD")
            sys.exit(1)
        format_src = f"assets/sprites/jobs/{chibi_ref_job}/overworld.png"

    artist_bytes = pad_to_square(Image.open(artist_png), 1024)
    chibi_bytes = pad_to_square(Image.open(chibi_png), 1024)

    prompt = PROMPT_TEMPLATE.format(char_desc=cfg["char_desc"]) + cfg.get("prompt_extra", "")
    if args.dry_run:
        print(f"[dry-run] would call gpt-image-1 (quality={args.quality}) with 2 refs:")
        print(f"  ref 1 (identity): {artist_png}")
        print(f"  ref 2 (format):   {chibi_png}  ← {format_src}")
        leaf = f"{args.entity}.png" if cfg.get("dest_flat") else f"{args.entity}/overworld.png"
        print(f"  deploy:           {GAME_REPO}/assets/sprites/{dest_root}/{leaf}")
        print(f"  drive:            Game graphics - {drive_root}/{cfg['drive_dir']}/")
        print(f"--- prompt ---\n{prompt}\n--- end prompt ---")
        return

    # 2. Call gpt-image-1
    print(f"[2] gpt-image-1 edit (quality={args.quality}, 2 refs, 1024x1024)")
    client = OpenAI(api_key=api_key)
    resp = client.images.edit(
        model="gpt-image-1",
        image=[
            ("ref_artist.png", artist_bytes, "image/png"),
            ("ref_chibi.png", chibi_bytes, "image/png"),
        ],
        prompt=prompt,
        size="1024x1024",
        quality=args.quality,
        n=1,
    )
    raw_b64 = resp.data[0].b64_json
    raw_img = Image.open(io.BytesIO(base64.b64decode(raw_b64))).convert("RGBA")
    raw_img.save(raw_out)
    print(f"   saved raw: {raw_out}")

    # 3. Build TWO outputs: 32px game PNG + 64px high-detail master
    print(f"[3] assemble dual outputs (32px game + 64px master)")
    grid_32 = assemble_game_grid(raw_img, target=32)
    refuse_hollow_grid(grid_32, args.entity)
    grid_32.save(grid_out)
    strip_32 = grid_to_strip(grid_32)
    strip_32.save(strip_out)

    grid_64 = assemble_game_grid(raw_img, target=64)
    grid64_out = entity_tmp / f"{args.entity}_overworld_grid_64.png"
    strip64_out = entity_tmp / f"{args.entity}_overworld_strip_64.png"
    grid_64.save(grid64_out)
    strip_64 = grid_to_strip(grid_64)
    strip_64.save(strip64_out)

    # 4. Build BOTH aseprite files (32px small + 64px master)
    print(f"[4] build tagged aseprites (32px small + 64px master)")
    build_aseprite_from_strip(strip_out, aseprite_out)
    aseprite_master = entity_tmp / f"{args.entity}_overworld_64.aseprite"
    build_aseprite_from_strip(strip64_out, aseprite_master)

    # 5. Upload BOTH aseprites to Drive (small + master)
    if not args.no_upload:
        print(f"[5] upload aseprites → gdrive: .../Game graphics - {drive_root}/{cfg['drive_dir']}/")
        upload_to_drive(aseprite_out, cfg["drive_dir"], drive_root)
        upload_to_drive(aseprite_master, cfg["drive_dir"], drive_root)
    else:
        print("[5] skipping upload (--no-upload)")

    # 6. Deploy to game
    # Monsters deploy FLAT (monsters/overworld/<id>.png); jobs and NPCs deploy into a
    # per-entity dir. The consumer path decides the shape, not the generator.
    dest = GAME_REPO / "assets" / "sprites" / dest_root / (
        f"{args.entity}.png" if cfg.get("dest_flat") else f"{args.entity}/overworld.png")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(grid_out.read_bytes())
    print(f"[6] deployed → {dest}")

    cost = {"low": 0.02, "medium": 0.07, "high": 0.19}.get(args.quality, 0.07)
    print(f"\nDONE — ~${cost:.2f} estimated")
    print(f"  raw 1024:   {raw_out}")
    print(f"  game PNG:   {dest}")
    print(f"  aseprite:   {aseprite_out}")


if __name__ == "__main__":
    main()
