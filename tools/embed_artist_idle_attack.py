#!/usr/bin/env python3
"""
Embed artist sprites from drive_archive into the game repo.

No ML, no palette mangling, no aseprite *edits*. Two source modes:

1. Tagged-aseprite mode (preferred once the artist has normalized a file):
   Call `aseprite -b --tag <name> --sheet out.png file.aseprite` to export
   the named tag as a horizontal strip of 128x128 frames.

2. Pre-rendered PNG mode (fallback for not-yet-normalized characters):
   Use the artist's already-exported PNG sheets next to the .aseprite.

Both modes produce 128px-tall strips which are 2x nearest-neighbor upscaled
to the 256x256 frame size the game's sprite_manifest expects.

Destinations: /home/struktured/projects/cowardly-irregular/assets/sprites/jobs/<job>/{idle,attack}.png
"""

import os
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DRIVE = REPO / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters"
_DEFAULT_GAME = "/home/struktured/projects/cowardly-irregular"
GAME_JOBS = Path(os.environ.get("GAME_REPO", _DEFAULT_GAME)) / "assets" / "sprites" / "jobs"

# Tagged-aseprite exports: (job, dest_anim, aseprite_rel, tag_name)
ASE_EXPORTS = [
    ("fighter", "idle",   "FIGHTER/Main Fighter animations.aseprite", "IDLE"),
    ("fighter", "attack", "FIGHTER/Main Fighter animations.aseprite", "Attack"),
    ("cleric",  "idle",   "CLERIC/Cleric Main design.aseprite",       "Idle"),
    ("cleric",  "cast",   "CLERIC/Cleric Main design.aseprite",       "Cast"),
    ("rogue",   "idle",   "ROGUE/Rogue Main design.aseprite",         "Idle"),
    ("rogue",   "attack", "ROGUE/Rogue Main design.aseprite",         "ATK"),
    ("mage",    "idle",   "MAGE/Mage Main design.aseprite",           "IDLE"),
    ("mage",    "attack", "MAGE/Mage Main design.aseprite",           "Atk 1"),
    # Pre-attack lunge — cowir-battle wires this into BattleAnimator.
    # Artist's tag is "Dash"; game-side filename is `lunge.png`.
    ("fighter", "lunge",  "FIGHTER/Main Fighter animations.aseprite", "Dash"),
]

# Pre-rendered PNG embeds: (job, dest_anim, png_rel, dup_to_frames)
PNG_EMBEDS = []


def load_strip_128(src: Path, dup_to: int | None) -> Image.Image:
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    assert h == 128, f"{src.name}: expected 128 tall, got {h}"
    assert w % 128 == 0, f"{src.name}: width {w} not multiple of 128"
    if dup_to:
        frame = im.crop((0, 0, 128, 128))
        strip = Image.new("RGBA", (128 * dup_to, 128))
        for i in range(dup_to):
            strip.paste(frame, (i * 128, 0))
        return strip
    return im


def export_aseprite_tag(ase: Path, tag: str) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        out = Path(tf.name)
    subprocess.run(
        ["aseprite", "-b", "--tag", tag, "--sheet", str(out), str(ase)],
        check=True, capture_output=True,
    )
    im = Image.open(out).convert("RGBA")
    out.unlink()
    return im


def deploy(strip: Image.Image, job: str, anim: str, source_desc: str) -> None:
    up = strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST)
    dest_dir = GAME_JOBS / job
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{anim}.png"
    up.save(dest, optimize=True)
    frames = strip.width // 128
    print(f"OK   {job}/{anim}.png  <- {source_desc}  ({frames}f, {up.size[0]}x{up.size[1]})")


def main():
    for job, anim, rel, tag in ASE_EXPORTS:
        ase = DRIVE / rel
        if not ase.exists():
            print(f"SKIP {job}/{anim}: missing aseprite {ase}")
            continue
        strip = export_aseprite_tag(ase, tag)
        deploy(strip, job, anim, f"{rel} [tag:{tag}]")

    for job, anim, rel, dup in PNG_EMBEDS:
        src = DRIVE / rel
        if not src.exists():
            print(f"SKIP {job}/{anim}: missing source {src}")
            continue
        strip = load_strip_128(src, dup)
        deploy(strip, job, anim, rel)


if __name__ == "__main__":
    main()
