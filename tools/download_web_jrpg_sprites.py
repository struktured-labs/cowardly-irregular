#!/usr/bin/env python3
"""
Download and process web-sourced JRPG pixel art sprites for LoRA training.

Sources (all free/CC licensed):
  - OpenGameArt.org packs (CC-BY, CC-BY-SA, CC0, Public Domain)
  - FLARE game sprites on GitHub (CC-BY-SA)
  - Wesnoth sprites (GPL/CC)

All sprites are processed through the same pipeline as curate_style_dataset.py:
  - Split sprite strips into individual frames
  - Auto-crop to character bounding box
  - Scale to 75% fill on a 512x512 canvas
  - Write caption .txt alongside each frame

Output: tools/lora_training/style_dataset/10_web_jrpg/
"""

import hashlib
import io
import json
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "tools" / "lora_training" / "style_dataset" / "10_web_jrpg"
RAW_CACHE_DIR = REPO_ROOT / "tmp" / "web_jrpg_raw"

CANVAS_SIZE = 512
TARGET_FILL = 0.75
FILL_MIN = 0.04
FILL_MAX = 0.88
ALPHA_THRESHOLD = 10

STYLE_TAG = "jrpg_pixel_style"

# ── Caption tables ──────────────────────────────────────────────────────────

CLASS_HINTS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"wizard|mage|caster|warlock|witch|sorcer", re.I), "mage"),
    (re.compile(r"cleric|priest|healer|bishop|nun", re.I), "cleric"),
    (re.compile(r"thief|rogue|assassin|ninja|ranger|scout", re.I), "rogue"),
    (re.compile(r"bard|singer|musician|troubadour", re.I), "bard"),
    (re.compile(r"paladin|holy|templar", re.I), "guardian"),
    (re.compile(r"knight|fighter|warrior|soldier|hero|guard", re.I), "fighter"),
    (re.compile(r"demon|devil|fiend|imp|dark", re.I), "monster demon"),
    (re.compile(r"dragon|wyvern|drake", re.I), "monster dragon"),
    (re.compile(r"goblin|orc|ogre|troll", re.I), "monster goblin"),
    (re.compile(r"undead|skeleton|zombie|ghost|lich", re.I), "monster undead"),
    (re.compile(r"slime|blob|jelly", re.I), "monster slime"),
    (re.compile(r"boss|lord|king|queen|master|leader", re.I), "boss"),
    (re.compile(r"female|woman|girl|lady|heroine", re.I), "female warrior"),
    (re.compile(r"dwarf", re.I), "dwarf warrior"),
    (re.compile(r"elf|elven", re.I), "elf warrior"),
    (re.compile(r"human|man|male|base", re.I), "fighter"),
]

POSE_HINTS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"idle|stand|default|rest", re.I), "idle stance"),
    (re.compile(r"walk|run|move", re.I), "walking pose"),
    (re.compile(r"attack|slash|hit|strike|swing|sword|cleave", re.I), "attack pose"),
    (re.compile(r"cast|spell|magic|fire|ice|thunder", re.I), "casting pose"),
    (re.compile(r"dead|death|die|dying|faint|collapse", re.I), "death pose"),
    (re.compile(r"hurt|damage|pain|react", re.I), "hit reaction"),
    (re.compile(r"defend|guard|block|shield", re.I), "defend stance"),
    (re.compile(r"victory|triumph|win|cheer|celebrate", re.I), "victory pose"),
    (re.compile(r"item|use|drink|potion", re.I), "item use pose"),
]


def infer_tags(name: str) -> tuple[str, str]:
    class_tag = "fantasy warrior"
    for pat, label in CLASS_HINTS:
        if pat.search(name):
            class_tag = label
            break
    pose_tag = "battle stance"
    for pat, label in POSE_HINTS:
        if pat.search(name):
            pose_tag = label
            break
    return class_tag, pose_tag


def make_caption(class_tag: str, pose_tag: str) -> str:
    return (
        f"{STYLE_TAG}, pixel art battle sprite, {class_tag} character, "
        f"{pose_tag}, black pixel outline, transparent background"
    )


