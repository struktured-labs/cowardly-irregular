#!/usr/bin/env python3
"""
Ingest new artist sprites from Google Drive archive into LoRA training dataset.

Processes all sprites from drive_archive/ into properly formatted training images:
  - Splits sprite strips into individual frames
  - Extracts key frames from animated GIFs
  - Autocrop + scale to 512x512 canvas (nearest-neighbor)
  - Writes captions for each frame
  - Organizes into appropriate training dataset buckets

Usage:
    uv run python tools/ingest_drive_sprites.py
    uv run python tools/ingest_drive_sprites.py --dry-run
    uv run python tools/ingest_drive_sprites.py --only-new   # skip files already processed
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
DRIVE_ARCHIVE = REPO_ROOT / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters"
STYLE_DATASET = REPO_ROOT / "tools" / "lora_training" / "style_dataset"

# Target buckets — number prefix = kohya repeat count
BUCKET_ARTIST = STYLE_DATASET / "20_artist"        # Our game's actual sprites (highest weight)
BUCKET_SAMPLES = STYLE_DATASET / "15_nazuna_samples"  # Artist's portfolio/samples work
BUCKET_NAZUNA = STYLE_DATASET / "10_nazuna_artist"  # Nazuna character specifically

STYLE_TAG = "jrpg_pixel_style"
CANVAS_SIZE = 512
FILL_MIN = 0.03
FILL_MAX = 0.90
TARGET_FILL = 0.75


def autocrop(img: Image.Image, alpha_threshold: int = 10) -> Image.Image:
    """Crop to bounding box of non-transparent pixels."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    a = img.split()[3]
    bbox = a.point(lambda p: 255 if p > alpha_threshold else 0).getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)


def scale_to_fill(cropped: Image.Image, canvas_size: int, target_fill: float) -> Image.Image:
    """Scale cropped sprite so its larger dimension fills target_fill of canvas. Nearest-neighbor."""
    cw, ch = cropped.size
    target_px = int(canvas_size * target_fill)
    scale = target_px / max(cw, ch)
    # Don't upscale more than 8x (preserves pixel art integrity)
    scale = min(scale, 8.0)
    new_w = max(1, round(cw * scale))
    new_h = max(1, round(ch * scale))
    return cropped.resize((new_w, new_h), Image.NEAREST)


def place_on_canvas(sprite: Image.Image, canvas_size: int) -> Image.Image:
    """Center sprite on transparent canvas."""
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    sw, sh = sprite.size
    x = (canvas_size - sw) // 2
    y = (canvas_size - sh) // 2
    canvas.paste(sprite, (x, y), sprite)
    return canvas


def canvas_fill_ratio(canvas: Image.Image) -> float:
    total = canvas.width * canvas.height
    opaque = sum(1 for p in canvas.split()[3].tobytes() if p > 10)
    return opaque / total


