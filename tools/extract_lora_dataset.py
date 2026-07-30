#!/usr/bin/env python3
"""
LoRA Training Dataset Extractor for Cowardly Irregular Fighter Sprites.

Extracts individual frames from all artist-made fighter sprite sheets,
writes matching .txt caption files, and emits a dataset_info.json
with recommended Kohya_ss SDXL LoRA training settings for an RTX 3090 24GB.

Re-run whenever the artist delivers additional frames.
Usage:
    python tools/extract_lora_dataset.py
"""

import json
import sys
from pathlib import Path
from PIL import Image

# ---------------------------------------------------------------------------
# Configuration — edit SOURCES to add new sheets as they arrive
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = REPO_ROOT / "assets" / "sprites" / "jobs" / "fighter"
PICTURES_ROOT = Path("/home/struktured/Pictures")
OUTPUT_DIR = REPO_ROOT / "tools" / "lora_training" / "dataset"

# Shared caption prefix applied to every frame.
CAPTION_PREFIX = (
    "pixel art, SNES RPG battle sprite, fighter character, "
    "red plate armor, brown hair, black pixel outline, "
    "transparent background, 16-bit style, "
    "side-view battle stance"
)

# ---------------------------------------------------------------------------
# Source sheet definitions.
#
# Each entry is a dict with:
#   path        — absolute Path to the PNG
#   frame_w     — width of a single frame in pixels
#   frame_h     — height of a single frame in pixels
#   frame_count — total frames (validated against actual image width)
#   prefix      — output filename prefix (determines sort order)
#   captions    — list of per-frame caption suffixes (len == frame_count)
# ---------------------------------------------------------------------------

SOURCES = [
    # -----------------------------------------------------------------------
    # In-game battle sprite sheets (all 256x256 frames)
    # -----------------------------------------------------------------------
    {
        "path": ASSET_ROOT / "idle.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 2,
        "prefix": "fighter_idle",
        "captions": [
            "idle pose frame 1, standing at rest with sword lowered, battle-ready stance",
            "idle pose frame 2, subtle weight shift bob, sword held at side",
        ],
    },
    {
        "path": ASSET_ROOT / "attack.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 6,
        "prefix": "fighter_attack",
        "captions": [
            "attack wind-up frame 1, raising sword overhead, weight shifting to back foot",
            "attack frame 2, sword lifted high, body coiling for swing",
            "attack frame 3, mid-swing arc, blade cutting downward",
            "attack frame 4, follow-through past center, blade angled forward",
            "attack frame 5, extended thrust pose, sword pointed at enemy",
            "attack frame 6, recovery stance, returning to guard position",
        ],
    },
    {
        "path": ASSET_ROOT / "walk.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 6,
        "prefix": "fighter_walk",
        "captions": [
            "walk cycle frame 1, advancing step, left foot forward",
            "walk cycle frame 2, mid-stride, weight transfer",
            "walk cycle frame 3, right foot stepping forward, sword at side",
            "walk cycle frame 4, both feet near ground, neutral position",
            "walk cycle frame 5, advancing step, momentum forward",
            "walk cycle frame 6, stride completing, returning to start pose",
        ],
    },
    {
        "path": ASSET_ROOT / "cast.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 4,
        "prefix": "fighter_cast",
        "captions": [
            "magic cast frame 1, gathering energy, arm extended forward",
            "magic cast frame 2, small blue orb forming in hand, concentrating",
            "magic cast frame 3, bright light burst at fingertips, releasing spell",
            "magic cast frame 4, spell fired, recoil stance, afterglow fading",
        ],
    },
    {
        "path": ASSET_ROOT / "dead.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 4,
        "prefix": "fighter_dead",
        "captions": [
            "death animation frame 1, falling backwards, sword slipping from grip",
            "death animation frame 2, body tilting, arms losing strength",
            "death animation frame 3, collapsed, diagonal sprawl on ground",
            "death animation frame 4, fully prone, motionless defeated pose",
        ],
    },
    {
        "path": ASSET_ROOT / "hit.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 4,
        "prefix": "fighter_hit",
        "captions": [
            "hit reaction frame 1, impact recoil, body lurching backward",
            "hit reaction frame 2, staggered, arms spread for balance",
            "hit reaction frame 3, recovering from blow, leaning back",
            "hit reaction frame 4, regaining footing, returning to guard stance",
        ],
    },
    {
        "path": ASSET_ROOT / "defend.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 4,
        "prefix": "fighter_defend",
        "captions": [
            "defend pose frame 1, raising sword in guard position, knees bent",
            "defend pose frame 2, full block, blade horizontal across body",
            "defend pose frame 3, bracing for impact, feet planted wide",
            "defend pose frame 4, held guard stance, sword edge toward enemy",
        ],
    },
    {
        "path": ASSET_ROOT / "item.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 4,
        "prefix": "fighter_item",
        "captions": [
            "item use frame 1, kneeling, reaching into bag at side",
            "item use frame 2, holding green potion vial overhead",
            "item use frame 3, tipping potion, liquid beginning to pour",
            "item use frame 4, sparkle effect, item consumed, rising back up",
        ],
    },
    {
        "path": ASSET_ROOT / "victory.png",
        "frame_w": 256,
        "frame_h": 256,
        "frame_count": 4,
        "prefix": "fighter_victory",
        "captions": [
            "victory pose frame 1, raising sword skyward triumphantly",
            "victory pose frame 2, sword held high, chest out, proud stance",
            "victory pose frame 3, swinging sword in celebratory arc",
            "victory pose frame 4, resting sword on shoulder, satisfied pose",
        ],
    },
    # -----------------------------------------------------------------------
    # External Pictures — body slash sheet (128x128 frames, no weapon)
    # -----------------------------------------------------------------------
    {
        "path": PICTURES_ROOT / "Main_Fighter_SLASH_1-Sheet.png",
        "frame_w": 128,
        "frame_h": 128,
        "frame_count": 3,
        "prefix": "fighter_body_slash",
        "captions": [
            "body slash frame 1, wind-up pose, torso rotating, unarmed slash motion",
            "body slash frame 2, peak of slash arc, arm extended mid-swing, no weapon",
            "body slash frame 3, follow-through, arm sweeping downward, no weapon",
        ],
    },
    # -----------------------------------------------------------------------
    # External Pictures — iron sword weapon sheet (128x128 frames)
    # -----------------------------------------------------------------------
    {
        "path": PICTURES_ROOT / "Wp1_Iron_sword-Sheet.png",
        "frame_w": 128,
        "frame_h": 128,
        "frame_count": 2,
        "prefix": "fighter_iron_sword",
        "captions": [
            "iron sword weapon sprite frame 1, blade at rest angle, grey steel edge",
            "iron sword weapon sprite frame 2, blade at alternate angle, slight gleam",
        ],
    },
    # -----------------------------------------------------------------------
    # External Pictures — iron sword dash frame (single 128x128)
    # -----------------------------------------------------------------------
    {
        "path": PICTURES_ROOT / "Wp_1_Iron_Sword_DASH_move.png",
        "frame_w": 128,
        "frame_h": 128,
        "frame_count": 1,
        "prefix": "fighter_iron_sword_dash",
        "captions": [
            "iron sword dash move, blade angled for lunge strike, forward momentum pose",
        ],
    },
    # -----------------------------------------------------------------------
    # External Pictures — iron sword slash arc sheet (128x128 frames)
    # -----------------------------------------------------------------------
    {
        "path": PICTURES_ROOT / "Wp_1_Iron_Sword_SLASH_1-Sheet.png",
        "frame_w": 128,
        "frame_h": 128,
        "frame_count": 3,
        "prefix": "fighter_iron_sword_slash",
        "captions": [
            "iron sword slash arc frame 1, sword mid-swing with green motion trail",
            "iron sword slash arc frame 2, blade at peak of arc, trail fading",
            "iron sword slash arc frame 3, follow-through, sword angled downward, trail gone",
        ],
    },
]

