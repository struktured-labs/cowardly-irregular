#!/usr/bin/env python3
"""
ElevenLabs Sound Effects Generator for Cowardly Irregular.

Reads data/sfx_manifest.json, generates OGG sound effects via ElevenLabs API,
saves them to assets/audio/sfx/.

Usage:
    # Generate all missing SFX
    uv run tools/elevenlabs_sfx.py

    # Generate specific sound keys
    uv run tools/elevenlabs_sfx.py attack_hit critical_hit heal

    # Regenerate all (overwrite existing)
    uv run tools/elevenlabs_sfx.py --force

    # Dry run (show what would be generated)
    uv run tools/elevenlabs_sfx.py --dry-run

Requires: ELEVENLABS_API_KEY env var (source setenv.sh)
"""
# /// script
# requires-python = ">=3.10"
# dependencies = ["httpx"]
# ///

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import httpx

API_URL = "https://api.elevenlabs.io/v1/sound-generation"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = PROJECT_ROOT / "data" / "sfx_manifest.json"
SFX_DIR = PROJECT_ROOT / "assets" / "audio" / "sfx"

# Rate limiting: ElevenLabs has rate limits, be polite
REQUEST_DELAY_SECONDS = 1.5


def get_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not key:
        print("ERROR: ELEVENLABS_API_KEY not set. Run: source setenv.sh", file=sys.stderr)
        sys.exit(1)
    return key


def load_manifest() -> dict:
    with open(MANIFEST_PATH) as f:
        return json.load(f)


def has_ffmpeg() -> bool:
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def convert_mp3_to_ogg(mp3_path: Path, ogg_path: Path) -> bool:
    """Convert MP3 to OGG Vorbis using ffmpeg."""
    try:
        result = subprocess.run(
            [
                "ffmpeg", "-y",
                "-i", str(mp3_path),
                "-c:a", "libvorbis",
                "-q:a", "6",  # Quality 6 (~192kbps) — good for SFX
                str(ogg_path),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            mp3_path.unlink()  # Clean up temp MP3
            return True
        else:
            print(f"  ffmpeg error: {result.stderr[:200]}", file=sys.stderr)
            return False
    except FileNotFoundError:
        print("ERROR: ffmpeg not found. Install it: sudo apt install ffmpeg", file=sys.stderr)
        return False


def generate_sfx(
    key: str,
    entry: dict,
    api_key: str,
    model_id: str,
    force: bool = False,
) -> bool:
    """Generate a single sound effect. Returns True on success."""
    ogg_path = PROJECT_ROOT / entry["file"]
    ogg_path.parent.mkdir(parents=True, exist_ok=True)

    if ogg_path.exists() and not force:
        print(f"  SKIP {key}: {ogg_path.name} already exists")
        return True

    prompt = entry["prompt"]
    duration = entry.get("duration_seconds", 1.0)
    influence = entry.get("prompt_influence", 0.3)

    print(f"  GEN  {key}: \"{prompt[:60]}...\" ({duration}s)")

    body = {
        "text": prompt,
        "model_id": model_id,
        "duration_seconds": duration,
        "prompt_influence": influence,
    }

    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
    }

    try:
        with httpx.Client(timeout=60.0) as client:
            resp = client.post(
                API_URL,
                json=body,
                headers=headers,
                params={"output_format": "mp3_44100_128"},
            )

        if resp.status_code == 200:
            # Save as temp MP3, convert to OGG
            mp3_path = ogg_path.with_suffix(".mp3")
            mp3_path.write_bytes(resp.content)

            if convert_mp3_to_ogg(mp3_path, ogg_path):
                size_kb = ogg_path.stat().st_size / 1024
                print(f"  OK   {key}: {ogg_path.name} ({size_kb:.1f} KB)")
                return True
            else:
                print(f"  FAIL {key}: ffmpeg conversion failed", file=sys.stderr)
                return False
        else:
            error_detail = resp.text[:300]
            print(f"  FAIL {key}: HTTP {resp.status_code} — {error_detail}", file=sys.stderr)
            return False

    except httpx.TimeoutException:
        print(f"  FAIL {key}: request timed out", file=sys.stderr)
        return False
    except httpx.HTTPError as e:
        print(f"  FAIL {key}: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Generate JRPG SFX via ElevenLabs API")
    parser.add_argument("keys", nargs="*", help="Specific sound keys to generate (default: all)")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be generated")
    parser.add_argument("--influence", type=float, default=None, help="Override prompt_influence (0-1)")
    args = parser.parse_args()

    if not has_ffmpeg():
        print("ERROR: ffmpeg required. Install: sudo apt install ffmpeg", file=sys.stderr)
        sys.exit(1)

    manifest = load_manifest()
    model_id = manifest.get("model_id", "eleven_text_to_sound_v2")
    sfx_entries = manifest.get("sfx", {})

    # Filter to requested keys
    if args.keys:
        missing = [k for k in args.keys if k not in sfx_entries]
        if missing:
            print(f"ERROR: Unknown sound keys: {', '.join(missing)}", file=sys.stderr)
            print(f"Available: {', '.join(sorted(sfx_entries.keys()))}", file=sys.stderr)
            sys.exit(1)
        keys = args.keys
    else:
        keys = list(sfx_entries.keys())

    # Apply influence override
    if args.influence is not None:
        for key in keys:
            sfx_entries[key]["prompt_influence"] = args.influence

    # Determine what needs generating
    to_generate = []
    for key in keys:
        entry = sfx_entries[key]
        ogg_path = PROJECT_ROOT / entry["file"]
        if ogg_path.exists() and not args.force:
            continue
        to_generate.append(key)

    if not to_generate:
        print(f"All {len(keys)} SFX files already exist. Use --force to regenerate.")
        return

    print(f"{'[DRY RUN] ' if args.dry_run else ''}Generating {len(to_generate)}/{len(keys)} sound effects...")
    print(f"Model: {model_id}")
    print()

    if args.dry_run:
        for key in to_generate:
            entry = sfx_entries[key]
            ogg_path = PROJECT_ROOT / entry["file"]
            status = "OVERWRITE" if ogg_path.exists() else "NEW"
            print(f"  {status:9s} {key:25s} {entry['duration_seconds']:4.1f}s  \"{entry['prompt'][:55]}...\"")
        print(f"\nTotal: {len(to_generate)} files would be generated")
        return

    api_key = get_api_key()
    SFX_DIR.mkdir(parents=True, exist_ok=True)

    success = 0
    failed = 0

    for i, key in enumerate(to_generate):
        entry = sfx_entries[key]
        if generate_sfx(key, entry, api_key, model_id, args.force):
            success += 1
        else:
            failed += 1

        # Rate limit between requests
        if i < len(to_generate) - 1:
            time.sleep(REQUEST_DELAY_SECONDS)

    print(f"\nDone: {success} generated, {failed} failed, {len(keys) - len(to_generate)} skipped")

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