def split_strip_horizontal(img: Image.Image, frame_height: int = None) -> list[Image.Image]:
    """Split horizontal sprite strip into frames. Assumes square frames by default."""
    w, h = img.size
    fh = frame_height or h
    frame_count = max(1, w // fh)
    frames = []
    for i in range(frame_count):
        box = (i * fh, 0, (i + 1) * fh, fh)
        frames.append(img.crop(box))
    return frames


def split_grid(img: Image.Image, cols: int, rows: int) -> list[Image.Image]:
    """Split a grid sprite sheet into individual frames."""
    w, h = img.size
    fw = w // cols
    fh = h // rows
    frames = []
    for r in range(rows):
        for c in range(cols):
            box = (c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)
            frames.append(img.crop(box))
    return frames


def extract_gif_keyframes(gif_path: Path, max_frames: int = 8) -> list[Image.Image]:
    """Extract evenly-spaced keyframes from an animated GIF."""
    with Image.open(gif_path) as gif:
        n_frames = getattr(gif, "n_frames", 1)
        if n_frames <= max_frames:
            indices = list(range(n_frames))
        else:
            step = n_frames / max_frames
            indices = [int(i * step) for i in range(max_frames)]

        frames = []
        for idx in indices:
            gif.seek(idx)
            # Convert palette mode to RGBA
            frame = gif.convert("RGBA")
            frames.append(frame.copy())
        return frames


def make_caption(character: str, pose: str, extras: str = "") -> str:
    """Build a training caption."""
    parts = [STYLE_TAG, "pixel art battle sprite", character]
    if pose:
        parts.append(pose)
    parts.append("black pixel outline")
    parts.append("transparent background")
    if extras:
        parts.append(extras)
    parts.append("16-bit SNES style")
    return ", ".join(parts)


def process_frame(
    frame: Image.Image,
    caption: str,
    output_dir: Path,
    prefix: str,
    counter: list[int],
    dry_run: bool = False,
) -> bool:
    """Process a single frame: autocrop, scale, place on canvas, validate, save."""
    if frame.mode != "RGBA":
        frame = frame.convert("RGBA")

    cropped = autocrop(frame)
    cw, ch = cropped.size
    if cw < 4 or ch < 4:
        return False

    scaled = scale_to_fill(cropped, CANVAS_SIZE, TARGET_FILL)
    canvas = place_on_canvas(scaled, CANVAS_SIZE)
    ratio = canvas_fill_ratio(canvas)

    if ratio < FILL_MIN or ratio > FILL_MAX:
        return False

    idx = counter[0]
    counter[0] += 1

    out_png = output_dir / f"{prefix}_{idx:03d}.png"
    out_txt = output_dir / f"{prefix}_{idx:03d}.txt"

    if not dry_run:
        canvas.save(out_png, "PNG")
        out_txt.write_text(caption, encoding="utf-8")

    return True


def ingest_fighter(output_dir: Path, counter: list[int], dry_run: bool) -> tuple[int, int]:
    """Process new fighter sprites from drive archive."""
    fighter_dir = DRIVE_ARCHIVE / "FIGHTER"
    accepted = rejected = 0

    # Fighter IDLE (2 frames)
    p = fighter_dir / "Main Fighter IDLE-Sheet.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "medieval fighter warrior, red plate armor, brown hair, broadsword",
                "idle stance" if i == 0 else "idle breathing frame",
            )
            if process_frame(frame, cap, output_dir, "fighter", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Fighter SLASH (3 frames)
    p = fighter_dir / "Main Fighter SLASH 1-Sheet.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        poses = ["slash windup pose", "slash mid-swing pose", "slash follow-through pose"]
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "medieval fighter warrior, red plate armor, brown hair",
                poses[min(i, len(poses) - 1)],
            )
            if process_frame(frame, cap, output_dir, "fighter", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Fighter DASH (1 frame)
    p = fighter_dir / "Main Fighter DASH-Sheet.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        cap = make_caption(
            "medieval fighter warrior, red plate armor, brown hair",
            "dash attack pose, lunging forward",
        )
        if process_frame(img, cap, output_dir, "fighter", counter, dry_run):
            accepted += 1
        else:
            rejected += 1

    # Fighter animations aseprite (3 frames - may overlap with existing)
    p = fighter_dir / "Main Fighter animations.aseprite"
    if p.exists():
        # Already extracted in existing 20_artist — skip to avoid duplicates
        pass

    # Iron Sword weapon sprites
    p = fighter_dir / "Wp1 Iron sword-Sheet.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "iron sword weapon sprite, medieval broadsword",
                "weapon idle" if i == 0 else "weapon raised",
                "weapon sprite only, no character",
            )
            if process_frame(frame, cap, output_dir, "fighter_wp", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Iron Sword SLASH (3 frames with motion trail)
    p = fighter_dir / "Wp 1 Iron Sword SLASH 1-Sheet.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "iron sword weapon sprite, slash motion trail",
                f"weapon slash frame {i+1}",
                "weapon sprite only with slash effect",
            )
            if process_frame(frame, cap, output_dir, "fighter_wp", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Iron Sword DASH (1 frame)
    p = fighter_dir / "Wp 1 Iron Sword DASH move.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        cap = make_caption(
            "iron sword weapon sprite, dash motion",
            "weapon dash forward",
            "weapon sprite only",
        )
        if process_frame(img, cap, output_dir, "fighter_wp", counter, dry_run):
            accepted += 1
        else:
            rejected += 1

    return accepted, rejected


