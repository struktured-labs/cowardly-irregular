#!/usr/bin/env python3
"""
DALL-E 3 JRPG Pixel Art Training Dataset Generator for Cowardly Irregular.

Generates ~96 sprite images across 8 job types using DALL-E 3, then
processes them into 512x512 captioned training frames for LoRA training.

Target output: tools/lora_training/style_dataset/12_dalle/
Cost tracking:  tmp/dalle_usage.json

Usage:
    uv run python tools/gen_dalle_training_data.py
    uv run python tools/gen_dalle_training_data.py --dry-run
    uv run python tools/gen_dalle_training_data.py --jobs fighter mage
    uv run python tools/gen_dalle_training_data.py --max-images 20
    uv run python tools/gen_dalle_training_data.py --process-only
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import httpx
from openai import OpenAI
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "tools" / "lora_training" / "style_dataset" / "12_dalle"
RAW_DIR = OUTPUT_DIR / "raw"
USAGE_FILE = REPO_ROOT / "tmp" / "dalle_usage.json"

# ----- Cost constants -----
# DALL-E 3 standard quality 1024x1024: $0.040 per image
COST_PER_IMAGE = 0.040

# ----- Style references rotated per generation for variety -----
STYLE_REFS = [
    "Final Fantasy VI style",
    "Chrono Trigger style",
    "Breath of Fire style",
    "Final Fantasy V style",
    "Final Fantasy IV style",
    "Secret of Mana style",
    "Seiken Densetsu style",
    "Bravely Default style",
]

# ----- Per-job description and palette (mirrors pipeline/prompts.py JOB_PROMPTS) -----
JOB_SPECS: dict[str, dict] = {
    "fighter": {
        "desc": "medieval warrior in red and steel plate armor, broadsword held ready, sturdy battle stance, brown hair, determined expression",
        "palette_hint": "warm reds, steel grays, brown leather, orange accents",
        "neg_extra": "",
    },
    "cleric": {
        "desc": "cleric priestess in white ceremonial robes with gold trim, ornate staff with gem top, hooded layered robes, braided hair, crown tiara headpiece, kind determined expression",
        "palette_hint": "white, soft pink, pale gold, cream, light blue, warm pastel tones",
        "neg_extra": "sword, blade, knife, dagger, weapon, bow, axe, spear",
    },
    "mage": {
        "desc": "mysterious mage in deep blue robes, tall pointed wizard hat, crystal-tipped staff, glowing cyan eyes, flowing robes with silver trim",
        "palette_hint": "deep blues, cyan glow, silver trim, dark purple shadows",
        "neg_extra": "sword, blade, knife, dagger, bow, axe, spear, shield, armor",
    },
    "rogue": {
        "desc": "gender-ambiguous rogue, face hidden by deep hood and wrapped dark scarf, only eyes visible in shadow, lean silhouette, torn cloak over light armor, belts and pouches, coiled evasive stance",
        "palette_hint": "deep muted green, dark brown leather, dusty purple scarf, shadow tones, weathered",
        "neg_extra": "clearly female curves, clearly male bodybuilder, anime catgirl, all-black outfit",
    },
    "bard": {
        "desc": "charming bard performer in gold-olive doublet with half-cape, tilted feathered beret with red feather, lute strapped to back, rapier at hip, dramatic flourish pose",
        "palette_hint": "gold, olive green, red feather, warm browns, cream shirt",
        "neg_extra": "",
    },
    "guardian": {
        "desc": "heavily armored guardian knight in full plate armor, massive tower shield, stoic protector, visor helmet, defensive battle stance",
        "palette_hint": "steel blue, polished silver, dark iron, gold trim, royal blue cape",
        "neg_extra": "",
    },
    "ninja": {
        "desc": "swift ninja in dark wrappings and face mask, kunai daggers at belt, crouched ready stance, minimal armor, lean athletic build",
        "palette_hint": "blacks, dark purple, steel gray, red sash accent",
        "neg_extra": "",
    },
    "summoner": {
        "desc": "ethereal summoner in flowing robes covered in arcane symbols, horned circlet headpiece, floating open grimoire, mystical energy aura surrounding hands",
        "palette_hint": "deep purple, gold arcane symbols, teal energy, dark cloth",
        "neg_extra": "sword, blade, dagger, axe, spear, bow",
    },
}

# ----- Pose variations per job (~12 per job = ~96 total) -----
# Each entry: (pose_tag for caption, pose_description for prompt)
JOB_POSES: dict[str, list[tuple[str, str]]] = {
    "fighter": [
        ("idle stance", "standing neutral ready pose, hand on sword hilt"),
        ("attack pose", "powerful broadsword swing in mid-arc, aggressive"),
        ("defend stance", "shield raised high, crouched defensive stance"),
        ("victory pose", "sword raised triumphantly overhead, victorious"),
        ("hit reaction", "recoiling backward from a blow, grimacing"),
        ("death pose", "slumped collapsed on ground, defeated"),
        ("casting pose", "channeling battle energy, power gathering in fist"),
        ("walking pose", "advancing forward with shield and sword ready"),
        ("item use pose", "drinking battle potion, brief respite mid-battle"),
        ("cleave attack pose", "wide horizontal broadsword cleave sweep"),
        ("power strike pose", "overhead two-handed broadsword downstrike"),
        ("battle stance", "alert combat ready pose, sword lowered slightly"),
    ],
    "cleric": [
        ("idle stance", "serene standing pose, staff held at side, calm"),
        ("healing pose", "hands glowing with holy light, healing warmth radiating"),
        ("casting pose", "staff raised high, holy magic energy forming above"),
        ("victory pose", "staff raised in celebration, grateful expression"),
        ("hit reaction", "startled stumble backward, protective arm raised"),
        ("death pose", "collapsed gently, staff fallen beside"),
        ("defend stance", "holy barrier forming around hands, protective shield"),
        ("buff casting pose", "drawing blessing sigil in air with staff tip"),
        ("raise ally pose", "kneeling over fallen ally, resurrection magic glowing"),
        ("walking pose", "purposeful stride forward, robes flowing, staff forward"),
        ("item use pose", "carefully administering holy water from vial"),
        ("battle stance", "staff crossed in front, alert but peaceful ready stance"),
    ],
    "mage": [
        ("idle stance", "standing with staff, arcane energy flickering at fingertips"),
        ("casting pose", "both hands raised, crackling magical energy forming"),
        ("attack pose", "launching magical bolt, hands extended forward"),
        ("victory pose", "staff raised with magical sparks showering down"),
        ("hit reaction", "magical shield shattering, staggering back"),
        ("death pose", "crumpled, arcane staff fallen, magic dissipating"),
        ("defend stance", "magical barrier erected by staff, glowing ward"),
        ("walking pose", "gliding forward, robes flowing, staff levitating beside"),
        ("item use pose", "reading from spell tome, pages glowing"),
        ("power cast pose", "explosive magical discharge both hands extended wide"),
        ("battle stance", "staff horizontal, eyes glowing with readied spell"),
        ("channeling pose", "drawing power from arcane ley lines, eyes closed"),
    ],
    "rogue": [
        ("idle stance", "weight shifted, coiled ready, hands relaxed but poised"),
        ("attack pose", "quick lunging feint, unexpected angle strike"),
        ("steal action pose", "darting low dash, fingers extended reaching"),
        ("victory pose", "back turned, glancing over shoulder, already leaving"),
        ("hit reaction", "twisting away, barely grazed, mid-dodge"),
        ("death pose", "crumpled in heap, face still obscured even in death"),
        ("defend stance", "vanishing sidestep, afterimage blur left behind"),
        ("walking pose", "light quick stride, almost gliding, scarf trailing"),
        ("backstab attack pose", "appearing from smoke behind, precision strike"),
        ("fleeing pose", "sprinting away, smoke bomb tossed at feet"),
        ("battle stance", "low crouch, eyes scanning, unreadable presence"),
        ("advance action pose", "predatory crouch, weight forward, explosive speed blur"),
    ],
    "bard": [
        ("idle stance", "relaxed posture, one hand resting on lute, easy confidence"),
        ("battle stance", "rapier drawn, lute ready to strum, theatrical stance"),
        ("casting pose", "strumming magical chord on lute, music notes visible"),
        ("victory pose", "grand bow, sweeping hat off head with flourish"),
        ("hit reaction", "stumbling back, hat knocked askew, surprised"),
        ("death pose", "dramatically collapsed, one hand reaching to sky"),
        ("defend stance", "musical notes forming barrier, harmony shield"),
        ("walking pose", "skipping stride, cape flowing, lute bouncing on back"),
        ("item use pose", "pulling flask from doublet, theatrical toast"),
        ("buff casting pose", "playing inspirational fanfare on lute, party energized"),
        ("debuff pose", "playing discordant notes, dissonant magical aura"),
        ("taunt pose", "provocative flourish with rapier, taunting gesture"),
    ],
    "guardian": [
        ("idle stance", "immovable stance, tower shield planted, visor lowered"),
        ("defend stance", "tower shield wall raised, full defensive position"),
        ("attack pose", "shield bash charge forward, full body slam"),
        ("victory pose", "shield raised high, helmet visor lifted, triumphant"),
        ("hit reaction", "pushed back but not falling, shield absorbing blow"),
        ("death pose", "collapsed against shield, armor cracked"),
        ("casting pose", "holy aura emanating from armor, defensive blessing"),
        ("walking pose", "slow heavy march forward, shield and sword ready"),
        ("item use pose", "lifting visor briefly to drink potion"),
        ("provoke taunt pose", "banging sword on shield, drawing enemy attention"),
        ("power strike pose", "massive overhead shield smash downward"),
        ("battle stance", "shield forward, sword behind, impenetrable wall stance"),
    ],
    "ninja": [
        ("idle stance", "crouched ready stance, eyes alert, dark wrappings"),
        ("attack pose", "spinning multi-kunai throw in arc"),
        ("battle stance", "low crouch, kunai in each hand, ready to vanish"),
        ("victory pose", "sheathing weapons with fluid grace, bow of respect"),
        ("hit reaction", "mid-air dodge, barely missed, hair flicking"),
        ("death pose", "slumped quietly, mask still on, honorable"),
        ("defend stance", "deflecting projectile mid-air, open palm block"),
        ("walking pose", "silent sprint across ground, barely touching floor"),
        ("item use pose", "applying poison to kunai blade quickly"),
        ("advance action pose", "explosive burst forward dash, after-image left behind"),
        ("backstab attack pose", "materializing from shadows, precise kunai thrust"),
        ("casting pose", "throwing shadow bomb, smoke and dark energy expanding"),
    ],
    "summoner": [
        ("idle stance", "hovering slightly, robes drifting, grimoire floating open"),
        ("casting pose", "arcane summoning circle forming at feet, arms raised"),
        ("attack pose", "commanding summoned energy bolt forward, pointing"),
        ("victory pose", "ethereal wings briefly manifesting, radiant aura"),
        ("hit reaction", "grimoire snapping shut, magic dispersing, stumbling"),
        ("death pose", "floating form dissolving, grimoire slowly closing"),
        ("defend stance", "arcane sigil barrier erected, runes glowing"),
        ("walking pose", "gliding forward, trailing magical particles in wake"),
        ("item use pose", "absorbing power from mystic orb, hands cupped"),
        ("summoning pose", "portal tearing open, silhouette of creature emerging"),
        ("channeling pose", "kneeling in meditation, astral energy converging"),
        ("battle stance", "grimoire open, pen hovering, ready to inscribe fate"),
    ],
}

# Shared base negative prompt
BASE_NEGATIVE = (
    "multiple characters, multiple views, sprite sheet, reference sheet, "
    "turnaround, model sheet, concept art, collage, grid, tiled, "
    "background scenery, landscape, room, floor, wall, "
    "blurry, photorealistic, 3D render, text, watermark, deformed, "
    "oversexualized, revealing armor, bikini armor"
)

STYLE_TAG = "jrpg_pixel_style"


def build_dalle_prompt(job: str, pose_desc: str, style_ref: str) -> str:
    spec = JOB_SPECS[job]
    return (
        f"A single pixel art RPG battle character sprite. "
        f"{spec['desc']}, {pose_desc}. "
        f"Side view. Black pixel outline. Plain white background. "
        f"Palette: {spec['palette_hint']}. "
        f"{style_ref}. "
        f"16-bit SNES JRPG style, chunky pixel art, limited color palette. "
        f"IMPORTANT: Show ONLY the single character sprite. "
        f"NO palette swatches. NO color charts. NO reference sheets. "
        f"NO multiple views. NO sprite sheets. NO grids. NO labels. "
        f"NO color samples. NO annotations. Just the ONE character on white."
    )


def make_caption(job: str, pose_tag: str) -> str:
    return (
        f"{STYLE_TAG}, pixel art battle sprite, {job} character, "
        f"{pose_tag}, side view, SNES 16-bit style, black pixel outline"
    )


def load_usage() -> dict:
    if USAGE_FILE.exists():
        with open(USAGE_FILE) as f:
            return json.load(f)
    return {"total_images": 0, "total_cost_usd": 0.0, "sessions": []}


def save_usage(usage: dict) -> None:
    USAGE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(USAGE_FILE, "w") as f:
        json.dump(usage, f, indent=2)


def download_image(url: str, dest: Path, timeout: int = 60) -> bool:
    """Download image from URL to dest path. Returns True on success."""
    try:
        resp = httpx.get(url, timeout=timeout, follow_redirects=True)
        resp.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(resp.content)
        return True
    except Exception as exc:
        print(f"  WARN  download failed for {dest.name}: {exc}")
        return False


def process_raw_to_dataset(
    raw_png: Path,
    output_dir: Path,
    caption: str,
    counter: list[int],
    canvas_size: int = 512,
) -> bool:
    """
    Process a single raw DALL-E PNG into a 512x512 training frame.

    Steps:
      1. Open and convert to RGBA (white background -> transparent via threshold)
      2. Auto-crop to opaque bounding box
      3. Scale so largest dimension fills 75% of canvas
      4. Center on transparent canvas
      5. Validate fill ratio (5-85%)
      6. Save PNG + TXT caption pair
    """
    try:
        with Image.open(raw_png) as img:
            img_rgba = img.convert("RGBA")
    except Exception as exc:
        print(f"  SKIP  {raw_png.name}: open failed ({exc})")
        return False

    import numpy as np
    arr = np.array(img_rgba)

    # --- Background color detection ---
    # Sample corners (10x10 patch each) to detect background color
    h_px, w_px = arr.shape[:2]
    patch = 12
    corners = [
        arr[:patch, :patch, :3],
        arr[:patch, -patch:, :3],
        arr[-patch:, :patch, :3],
        arr[-patch:, -patch:, :3],
    ]
    corner_colors = np.concatenate([c.reshape(-1, 3) for c in corners], axis=0)
    corner_std = corner_colors.std(axis=0).max()
    bg_color = corner_colors.mean(axis=0)  # [R, G, B]

    if corner_std < 25:
        # Uniform background — remove it with a tolerance
        tolerance = 30
        bg_mask = (
            (np.abs(arr[:, :, 0].astype(int) - bg_color[0]) < tolerance) &
            (np.abs(arr[:, :, 1].astype(int) - bg_color[1]) < tolerance) &
            (np.abs(arr[:, :, 2].astype(int) - bg_color[2]) < tolerance)
        )
        arr[:, :, 3] = np.where(bg_mask, 0, arr[:, :, 3])
    else:
        # Fallback: remove only near-white pixels
        bg_mask = (arr[:, :, 0] > 235) & (arr[:, :, 1] > 235) & (arr[:, :, 2] > 235)
        arr[:, :, 3] = np.where(bg_mask, 0, arr[:, :, 3])

    img_rgba = Image.fromarray(arr, "RGBA")

    # --- Palette swatch and reference strip erasure ---
    # DALL-E adds palette swatches and animation reference strips at the edges.
    # Check all four margins. Erase any margin strip that is heavily filled with
    # small uniform-color blocks (palette) or repeated tiny sprites.
    #
    # Strategy: for each edge strip (left 15%, right 15%, top 18%, top-right corner),
    # if opaque fill > threshold, blank it out. Then re-detect after each erasure.

    def erase_if_filled(region_mask_fn: callable, threshold: float = 0.12) -> bool:
        """Apply region_mask_fn to arr, erase if fill > threshold. Returns True if erased."""
        region = arr[region_mask_fn()]
        al = region[:, :, 3] if region.ndim == 3 else region
        opaque = (al > 10).sum()
        total = al.size
        fill = opaque / total if total > 0 else 0
        if fill > threshold:
            arr[region_mask_fn()][..., 3] = 0
            return True
        return False

    # Left strip: left 15% of width
    left_w = int(w_px * 0.15)
    left_region = arr[:, :left_w, :]
    left_alpha = left_region[:, :, 3]
    left_fill = (left_alpha > 10).sum() / left_alpha.size
    if left_fill > 0.12:
        arr[:, :left_w, 3] = 0

    # Right strip: right 15% of width
    right_w = int(w_px * 0.15)
    right_region = arr[:, -right_w:, :]
    right_alpha = right_region[:, :, 3]
    right_fill = (right_alpha > 10).sum() / right_alpha.size
    if right_fill > 0.12:
        arr[:, -right_w:, 3] = 0

    # Top strip: top 18% of height
    top_h = int(h_px * 0.18)
    top_region = arr[:top_h, :, :]
    top_alpha = top_region[:, :, 3]
    top_fill = (top_alpha > 10).sum() / top_alpha.size
    if top_fill > 0.12:
        arr[:top_h, :, 3] = 0

    # Top-right quadrant corner: top 22% x right 40% (catches diagonal swatch placement)
    tr_region = arr[:int(h_px * 0.22), int(w_px * 0.60):, :]
    tr_alpha = tr_region[:, :, 3]
    tr_fill = (tr_alpha > 10).sum() / tr_alpha.size
    if tr_fill > 0.12:
        arr[:int(h_px * 0.22), int(w_px * 0.60):, 3] = 0

    # Bottom strip: bottom 12% of height (palette row below sprite)
    bot_h = int(h_px * 0.12)
    bot_region = arr[-bot_h:, :, :]
    bot_alpha = bot_region[:, :, 3]
    bot_fill = (bot_alpha > 10).sum() / bot_alpha.size
    if bot_fill > 0.12:
        arr[-bot_h:, :, 3] = 0

    img_rgba = Image.fromarray(arr, "RGBA")

    # Auto-crop to bounding box of opaque pixels
    alpha = img_rgba.split()[3]
    bbox = alpha.point(lambda p: 255 if p > 10 else 0).getbbox()
    if bbox is None:
        print(f"  SKIP  {raw_png.name}: entirely transparent after bg removal")
        return False

    cropped = img_rgba.crop(bbox)
    cw, ch = cropped.size
    if cw == 0 or ch == 0:
        print(f"  SKIP  {raw_png.name}: zero-size crop")
        return False

    # Scale so largest dimension = 75% of canvas
    target_px = int(canvas_size * 0.75)
    scale = target_px / max(cw, ch)
    new_w = max(1, round(cw * scale))
    new_h = max(1, round(ch * scale))
    # Use LANCZOS for quality downscale (DALL-E is 1024px, we scale to ~384px within 512)
    scaled = cropped.resize((new_w, new_h), Image.LANCZOS)

    # Center on canvas
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - new_w) // 2
    y = (canvas_size - new_h) // 2
    canvas.paste(scaled, (x, y), scaled)

    # Validate fill ratio
    total_px = canvas_size * canvas_size
    opaque_px = sum(1 for p in canvas.split()[3].tobytes() if p > 10)
    fill = opaque_px / total_px
    if fill < 0.05:
        print(f"  SKIP  {raw_png.name}: fill too low ({fill:.1%})")
        return False
    if fill > 0.85:
        print(f"  SKIP  {raw_png.name}: fill too high ({fill:.1%})")
        return False

    idx = counter[0]
    counter[0] += 1

    out_png = output_dir / f"sprite_{idx:03d}.png"
    out_txt = output_dir / f"sprite_{idx:03d}.txt"

    canvas.save(out_png, "PNG")
    out_txt.write_text(caption, encoding="utf-8")
    print(f"  OK    {raw_png.name} -> sprite_{idx:03d}.png  (fill={fill:.1%})")
    return True


def generate_all(
    client: OpenAI,
    jobs: list[str],
    max_images: int,
    dry_run: bool,
    rate_limit_secs: float,
) -> dict:
    """
    Drive DALL-E 3 generation for all requested jobs and poses.

    Returns a session record dict with counts and cost.
    """
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    usage = load_usage()
    session = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "jobs": jobs,
        "images_attempted": 0,
        "images_downloaded": 0,
        "images_processed": 0,
        "cost_usd": 0.0,
        "errors": [],
    }

    counter = [0]
    # Start counter after any existing processed sprites
    existing = sorted(OUTPUT_DIR.glob("sprite_*.png"))
    if existing:
        last_idx = int(existing[-1].stem.split("_")[1])
        counter[0] = last_idx + 1
        print(f"Resuming from sprite index {counter[0]} ({len(existing)} existing sprites)")

    total_generated = 0

    for job in jobs:
        if job not in JOB_SPECS:
            print(f"WARNING: unknown job '{job}', skipping")
            continue
        if job not in JOB_POSES:
            print(f"WARNING: no poses defined for '{job}', skipping")
            continue

        poses = JOB_POSES[job]
        print(f"\n--- Job: {job} ({len(poses)} poses) ---")

        for i, (pose_tag, pose_desc) in enumerate(poses):
            if total_generated >= max_images:
                print(f"  Reached max_images={max_images}, stopping.")
                break

            style_ref = STYLE_REFS[total_generated % len(STYLE_REFS)]
            prompt = build_dalle_prompt(job, pose_desc, style_ref)
            caption = make_caption(job, pose_tag)

            # Filename for raw download
            safe_pose = pose_tag.replace(" ", "_").replace("/", "_")
            raw_filename = f"{job}_{safe_pose}_{i:02d}.png"
            raw_path = RAW_DIR / raw_filename

            print(f"  [{total_generated+1}/{max_images}] {job}/{pose_tag}")
            print(f"    style: {style_ref}")

            if dry_run:
                print(f"    DRY RUN: would generate -> {raw_filename}")
                total_generated += 1
                session["images_attempted"] += 1
                continue

            # Skip if already downloaded (allows reruns)
            if raw_path.exists():
                print(f"    Already downloaded, re-processing only.")
                ok = process_raw_to_dataset(raw_path, OUTPUT_DIR, caption, counter)
                if ok:
                    session["images_processed"] += 1
                total_generated += 1
                continue

            # Call DALL-E 3
            try:
                response = client.images.generate(
                    model="dall-e-3",
                    prompt=prompt,
                    n=1,
                    size="1024x1024",
                    quality="standard",
                    response_format="url",
                )
                image_url = response.data[0].url
                session["images_attempted"] += 1
                session["cost_usd"] += COST_PER_IMAGE
                usage["total_images"] += 1
                usage["total_cost_usd"] += COST_PER_IMAGE

            except Exception as exc:
                err_msg = str(exc)
                print(f"  ERROR generating {job}/{pose_tag}: {err_msg}")
                session["errors"].append({"job": job, "pose": pose_tag, "error": err_msg})
                # Check for billing/quota errors — halt gracefully
                if any(kw in err_msg.lower() for kw in ["billing", "quota", "exceeded", "insufficient"]):
                    print("  BILLING LIMIT HIT — saving progress and stopping.")
                    session["halt_reason"] = "billing_limit"
                    usage["sessions"].append(session)
                    save_usage(usage)
                    return session
                # Rate limit — back off
                if "rate_limit" in err_msg.lower():
                    print("  Rate limit hit — waiting 60s...")
                    time.sleep(60)
                continue

            # Download from URL (URLs expire ~1 hour)
            print(f"    Downloading...")
            downloaded = download_image(image_url, raw_path)
            if downloaded:
                session["images_downloaded"] += 1
                print(f"    Saved raw: {raw_filename}")

                # Process to training frame immediately
                ok = process_raw_to_dataset(raw_path, OUTPUT_DIR, caption, counter)
                if ok:
                    session["images_processed"] += 1
            else:
                session["errors"].append({
                    "job": job, "pose": pose_tag, "error": "download_failed",
                    "url": image_url,
                })

            total_generated += 1

            # Rate limiting between API calls
            if total_generated < max_images:
                time.sleep(rate_limit_secs)

    usage["sessions"].append(session)
    save_usage(usage)

    print(f"\n=== Session Summary ===")
    print(f"  Attempted   : {session['images_attempted']}")
    print(f"  Downloaded  : {session['images_downloaded']}")
    print(f"  Processed   : {session['images_processed']}")
    print(f"  Session cost: ${session['cost_usd']:.2f}")
    print(f"  Total spend : ${usage['total_cost_usd']:.2f} ({usage['total_images']} images)")
    print(f"  Errors      : {len(session['errors'])}")
    if session["errors"]:
        for e in session["errors"][:5]:
            print(f"    - {e['job']}/{e['pose']}: {e['error'][:80]}")

    return session


def process_only_mode(jobs: list[str]) -> None:
    """Re-process all raw files in RAW_DIR that haven't been turned into training frames yet."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    counter = [0]
    existing = sorted(OUTPUT_DIR.glob("sprite_*.png"))
    if existing:
        last_idx = int(existing[-1].stem.split("_")[1])
        counter[0] = last_idx + 1

    raw_pngs = sorted(RAW_DIR.glob("*.png"))
    print(f"Processing {len(raw_pngs)} raw files from {RAW_DIR}")
    accepted = 0
    for raw_path in raw_pngs:
        # Infer job and pose from filename: {job}_{safe_pose}_{idx}.png
        stem_parts = raw_path.stem.split("_")
        job = stem_parts[0] if stem_parts else "fighter"
        # Reconstruct pose from remaining parts minus trailing index
        pose_parts = stem_parts[1:-1] if len(stem_parts) > 2 else stem_parts[1:]
        pose_tag = " ".join(pose_parts).replace("_", " ")
        caption = make_caption(job, pose_tag or "battle stance")

        ok = process_raw_to_dataset(raw_path, OUTPUT_DIR, caption, counter)
        if ok:
            accepted += 1

    print(f"\nProcessed {accepted}/{len(raw_pngs)} files accepted into dataset.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate JRPG pixel art training data via DALL-E 3."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print prompts without calling the API.",
    )
    parser.add_argument(
        "--jobs",
        nargs="+",
        default=list(JOB_SPECS.keys()),
        help="Job IDs to generate (default: all 8 jobs).",
    )
    parser.add_argument(
        "--max-images",
        type=int,
        default=96,
        help="Maximum total images to generate (default: 96, ~$3.84).",
    )
    parser.add_argument(
        "--rate-limit",
        type=float,
        default=1.5,
        help="Seconds between API calls (default: 1.5).",
    )
    parser.add_argument(
        "--process-only",
        action="store_true",
        help="Skip generation; only re-process existing raw files into training frames.",
    )
    parser.add_argument(
        "--canvas-size",
        type=int,
        default=512,
        help="Output canvas size in pixels (default: 512).",
    )
    args = parser.parse_args()

    print(f"Output dir : {OUTPUT_DIR}")
    print(f"Raw dir    : {RAW_DIR}")
    print(f"Usage file : {USAGE_FILE}")
    print(f"Jobs       : {', '.join(args.jobs)}")
    print(f"Max images : {args.max_images}")
    print(f"Est. cost  : ${args.max_images * COST_PER_IMAGE:.2f}")
    print()

    if args.process_only:
        process_only_mode(args.jobs)
        return

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("ERROR: OPENAI_API_KEY not set in environment.", file=sys.stderr)
        sys.exit(1)

    client = OpenAI(api_key=api_key)

    if args.dry_run:
        print("DRY RUN mode — no API calls will be made.\n")
        # Print first few prompts for review
        shown = 0
        for job in args.jobs:
            if job not in JOB_POSES:
                continue
            for i, (pose_tag, pose_desc) in enumerate(JOB_POSES[job]):
                style_ref = STYLE_REFS[shown % len(STYLE_REFS)]
                prompt = build_dalle_prompt(job, pose_desc, style_ref)
                caption = make_caption(job, pose_tag)
                print(f"[{shown+1}] {job}/{pose_tag}")
                print(f"  PROMPT : {prompt[:120]}...")
                print(f"  CAPTION: {caption}")
                print()
                shown += 1
                if shown >= 5:
                    print(f"  ... ({args.max_images - 5} more prompts)")
                    break
            if shown >= 5:
                break

    generate_all(
        client=client,
        jobs=args.jobs,
        max_images=args.max_images,
        dry_run=args.dry_run,
        rate_limit_secs=args.rate_limit,
    )


if __name__ == "__main__":
    main()