# ---------------------------------------------------------------------------
# Recommended Kohya_ss SDXL LoRA settings for RTX 3090 24GB
# ---------------------------------------------------------------------------

KOHYA_SETTINGS = {
    "model": "SDXL 1.0 base (stabilityai/stable-diffusion-xl-base-1.0)",
    "lora_type": "LoRA (standard rank decomposition)",
    "network_dim": 32,
    "network_alpha": 16,
    "notes_network": (
        "rank 32 / alpha 16 is a good balance for a small specialised style dataset. "
        "Increase to rank 64 if you want more capacity but 32 is sufficient for a single character style."
    ),
    "resolution": "512,512",
    "notes_resolution": (
        "512x512 matches the 256x256 in-game frames upscaled 2x. "
        "SDXL can train at 512 even though its native res is 1024; "
        "the pixel art style benefits from smaller resolution to preserve crispness."
    ),
    "train_batch_size": 4,
    "gradient_accumulation_steps": 1,
    "notes_batch": (
        "Batch 4 fits comfortably on 24GB VRAM with SDXL. "
        "Increase to 6 if memory permits with fp16 and xformers."
    ),
    "max_train_steps": "recommend 1500-2500 (start at 1500, check samples every 250 steps)",
    "notes_steps": (
        "With ~38 training images and batch 4, one epoch is ~10 steps. "
        "1500 steps gives roughly 150 epochs — appropriate for a tightly scoped style LoRA. "
        "Monitor validation loss; stop early if overfit."
    ),
    "learning_rate": 0.0001,
    "unet_lr": 0.0001,
    "text_encoder_lr": 0.00005,
    "lr_scheduler": "cosine_with_restarts",
    "lr_warmup_steps": 100,
    "optimizer": "AdamW8bit",
    "mixed_precision": "fp16",
    "save_precision": "fp16",
    "xformers": True,
    "gradient_checkpointing": False,
    "notes_gradient_ckpt": (
        "With 24GB VRAM, gradient checkpointing is not needed and "
        "leaving it off keeps training faster."
    ),
    "bucket_no_upscale": True,
    "notes_bucketing": (
        "Enable no-upscale bucketing so smaller 128x128 frames "
        "are not blurrily upscaled during data loading."
    ),
    "caption_dropout_rate": 0.05,
    "notes_caption": (
        "5% caption dropout helps the LoRA learn visual style, "
        "not just caption keywords. Keep low because captions are descriptive."
    ),
    "noise_offset": 0.1,
    "sample_every_n_steps": 250,
    "save_every_n_steps": 500,
    "trigger_word": "fighter_ci_pixel",
    "notes_trigger": (
        "Prefix every caption with 'fighter_ci_pixel' when training "
        "to allow targeted activation. "
        "The CAPTION_PREFIX in this script already encodes style tags; "
        "prepend the trigger word in Kohya's caption prefix field."
    ),
}