# ── Image processing ─────────────────────────────────────────────────────────

def autocrop(img: Image.Image) -> Image.Image:
    a = img.split()[3]
    bbox = a.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0).getbbox()
    return img.crop(bbox) if bbox else img


def count_opaque(img: Image.Image) -> int:
    return sum(1 for p in img.split()[3].tobytes() if p > ALPHA_THRESHOLD)


def scale_to_fill(img: Image.Image) -> Image.Image:
    cw, ch = img.size
    target_px = int(CANVAS_SIZE * TARGET_FILL)
    scale = target_px / max(cw, ch)
    return img.resize((max(1, round(cw * scale)), max(1, round(ch * scale))), Image.NEAREST)


def place_on_canvas(sprite: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    sw, sh = sprite.size
    canvas.paste(sprite, ((CANVAS_SIZE - sw) // 2, (CANVAS_SIZE - sh) // 2), sprite)
    return canvas


def fill_ratio(canvas: Image.Image) -> float:
    return count_opaque(canvas) / (CANVAS_SIZE * CANVAS_SIZE)


def split_strip(img: Image.Image) -> list[Image.Image]:
    """Split a horizontal strip into square frames (frame size = image height)."""
    w, h = img.size
    if h == 0:
        return []
    n = w // h
    return [img.crop((i * h, 0, (i + 1) * h, h)) for i in range(max(1, n))]


def split_grid(img: Image.Image, fw: int, fh: int) -> list[Image.Image]:
    """Split a sprite sheet into frames given explicit frame dimensions."""
    w, h = img.size
    frames = []
    for row in range(h // fh):
        for col in range(w // fw):
            frames.append(img.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh)))
    return frames


def process_frames(
    frames: list[Image.Image],
    out_dir: Path,
    counter: list[int],
    class_tag: str,
    pose_tag: str,
    prefix: str = "sprite",
) -> tuple[int, int]:
    accepted = rejected = 0
    for frame in frames:
        try:
            rgba = frame.convert("RGBA")
            cropped = autocrop(rgba)
            if min(cropped.size) < 4:
                rejected += 1
                continue
            scaled = scale_to_fill(cropped)
            canvas = place_on_canvas(scaled)
            ratio = fill_ratio(canvas)
            if ratio < FILL_MIN or ratio > FILL_MAX:
                rejected += 1
                continue
            idx = counter[0]
            counter[0] += 1
            out_dir.mkdir(parents=True, exist_ok=True)
            canvas.save(out_dir / f"{prefix}_{idx:04d}.png", "PNG")
            (out_dir / f"{prefix}_{idx:04d}.txt").write_text(
                make_caption(class_tag, pose_tag), encoding="utf-8"
            )
            accepted += 1
        except Exception as exc:
            print(f"    frame error: {exc}")
            rejected += 1
    return accepted, rejected


def process_png(
    path: Path,
    out_dir: Path,
    counter: list[int],
    class_tag: str | None = None,
    pose_tag: str | None = None,
    frame_w: int | None = None,
    frame_h: int | None = None,
    prefix: str = "sprite",
) -> tuple[int, int]:
    try:
        with Image.open(path) as raw:
            img = raw.convert("RGBA")
    except Exception as exc:
        print(f"  SKIP  {path.name}: {exc}")
        return 0, 1

    ct, pt = infer_tags(path.stem)
    ct = class_tag or ct
    pt = pose_tag or pt

    w, h = img.size
    if frame_w and frame_h:
        frames = split_grid(img, frame_w, frame_h)
    elif w >= 2 * h:
        frames = split_strip(img)
    else:
        frames = [img]

    return process_frames(frames, out_dir, counter, ct, pt, prefix)


# ── Downloading ───────────────────────────────────────────────────────────────

def url_to_cache_path(url: str) -> Path:
    h = hashlib.md5(url.encode()).hexdigest()[:10]
    name = re.sub(r"[^\w.\-]", "_", url.split("/")[-1])[:60]
    return RAW_CACHE_DIR / f"{h}_{name}"


def download(url: str) -> Path | None:
    dest = url_to_cache_path(url)
    if dest.exists() and dest.stat().st_size > 100:
        return dest
    RAW_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"  DL  {url}")
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0 (sprite-dataset-builder/1.0)"},
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        dest.write_bytes(data)
        return dest
    except Exception as exc:
        print(f"  FAIL  {url}: {exc}")
        return None


def download_bytes(url: str) -> bytes | None:
    path = download(url)
    return path.read_bytes() if path else None


# ── Source processors ─────────────────────────────────────────────────────────

def process_zip(
    url: str,
    out_dir: Path,
    counter: list[int],
    name_filter: re.Pattern | None = None,
    class_tag: str | None = None,
    pose_tag: str | None = None,
    frame_w: int | None = None,
    frame_h: int | None = None,
    prefix: str = "sprite",
    max_files: int = 200,
) -> tuple[int, int]:
    data = download_bytes(url)
    if data is None:
        return 0, 0

    total_a = total_r = 0
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            png_names = [
                n for n in zf.namelist()
                if n.lower().endswith(".png") and not n.startswith("__MACOSX")
            ]
            if name_filter:
                png_names = [n for n in png_names if name_filter.search(n)]
            png_names = png_names[:max_files]
            for zname in png_names:
                stem = Path(zname).stem
                try:
                    img_data = zf.read(zname)
                    with Image.open(io.BytesIO(img_data)) as raw:
                        img = raw.convert("RGBA")
                except Exception as exc:
                    print(f"    skip {zname}: {exc}")
                    total_r += 1
                    continue

                ct, pt = infer_tags(stem)
                ct = class_tag or ct
                pt = pose_tag or pt

                w, h = img.size
                if frame_w and frame_h:
                    frames = split_grid(img, frame_w, frame_h)
                elif w >= 2 * h:
                    frames = split_strip(img)
                else:
                    frames = [img]

                a, r = process_frames(frames, out_dir, counter, ct, pt, prefix)
                total_a += a
                total_r += r
    except zipfile.BadZipFile as exc:
        print(f"  BAD ZIP {url}: {exc}")
    return total_a, total_r


def process_single_url(
    url: str,
    out_dir: Path,
    counter: list[int],
    class_tag: str | None = None,
    pose_tag: str | None = None,
    frame_w: int | None = None,
    frame_h: int | None = None,
    prefix: str = "sprite",
) -> tuple[int, int]:
    path = download(url)
    if path is None:
        return 0, 0
    return process_png(path, out_dir, counter, class_tag, pose_tag, frame_w, frame_h, prefix)


def process_github_dir(
    repo: str,
    dir_path: str,
    out_dir: Path,
    counter: list[int],
    class_tag: str | None = None,
    pose_tag: str | None = None,
    prefix: str = "sprite",
    recurse: bool = False,
    max_files: int = 80,
) -> tuple[int, int]:
    api_url = f"https://api.github.com/repos/{repo}/contents/{dir_path}"
    try:
        req = urllib.request.Request(
            api_url,
            headers={"User-Agent": "sprite-dataset-builder/1.0"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            listing = json.loads(resp.read())
    except Exception as exc:
        print(f"  FAIL GitHub listing {repo}/{dir_path}: {exc}")
        return 0, 0

    total_a = total_r = 0
    files_done = 0
    for entry in listing:
        if files_done >= max_files:
            break
        if entry["type"] == "file" and entry["name"].lower().endswith(".png"):
            raw_url = entry["download_url"]
            if raw_url:
                a, r = process_single_url(
                    raw_url, out_dir, counter, class_tag, pose_tag, prefix=prefix
                )
                total_a += a
                total_r += r
                files_done += 1
        elif recurse and entry["type"] == "dir":
            a, r = process_github_dir(
                repo, entry["path"], out_dir, counter, class_tag, pose_tag, prefix, recurse=False
            )
            total_a += a
            total_r += r
    return total_a, total_r


# ── Source manifest ───────────────────────────────────────────────────────────

# Each entry describes one source to pull and how to process it.
# Fields:
#   kind:       "zip_url" | "png_url" | "github_dir"
#   url/repo:   source location
#   label:      human-readable name for logging
#   class_tag:  override caption class (None = infer per filename)
#   pose_tag:   override caption pose (None = infer per filename)
#   prefix:     output filename prefix
#   frame_w/h:  explicit frame dimensions if grid sheet
#   name_filter: regex string to filter filenames inside a zip
#   dir_path:   for github_dir sources
#   recurse:    for github_dir sources

SOURCES: list[dict] = [
    # ── OpenGameArt battle character packs ────────────────────────────────
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/fantasy_character_sprites_battlers.zip",
        "label": "OGA Fantasy Character Sprites & Battlers",
        "class_tag": None,
        "pose_tag": None,
        "prefix": "oga_fantasy_battler",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/Battlers.zip",
        "label": "OGA JS Monster Pack 4 - Ascent (Battlers)",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "oga_jsmonster4",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/Sample.zip",
        "label": "OGA Sample RPG Enemy Sprite Pack",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "oga_sample_enemy",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/superpowers-asset-packs-characters.zip",
        "label": "OGA Superpowers Asset Packs - Characters",
        "class_tag": None,
        "pose_tag": None,
        "prefix": "oga_superpowers",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/WesnothSprites_1.zip",
        "label": "OGA Blarumyrran Wesnoth Sprites (Public Domain)",
        "class_tag": None,
        "pose_tag": "battle stance",
        "prefix": "oga_wesnoth_pd",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/plantenemies_battlers_charset.zip",
        "label": "OGA Plant & Mushroom Enemy Battlers",
        "class_tag": "monster plant",
        "pose_tag": "battle stance",
        "prefix": "oga_plant_enemy",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/tinytactics_battlekiti_v1_0.zip",
        "label": "OGA Tiny Tactics Battle Kit I",
        "class_tag": None,
        "pose_tag": "battle stance",
        "prefix": "oga_tiny_tactics",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/rpgsprites1.zip",
        "label": "OGA Antifarea RPG Sprite Set 1",
        "class_tag": None,
        "pose_tag": "battle stance",
        "prefix": "oga_antifarea",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/attack.zip",
        "label": "OGA Attack Animation",
        "class_tag": "fighter",
        "pose_tag": "attack pose",
        "prefix": "oga_attack_anim",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/PIxelantasy%20-%20FREE_0.zip",
        "label": "OGA Pixelantasy FREE",
        "class_tag": None,
        "pose_tag": None,
        "prefix": "oga_pixelantasy",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/human-male-base_0.zip",
        "label": "OGA Wesnoth Generic Human Male Base",
        "class_tag": "fighter",
        "pose_tag": "battle stance",
        "prefix": "oga_wesnoth_human_m",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/human-female-base.zip",
        "label": "OGA Wesnoth Generic Human Female Base",
        "class_tag": "female warrior",
        "pose_tag": "battle stance",
        "prefix": "oga_wesnoth_human_f",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/dwarf-male-base_1.zip",
        "label": "OGA Wesnoth Generic Dwarf Male",
        "class_tag": "dwarf warrior",
        "pose_tag": "battle stance",
        "prefix": "oga_wesnoth_dwarf",
    },
    {
        "kind": "zip_url",
        "url": "https://opengameart.org/sites/default/files/base-male-by-rubengc-1.1.zip",
        "label": "OGA Base Male Fighter",
        "class_tag": "fighter",
        "pose_tag": "idle stance",
        "prefix": "oga_base_male",
    },
    # ── Single PNG sprite sheets ──────────────────────────────────────────
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/Heroes_01.png",
        "label": "OGA JS Actors - Aeon Warriors Heroes Sheet",
        "class_tag": "fighter",
        "pose_tag": "battle stance",
        "prefix": "oga_aeon_heroes",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/leocephas6.png",
        "label": "OGA Leocephas FF6-ish Style RPG Miniboss",
        "class_tag": "boss",
        "pose_tag": "battle stance",
        "prefix": "oga_leocephas_ff6",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/elementals3big.png",
        "label": "OGA JS Monster Set Elementals III",
        "class_tag": "monster elemental",
        "pose_tag": "battle stance",
        "prefix": "oga_elementals3",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/laila_battle_sprite.png",
        "label": "OGA Allacrost Battle Sprite - Laila (64x128)",
        "class_tag": "female warrior",
        "pose_tag": "idle stance",
        "prefix": "oga_allacrost_laila",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/claudius_battle_sprite.png",
        "label": "OGA Allacrost Battle Sprite - Claudius (64x128)",
        "class_tag": "fighter",
        "pose_tag": "idle stance",
        "prefix": "oga_allacrost_claudius",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/9RPGenemies.PNG",
        "label": "OGA 9 RPG Enemies",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "oga_9rpg_enemies",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/9RPGenemies_0.PNG",
        "label": "OGA 9 RPG Enemies v2",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "oga_9rpg_enemies_v2",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/rpgcritter%20update%20formatted%20transparent.png",
        "label": "OGA RPG Critters Updated (16-32px enemies)",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "oga_rpg_critter",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/threeformsPJ2.png",
        "label": "OGA 3-Form RPG Boss Harlequin Epicycle",
        "class_tag": "boss",
        "pose_tag": "battle stance",
        "prefix": "oga_harlequin_boss",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/boss-malleus_0.png",
        "label": "OGA Boss Cohort - Malleus",
        "class_tag": "boss",
        "pose_tag": "battle stance",
        "prefix": "oga_boss_malleus",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/2xdemon-terradaemon.png",
        "label": "OGA Boss Cohort - Terra Daemon",
        "class_tag": "boss monster demon",
        "pose_tag": "battle stance",
        "prefix": "oga_boss_daemon",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/sotrak_rewop_0.png",
        "label": "OGA Sotrak Rewop RPG Battler",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "oga_sotrak",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/puck-th.png",
        "label": "OGA Puck Thief Character",
        "class_tag": "rogue",
        "pose_tag": "battle stance",
        "prefix": "oga_puck_thief",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/puck-bm.png",
        "label": "OGA Puck Wizard/Black Mage Character",
        "class_tag": "mage",
        "pose_tag": "battle stance",
        "prefix": "oga_puck_mage",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/Kayla.png",
        "label": "OGA Fantasy Character Battler - Kayla",
        "class_tag": "female warrior",
        "pose_tag": "battle stance",
        "prefix": "oga_kayla",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/Higan.png",
        "label": "OGA Fantasy Character Battler - Higan",
        "class_tag": "fighter",
        "pose_tag": "battle stance",
        "prefix": "oga_higan",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/Vance.png",
        "label": "OGA Fantasy Character Battler - Vance",
        "class_tag": "mage",
        "pose_tag": "battle stance",
        "prefix": "oga_vance",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/wizard%20spritesheet%20calciumtrice.png",
        "label": "OGA Animated Wizard Spritesheet",
        "class_tag": "mage",
        "pose_tag": "casting pose",
        "prefix": "oga_wizard_anim",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/RPGCharacterSprites32x32.png",
        "label": "OGA 32x32 RPG Character Sprites Sheet",
        "class_tag": None,
        "pose_tag": "battle stance",
        "frame_w": 32,
        "frame_h": 32,
        "prefix": "oga_rpg32",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/RPGSoldier32x32.png",
        "label": "OGA RPG Soldier 32x32",
        "class_tag": "fighter",
        "pose_tag": "battle stance",
        "frame_w": 32,
        "frame_h": 32,
        "prefix": "oga_soldier32",
    },
    # ── FLARE game sprites from GitHub (CC-BY-SA) ─────────────────────────
    {
        "kind": "github_dir",
        "repo": "flareteam/flare-game",
        "dir_path": "mods/fantasycore/images/enemies",
        "label": "FLARE Game - Enemy Sprites",
        "class_tag": "monster",
        "pose_tag": "battle stance",
        "prefix": "flare_enemy",
    },
    # ── LPC spritesheet body/torso (top-down but still pixel JRPG style) ──
    {
        "kind": "github_dir",
        "repo": "jrconway3/Universal-LPC-spritesheet",
        "dir_path": "body",
        "label": "LPC Universal Spritesheet - Body",
        "class_tag": "fighter",
        "pose_tag": "battle stance",
        "prefix": "lpc_body",
        "recurse": True,
    },
    {
        "kind": "github_dir",
        "repo": "jrconway3/Universal-LPC-spritesheet",
        "dir_path": "torso",
        "label": "LPC Universal Spritesheet - Torso",
        "class_tag": "fighter",
        "pose_tag": "idle stance",
        "prefix": "lpc_torso",
        "recurse": True,
    },
    # ── Additional OGA packs discovered ──────────────────────────────────
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/plant_enemy_01.png",
        "label": "OGA Plant Enemy 01",
        "class_tag": "monster plant",
        "pose_tag": "battle stance",
        "prefix": "oga_plant01",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/plant_enemy_02.png",
        "label": "OGA Plant Enemy 02",
        "class_tag": "monster plant",
        "pose_tag": "battle stance",
        "prefix": "oga_plant02",
    },
    {
        "kind": "png_url",
        "url": "https://opengameart.org/sites/default/files/plant_enemy_05.png",
        "label": "OGA Plant Enemy 05",
        "class_tag": "monster plant",
        "pose_tag": "battle stance",
        "prefix": "oga_plant05",
    },
]

# ── Additional OGA pages to scrape for more PNG/ZIP links ────────────────────

EXTRA_OGA_SLUGS: list[dict] = [
    {"slug": "twelve-16x18-rpg-sprites-plus-base", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_12rpg_sprites"},
    {"slug": "js-monster-set-elementals-iii", "class_tag": "monster elemental", "pose_tag": "battle stance", "prefix": "oga_elementals3_extra"},
    {"slug": "wesnoth-frankenpack", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_wesnoth_frank"},
    {"slug": "gilgaphoenixignis-rpg-ennemy-sprite-pack", "class_tag": "monster", "pose_tag": "battle stance", "prefix": "oga_gilga_enemy"},
    {"slug": "isaiah658s-pixel-pack-2", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_isaiah_pack2"},
    {"slug": "24x32-heroine-lyuba-sprites-faces-pictures", "class_tag": "female warrior", "pose_tag": "battle stance", "prefix": "oga_lyuba"},
    {"slug": "sara-wizard", "class_tag": "mage", "pose_tag": "casting pose", "prefix": "oga_sara_wizard"},
    {"slug": "boss-cohort", "class_tag": "boss", "pose_tag": "battle stance", "prefix": "oga_boss_cohort"},
    {"slug": "rpg-maker-2003-compatible-furry-characters", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_furry_rpg"},
    {"slug": "antifareas-rpg-sprite-set-1-enlarged-w-transparent-background-fixed", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_antifarea_fixed"},
    {"slug": "lpc-in-battle-rpg-sprites", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_lpc_battle"},
    {"slug": "pixel-hero-base-classic", "class_tag": "fighter", "pose_tag": "idle stance", "prefix": "oga_pixel_hero"},
    {"slug": "edited-and-extended-24x32-character-pack", "class_tag": None, "pose_tag": "battle stance", "prefix": "oga_24x32_char"},
]


def scrape_and_process_oga_slug(
    slug: str,
    out_dir: Path,
    counter: list[int],
    class_tag: str | None,
    pose_tag: str | None,
    prefix: str,
) -> tuple[int, int]:
    """Scrape an OGA page for PNG/ZIP links and process them."""
    url = f"https://opengameart.org/content/{slug}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as exc:
        print(f"  FAIL scrape {slug}: {exc}")
        return 0, 0

    # Extract PNG and ZIP links from OGA files server
    links = re.findall(
        r'href="((?:https?://opengameart\.org|)/sites/default/files/[^"]+\.(?:png|PNG|zip|ZIP))"',
        html,
        re.I,
    )
    links = list(dict.fromkeys(  # deduplicate, preserve order
        ("https://opengameart.org" + l if l.startswith("/") else l) for l in links
    ))

    total_a = total_r = 0
    for link in links[:10]:
        if link.lower().endswith(".zip"):
            a, r = process_zip(link, out_dir, counter, class_tag=class_tag, pose_tag=pose_tag, prefix=prefix)
        else:
            a, r = process_single_url(link, out_dir, counter, class_tag=class_tag, pose_tag=pose_tag, prefix=prefix)
        total_a += a
        total_r += r
    return total_a, total_r


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    RAW_CACHE_DIR.mkdir(parents=True, exist_ok=True)

    counter = [0]
    grand_accepted = 0
    grand_rejected = 0
    results: list[dict] = []

    all_sources = list(SOURCES)

    # Add scraped OGA slugs to the source list
    for entry in EXTRA_OGA_SLUGS:
        all_sources.append({
            "kind": "_oga_slug",
            "slug": entry["slug"],
            "label": f"OGA scraped: {entry['slug']}",
            "class_tag": entry.get("class_tag"),
            "pose_tag": entry.get("pose_tag"),
            "prefix": entry.get("prefix", "oga_scrape"),
        })

    for src in all_sources:
        label = src.get("label", src.get("url", src.get("slug", "?")))
        print(f"\n[{src['kind']}] {label}")

        ct = src.get("class_tag")
        pt = src.get("pose_tag")
        pfx = src.get("prefix", "sprite")

        if src["kind"] == "zip_url":
            a, r = process_zip(
                src["url"], OUTPUT_DIR, counter,
                class_tag=ct, pose_tag=pt,
                frame_w=src.get("frame_w"), frame_h=src.get("frame_h"),
                prefix=pfx,
                name_filter=re.compile(src["name_filter"]) if src.get("name_filter") else None,
            )
        elif src["kind"] == "png_url":
            a, r = process_single_url(
                src["url"], OUTPUT_DIR, counter,
                class_tag=ct, pose_tag=pt,
                frame_w=src.get("frame_w"), frame_h=src.get("frame_h"),
                prefix=pfx,
            )
        elif src["kind"] == "github_dir":
            a, r = process_github_dir(
                src["repo"], src["dir_path"], OUTPUT_DIR, counter,
                class_tag=ct, pose_tag=pt, prefix=pfx,
                recurse=src.get("recurse", False),
            )
        elif src["kind"] == "_oga_slug":
            a, r = scrape_and_process_oga_slug(
                src["slug"], OUTPUT_DIR, counter,
                class_tag=ct, pose_tag=pt, prefix=pfx,
            )
        else:
            print(f"  Unknown kind: {src['kind']}")
            continue

        grand_accepted += a
        grand_rejected += r
        results.append({"source": label, "accepted": a, "rejected": r})
        print(f"  => {a} accepted, {r} rejected (running total: {grand_accepted})")

        if grand_accepted >= 400:
            print(f"\nTarget of 400 frames reached. Stopping early.")
            break

    print("\n" + "=" * 60)
    print("SOURCE BREAKDOWN")
    print("=" * 60)
    for res in results:
        if res["accepted"] > 0:
            print(f"  {res['accepted']:4d}  {res['source']}")
    print("-" * 60)
    print(f"  Total accepted : {grand_accepted}")
    print(f"  Total rejected : {grand_rejected}")
    print(f"  Output dir     : {OUTPUT_DIR}")
    print(f"  Raw cache dir  : {RAW_CACHE_DIR}")

    if grand_accepted < 300:
        print(f"\nWARNING: Only got {grand_accepted} frames (target: 300+).")
        sys.exit(1)
    else:
        print(f"\nSUCCESS: {grand_accepted} training frames ready.")


if __name__ == "__main__":
    main()