def ingest_rogue(output_dir: Path, counter: list[int], dry_run: bool) -> tuple[int, int]:
    """Process rogue sprites from drive archive."""
    rogue_dir = DRIVE_ARCHIVE / "ROGUE"
    accepted = rejected = 0

    # Rogue base idle
    p = rogue_dir / "Rogue Base sprite.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        cap = make_caption(
            "rogue assassin, dark leather armor, hood and flowing cape, dual weapons",
            "idle battle stance",
        )
        if process_frame(img, cap, output_dir, "rogue", counter, dry_run):
            accepted += 1
        else:
            rejected += 1

    # Rogue shooting (3 frames)
    p = rogue_dir / "Rogue_Shooting.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        poses = ["aiming crossbow", "firing crossbow", "crossbow recoil"]
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "rogue assassin, dark leather armor, hood and cape, crossbow",
                poses[min(i, len(poses) - 1)],
            )
            if process_frame(frame, cap, output_dir, "rogue", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Rogue slashing (3 frames)
    p = rogue_dir / "Rogue_Slashing 1.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        poses = ["slash windup", "slash mid-swing", "slash follow-through"]
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "rogue assassin, dark leather armor, hood and cape, sword",
                poses[min(i, len(poses) - 1)],
            )
            if process_frame(frame, cap, output_dir, "rogue", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Rogue design aseprite (7 hi-res frames with layer breakdown)
    # Extract via aseprite CLI was done to tmp/drive_extraction/
    extraction_dir = REPO_ROOT / "tmp" / "drive_extraction"
    rogue_poses = [
        "idle battle stance with bow",
        "walking forward pose",
        "crouching stealth pose",
        "attack ready stance",
        "shooting arrow pose",
        "dodge roll pose",
        "casting ability pose with orb",
    ]
    for i in range(7):
        p = extraction_dir / f"rogue_frame_{i}.png"
        if p.exists():
            img = Image.open(p).convert("RGBA")
            cap = make_caption(
                "rogue assassin, dark leather armor, hood, flowing cape, red boots, dual weapons, bow",
                rogue_poses[i],
                "detailed hi-res design",
            )
            if process_frame(img, cap, output_dir, "rogue_design", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    return accepted, rejected


def ingest_cleric(output_dir: Path, counter: list[int], dry_run: bool) -> tuple[int, int]:
    """Process cleric sprites from drive archive."""
    cleric_dir = DRIVE_ARCHIVE / "CLERIC"
    accepted = rejected = 0

    # Cleric design sheet (3 frames showing casting stages)
    p = cleric_dir / "Cleric Main design-Sheet.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        poses = ["casting spell with staff, aura building", "channeling magic, staff glowing", "spell release, magical aura burst"]
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "cleric priestess, white and purple hooded robes, golden star staff, braided hair",
                poses[min(i, len(poses) - 1)],
            )
            if process_frame(frame, cap, output_dir, "cleric", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Cleric design from aseprite (single frame, hi-res)
    p = REPO_ROOT / "tmp" / "drive_extraction" / "cleric_design_frame_0.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        cap = make_caption(
            "cleric priestess, white and purple hooded robes, golden star staff, braided hair, magical aura",
            "casting spell pose, staff raised, sparkle effects",
            "detailed hi-res design",
        )
        if process_frame(img, cap, output_dir, "cleric_design", counter, dry_run):
            accepted += 1
        else:
            rejected += 1

    return accepted, rejected


def ingest_samples(output_dir: Path, counter: list[int], dry_run: bool) -> tuple[int, int]:
    """Process artist's portfolio samples into training data."""
    samples_dir = DRIVE_ARCHIVE / "Samples"
    if not samples_dir.exists():
        return 0, 0

    accepted = rejected = 0

    # Skeleton character (5 frames, 640x128)
    p = samples_dir / "Character Pixel art SKELETON Finished.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        poses = ["front facing idle", "quarter turn left", "side profile", "quarter turn right", "back facing"]
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "undead skeleton warrior, green glowing hands, dark bones",
                poses[min(i, len(poses) - 1)],
                "character rotation turnaround",
            )
            if process_frame(frame, cap, output_dir, "skeleton", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Young Woman character (5 frames, 640x128)
    p = samples_dir / "Character Pixel art YOUNGWOMAN Finished.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        poses = ["front facing idle", "quarter turn left", "side profile", "quarter turn right", "back facing"]
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "young woman villager, red dress, brown braided hair",
                poses[min(i, len(poses) - 1)],
                "character rotation turnaround",
            )
            if process_frame(frame, cap, output_dir, "youngwoman", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Young Woman preview (3 frames, 384x128)
    p = samples_dir / "Character Pixel art YOUNGWOMAN preview 1.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption(
                "young woman villager, red dress, brown braided hair",
                f"action pose frame {i+1}",
            )
            if process_frame(frame, cap, output_dir, "youngwoman", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Armed attack sheet (512x1024 = 4 cols x 8 rows of 128x128 frames)
    p = samples_dir / "Sprite_sheet_4_attk_Armed.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        frames = split_grid(img, cols=4, rows=8)
        for i, frame in enumerate(frames):
            row = i // 4
            row_labels = ["idle", "walk", "attack windup", "attack strike", "attack follow", "cast", "hit reaction", "special"]
            pose = row_labels[min(row, len(row_labels) - 1)] + f" frame {(i % 4) + 1}"
            cap = make_caption(
                "armed warrior character, medieval armor, sword and shield",
                pose,
            )
            if process_frame(frame, cap, output_dir, "armed", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Void Boar charge (1200x64 = ~18 frames of 64x64)
    p = samples_dir / "void_boar_layers_Charge.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        w, h = img.size
        n_frames = w // h if h > 0 else 1
        for i in range(n_frames):
            box = (i * h, 0, (i + 1) * h, h)
            frame = img.crop(box)
            phase = "idle" if i < 3 else ("charging energy" if i < 8 else ("charge attack" if i < 14 else "charge recovery"))
            cap = make_caption(
                "void boar monster, dark beast with purple energy aura",
                f"{phase} frame {i+1}",
                "monster sprite",
            )
            if process_frame(frame, cap, output_dir, "boar", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Diagonal walking example (264x637, roughly 4 cols x 9 rows at ~66x~70)
    p = samples_dir / "DiagonalWalkingExample.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        # This is a grid — 4 cols, auto-detect row height from col width
        w, h = img.size
        col_w = w // 4  # ~66
        rows = h // col_w  # ~9
        frames = split_grid(img, cols=4, rows=rows)
        directions = ["walk down", "walk left", "walk right", "walk up",
                       "walk down-left", "walk down-right", "walk up-left", "walk up-right", "idle"]
        for i, frame in enumerate(frames):
            row = i // 4
            col = i % 4
            dir_label = directions[min(row, len(directions) - 1)]
            cap = make_caption(
                "blue-haired character, dark outfit, overworld sprite",
                f"{dir_label} frame {col+1}",
                "isometric diagonal walk cycle",
            )
            if process_frame(frame, cap, output_dir, "diagwalk", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Dragon pixel art (large hi-res designs - treat as single images)
    for dragon_file, desc in [
        ("DRAGON pixel art_preview 2.png", "blue dragon, wings spread, multiple views with palette"),
        ("DRAGON pixel art_preview 5.png", "blue dragon, detailed pixel art, multiple angles and poses"),
    ]:
        p = samples_dir / dragon_file
        if p.exists():
            img = Image.open(p).convert("RGBA")
            cap = make_caption(desc, "dragon design sheet", "monster pixel art, detailed")
            if process_frame(img, cap, output_dir, "dragon", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    # Animated GIFs — extract keyframes
    gif_entries = [
        ("Wizard_Prev1.gif", "wizard mage, robes, pointed hat, magical staff", 8),
        ("Dr Iron preview.gif", "armored robot knight, mechanical warrior", 8),
        ("Sharkoid_Idle preview.gif", "shark humanoid creature, aquatic monster", 8),
        ("ship preview.gif", "pixel art spaceship, sci-fi vessel", 6),
    ]
    for gif_name, char_desc, max_kf in gif_entries:
        p = samples_dir / gif_name
        if p.exists():
            try:
                keyframes = extract_gif_keyframes(p, max_kf)
                prefix = gif_name.split("_")[0].split(" ")[0].lower()
                for i, frame in enumerate(keyframes):
                    cap = make_caption(char_desc, f"animation keyframe {i+1}")
                    if process_frame(frame, cap, output_dir, prefix, counter, dry_run):
                        accepted += 1
                    else:
                        rejected += 1
            except Exception as e:
                print(f"  WARN: Failed to extract GIF {gif_name}: {e}")
                rejected += 1

    # RPG scene (single frame)
    p = samples_dir / "Pad_RPG game 1 scene 1.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        cap = f"{STYLE_TAG}, pixel art battle scene, character fighting fire monster, outdoor forest, 16-bit SNES style"
        if process_frame(img, cap, output_dir, "scene", counter, dry_run):
            accepted += 1
        else:
            rejected += 1

    # Skip: Characters Preview 4/5 (concept art, not pixel art)
    # Skip: Comparison_of_Skeleton_to_Young_Man.png (too small, 153x116)

    return accepted, rejected


def ingest_nazuna_gifs(output_dir: Path, counter: list[int], dry_run: bool) -> tuple[int, int]:
    """Extract additional keyframes from Nazuna animated GIFs."""
    nazuna_dir = DRIVE_ARCHIVE / "Nazuna sample sprites"
    if not nazuna_dir.exists():
        return 0, 0

    accepted = rejected = 0

    gif_entries = [
        ("Genesis 32X Nazuna Atks00.gif", "sci-fi female warrior, cybernetic armor, attack combo", 6),
        ("Genesis 32X Nazuna Atks prev 2.gif", "sci-fi female warrior, cybernetic armor, hi-res attack sequence", 6),
        ("Genesis 32X Nazuna Blink to target0.gif", "sci-fi female warrior, teleport blink attack", 4),
        ("Nasuna walk 3.gif", "sci-fi female warrior, walking animation cycle", 6),
        ("Naz running new.gif", "sci-fi female warrior, running animation cycle", 6),
        ("Nazuna animations PREV 1.gif", "sci-fi female warrior, multiple combat animations", 8),
        ("Taureg prev112143.gif", "taureg beast creature, animated monster", 6),
    ]

    for gif_name, char_desc, max_kf in gif_entries:
        p = nazuna_dir / gif_name
        if p.exists():
            try:
                keyframes = extract_gif_keyframes(p, max_kf)
                prefix = "nazuna"
                for i, frame in enumerate(keyframes):
                    cap = make_caption(char_desc, f"animation keyframe {i+1}")
                    if process_frame(frame, cap, output_dir, prefix, counter, dry_run):
                        accepted += 1
                    else:
                        rejected += 1
            except Exception as e:
                print(f"  WARN: Failed to extract GIF {gif_name}: {e}")
                rejected += 1

    # Ship-1-Shoot sprite sheet (510x128 = ~4 frames)
    p = nazuna_dir / "Ship-1-Shoot.png"
    if p.exists():
        img = Image.open(p).convert("RGBA")
        for i, frame in enumerate(split_strip_horizontal(img)):
            cap = make_caption("pixel art spaceship, sci-fi vessel", f"shooting animation frame {i+1}")
            if process_frame(frame, cap, output_dir, "nazuna_ship", counter, dry_run):
                accepted += 1
            else:
                rejected += 1

    return accepted, rejected


def main():
    parser = argparse.ArgumentParser(description="Ingest drive archive sprites into LoRA training dataset")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing files")
    args = parser.parse_args()

    print("=" * 60)
    print("Drive Sprite Ingestion for LoRA Training")
    print("=" * 60)

    if not DRIVE_ARCHIVE.exists():
        print(f"ERROR: Drive archive not found at {DRIVE_ARCHIVE}")
        sys.exit(1)

    # Count existing files per bucket
    for bucket in [BUCKET_ARTIST, BUCKET_SAMPLES, BUCKET_NAZUNA]:
        bucket.mkdir(parents=True, exist_ok=True)
        existing = len(list(bucket.glob("*.png")))
        print(f"  {bucket.name}: {existing} existing images")

    print()

    results = {}

    # 1. Fighter + Cleric + Rogue → 20_artist bucket
    # Find the next available index in 20_artist
    existing_artist = sorted(BUCKET_ARTIST.glob("*.png"))
    # Start counter after existing numbered files
    start_idx = 0
    if existing_artist:
        # Find max index from existing sprite_NNN.png pattern
        for f in existing_artist:
            stem = f.stem
            parts = stem.rsplit("_", 1)
            if len(parts) == 2 and parts[1].isdigit():
                start_idx = max(start_idx, int(parts[1]) + 1)

    artist_counter = [start_idx]
    print(f"\n--- 20_artist bucket (starting at index {start_idx}) ---")

    print("\n[Fighter]")
    a, r = ingest_fighter(BUCKET_ARTIST, artist_counter, args.dry_run)
    print(f"  Fighter: {a} accepted, {r} rejected")
    results["fighter"] = (a, r)

    print("\n[Rogue]")
    a, r = ingest_rogue(BUCKET_ARTIST, artist_counter, args.dry_run)
    print(f"  Rogue: {a} accepted, {r} rejected")
    results["rogue"] = (a, r)

    print("\n[Cleric]")
    a, r = ingest_cleric(BUCKET_ARTIST, artist_counter, args.dry_run)
    print(f"  Cleric: {a} accepted, {r} rejected")
    results["cleric"] = (a, r)

    # 2. Samples → 15_nazuna_samples bucket
    samples_counter = [0]
    print(f"\n--- 15_nazuna_samples bucket ---")
    a, r = ingest_samples(BUCKET_SAMPLES, samples_counter, args.dry_run)
    print(f"  Samples: {a} accepted, {r} rejected")
    results["samples"] = (a, r)

    # 3. Nazuna GIFs → 10_nazuna_artist bucket (append after existing)
    existing_nazuna = sorted(BUCKET_NAZUNA.glob("*.png"))
    naz_start = 0
    for f in existing_nazuna:
        parts = f.stem.rsplit("_", 1)
        if len(parts) == 2 and parts[1].isdigit():
            naz_start = max(naz_start, int(parts[1]) + 1)

    nazuna_counter = [naz_start]
    print(f"\n--- 10_nazuna_artist bucket (starting at index {naz_start}) ---")
    a, r = ingest_nazuna_gifs(BUCKET_NAZUNA, nazuna_counter, args.dry_run)
    print(f"  Nazuna GIFs: {a} accepted, {r} rejected")
    results["nazuna_gifs"] = (a, r)

    # Summary
    total_accepted = sum(v[0] for v in results.values())
    total_rejected = sum(v[1] for v in results.values())

    print(f"\n{'=' * 60}")
    print(f"SUMMARY {'(DRY RUN)' if args.dry_run else ''}")
    print(f"{'=' * 60}")
    for source, (a, r) in results.items():
        print(f"  {source:20s}: {a:3d} accepted, {r:3d} rejected")
    print(f"  {'TOTAL':20s}: {total_accepted:3d} accepted, {total_rejected:3d} rejected")

    # Final bucket counts
    print(f"\nFinal bucket sizes:")
    for bucket in [BUCKET_ARTIST, BUCKET_SAMPLES, BUCKET_NAZUNA]:
        count = len(list(bucket.glob("*.png")))
        print(f"  {bucket.name}: {count} images")

    if total_accepted > 0 and not args.dry_run:
        print(f"\nDone! Delete .npz cache files and run training next.")


if __name__ == "__main__":
    main()