# ---------------------------------------------------------------------------
# Extraction logic
# ---------------------------------------------------------------------------

def validate_source(src: dict) -> None:
    p = src["path"]
    if not p.exists():
        raise FileNotFoundError(f"Source not found: {p}")
    with Image.open(p) as img:
        expected_w = src["frame_w"] * src["frame_count"]
        if img.width != expected_w:
            raise ValueError(
                f"{p.name}: expected width {expected_w}px "
                f"({src['frame_count']} frames x {src['frame_w']}px) "
                f"but got {img.width}px"
            )
        if img.height != src["frame_h"]:
            raise ValueError(
                f"{p.name}: expected height {src['frame_h']}px but got {img.height}px"
            )
    n_captions = len(src["captions"])
    if n_captions != src["frame_count"]:
        raise ValueError(
            f"{p.name}: {src['frame_count']} frames declared but "
            f"{n_captions} captions provided"
        )


def extract_source(src: dict, output_dir: Path) -> list[dict]:
    """Extract all frames from one source sheet. Returns list of frame metadata."""
    records = []
    with Image.open(src["path"]) as img:
        img = img.convert("RGBA")
        for i, caption_suffix in enumerate(src["captions"]):
                left = i * src["frame_w"]
                box = (left, 0, left + src["frame_w"], src["frame_h"])
                frame = img.crop(box)

                stem = f"{src['prefix']}_f{i+1:02d}"
                png_path = output_dir / f"{stem}.png"
                txt_path = output_dir / f"{stem}.txt"

                frame.save(png_path, "PNG")

                caption = f"{CAPTION_PREFIX}, {caption_suffix}"
                txt_path.write_text(caption, encoding="utf-8")

                records.append({
                    "filename": f"{stem}.png",
                    "source": str(src["path"]),
                    "frame_index": i,
                    "frame_size": f"{src['frame_w']}x{src['frame_h']}",
                    "caption": caption,
                })
    return records


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Output directory: {OUTPUT_DIR}")
    print(f"Sources to process: {len(SOURCES)}\n")

    # Validate all sources before writing anything.
    print("Validating sources...")
    errors = []
    for src in SOURCES:
        try:
            validate_source(src)
            print(f"  OK  {src['path'].name} ({src['frame_count']} frames)")
        except Exception as exc:
            print(f"  ERR {src['path'].name}: {exc}")
            errors.append(str(exc))
    if errors:
        print(f"\n{len(errors)} validation error(s). Aborting.")
        sys.exit(1)

    # Extract frames.
    print("\nExtracting frames...")
    all_records: list[dict] = []
    source_summary: list[dict] = []
    for src in SOURCES:
        records = extract_source(src, OUTPUT_DIR)
        all_records.extend(records)
        source_summary.append({
            "source_file": str(src["path"]),
            "prefix": src["prefix"],
            "frame_size": f"{src['frame_w']}x{src['frame_h']}",
            "frames_extracted": len(records),
            "output_files": [r["filename"] for r in records],
        })
        print(f"  {src['prefix']}: {len(records)} frame(s) extracted")

    total = len(all_records)

    # Write dataset_info.json.
    info = {
        "dataset_name": "cowardly_irregular_fighter_lora",
        "character": "Fighter (Cowardly Irregular JRPG)",
        "style": "SNES-era pixel art, 16-bit RPG battle sprite",
        "total_training_images": total,
        "sources": source_summary,
        "frames": all_records,
        "kohya_sdxl_lora_settings": KOHYA_SETTINGS,
        "generation_notes": [
            "All frames extracted from artist-made sprites — no procedural/generated art.",
            "Frames have transparent (RGBA) backgrounds, as required for clean pixel art LoRA training.",
            "128x128 and 256x256 frame sizes are mixed; Kohya bucketing handles this automatically.",
            "Re-run this script to regenerate the dataset after adding new sheets to SOURCES.",
            "Caption trigger word 'fighter_ci_pixel' should be prepended in Kohya's prefix field.",
        ],
    }

    info_path = REPO_ROOT / "tools" / "lora_training" / "dataset_info.json"
    info_path.write_text(json.dumps(info, indent=2), encoding="utf-8")
    print(f"\nDataset info written to: {info_path}")

    print(f"\nTotal training images extracted: {total}")
    print("Done.")


if __name__ == "__main__":
    main()
