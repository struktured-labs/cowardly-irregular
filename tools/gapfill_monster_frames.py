#!/usr/bin/env python3
"""gpt-image gap-fill for animations the artist did NOT author.

Sanctioned by struktured 2026-07-25: "gpt2 to FILL in missing artist
sprite frames still fair game" — with the hard constraint that it never
substitutes for a frame the artist DID draw.

Safety model:
  * Reads an ARTIST frame from the existing sheet purely as an identity
    anchor (never modified, never overwritten).
  * APPENDS generated frames to the tail of the strip. Artist frames keep
    their original indices, so every authored animation range is untouched
    by construction.
  * Refuses to run if the requested anim already maps into artist frames.

Usage:
  uv run python tools/gapfill_monster_frames.py \
      --monster-id chancellor_mordaine --anchor-frame 0 \
      --fill hit --fill dead --quality high
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
    "GAME_REPO", "/home/struktured/projects/cowardly-irregular-artist-ship"))
RAW_DIR = PROJECT / "tmp" / "monster_gapfill"
COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

POSE_PROMPTS = {
    "hit": ("STANDING UPRIGHT and flinching from a blow — still on her feet, "
            "still vertical, weight rocked back onto the rear foot, head "
            "tilted back slightly, one arm drawn protectively across the "
            "body, shoulders hunched, expression pained. A STAGGER, not a "
            "fall. Her head stays near the TOP of the frame and her feet "
            "stay near the BOTTOM"),
    "dead": ("DEFEATED but still VERTICAL — sunk down onto one knee with the "
             "torso slumped forward and the head bowed low, one hand braced "
             "on the ground, the other arm hanging limp. Beaten and spent, "
             "yet the figure still reads head-at-top / ground-at-bottom. She "
             "is KNEELING, absolutely NOT lying flat"),
}


def build_prompt(desc: str, poses: list[str]) -> str:
    n = len(poses)
    layout = (f"a horizontal row of {n} frames, evenly spaced, each frame "
              f"square and the SAME size") if n > 1 else "a single frame"
    pose_txt = " ".join(
        f"Frame {i+1}: the SAME character {POSE_PROMPTS[p]}."
        for i, p in enumerate(poses))
    return (
        f"16-bit JRPG pixel-art battle sprite sheet: {layout}. "
        f"The reference image shows the EXACT character — copy her design "
        f"precisely: same silhouette, same palette, same hair, same costume, "
        f"same proportions, same lineart weight and shading style. "
        f"Character: {desc}. {pose_txt} "
        f"CRITICAL ORIENTATION RULE — every frame must match the reference's "
        f"framing exactly: the character is drawn UPRIGHT and VERTICAL, "
        f"head near the top of the frame, feet/ground contact near the "
        f"bottom, occupying the SAME height and the SAME amount of the frame "
        f"as the reference figure. NEVER draw the character rotated, lying "
        f"horizontally, sideways, sprawled across the frame's width, or "
        f"viewed from above. A defeated pose is a KNEEL or a SLUMP, never a "
        f"body lying flat. "
        f"Fully transparent background, no scenery, no shadows, no ground "
        f"plane, no text. Each frame centered in its cell. Clean pixel art, "
        f"bold outlines, soft cel shading, no anti-aliasing artifacts, no "
        f"floating pixels, no duplicate limbs. EXACTLY ONE FIGURE per frame."
    )


def call_gpt(client, prompt, ref_bytes, quality, retries=3):
    for attempt in range(retries):
        try:
            resp = client.images.edit(
                model="gpt-image-1",
                image=("anchor.png", ref_bytes, "image/png"),
                prompt=prompt, size="1024x1024", quality=quality, n=1)
            return Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        except Exception as e:
            m = str(e).lower()
            if "rate" in m or "429" in m:
                time.sleep(30 * (attempt + 1))
            elif any(k in m for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"  error: {e}; retry"); time.sleep(5)
    raise RuntimeError("failed after retries")


def downscale(img, target):
    img = img.convert("RGBA")
    return img.resize((target * 4, target * 4), Image.LANCZOS) \
              .resize((target, target), Image.BOX)


def transparent_bg(img, threshold=240):
    img = img.convert("RGBA"); px = img.load(); W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--monster-id", required=True)
    ap.add_argument("--fill", action="append", required=True, dest="fills",
                    choices=sorted(POSE_PROMPTS))
    ap.add_argument("--replace-reused", action="append", default=[],
                    metavar="ANIM",
                    help="repoint an anim whose current mapping REUSES other "
                         "frames rather than being authored art. Must name "
                         "each anim explicitly.")
    ap.add_argument("--anchor-frame", type=int, default=0)
    ap.add_argument("--desc", default="")
    ap.add_argument("--quality", choices=list(COST), default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    mpath = GAME_REPO / "data" / "sprite_manifest.json"
    manifest = json.loads(mpath.read_text())
    entry = manifest.get("monster_sheets", {}).get(args.monster_id)
    if entry is None:
        print(f"ERROR: {args.monster_id} not in monster_sheets — wire the "
              f"artist sheet first", file=sys.stderr)
        return 1

    for anim in args.fills:
        if anim in entry["animations"] and anim not in args.replace_reused:
            print(f"REFUSING: '{anim}' already maps to frames "
                  f"{entry['animations'][anim]} — gap-fill must never "
                  f"overwrite authored animation. If that mapping is a REUSE "
                  f"of other frames rather than authored art, pass "
                  f"--replace-reused {anim} to repoint it.", file=sys.stderr)
            return 1
    # --replace-reused exists because "the anim is registered" and "the anim
    # was authored" are different facts, and the manifest only records the
    # second in prose. goblin ships hit -> frame 3 (an attack WINDUP) and
    # dead -> frame 0 (a plain idle): registered, non-authored, and visibly
    # wrong in play. The guard above still blocks the dangerous case; this
    # flag makes the caller name each repoint explicitly rather than letting
    # a bulk run silently clobber real artist frames.

    sheet_path = GAME_REPO / "assets" / "sprites" / "monsters" / f"{args.monster_id}.png"
    sheet = Image.open(sheet_path).convert("RGBA")
    fw = entry["frame_width"]; fh = entry["frame_height"]
    n_existing = sheet.width // fw

    anchor = sheet.crop((args.anchor_frame * fw, 0,
                         (args.anchor_frame + 1) * fw, fh))
    up = anchor.resize((1024, 1024), Image.NEAREST)
    buf = io.BytesIO(); up.save(buf, format="PNG")

    prompt = build_prompt(args.desc or args.monster_id.replace("_", " "),
                          args.fills)
    cost = COST[args.quality]
    print(f"[{args.monster_id}] sheet {sheet.width}x{sheet.height} "
          f"({n_existing} frames of {fw})")
    print(f"  anchor: artist frame {args.anchor_frame}")
    print(f"  filling: {', '.join(args.fills)}  -> frames "
          f"{n_existing}..{n_existing + len(args.fills) - 1}")
    print(f"  cost: ${cost:.3f}")
    if args.dry_run:
        print("\nDRY RUN"); return 0

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI()
    raw = call_gpt(client, prompt, buf.getvalue(), args.quality)
    raw.save(RAW_DIR / f"{args.monster_id}_gapfill_raw.png")

    n = len(args.fills)
    tile_w = raw.width // n
    new_frames = []
    for i in range(n):
        tile = raw.crop((i * tile_w, 0, (i + 1) * tile_w, raw.height))
        new_frames.append(transparent_bg(downscale(tile, fw)))

    out = Image.new("RGBA", (sheet.width + fw * n, fh), (0, 0, 0, 0))
    out.paste(sheet, (0, 0))
    for i, fr in enumerate(new_frames):
        out.paste(fr, (sheet.width + i * fw, 0))
    out.save(sheet_path)

    for i, anim in enumerate(args.fills):
        idx = n_existing + i
        entry["animations"][anim] = {"start": idx, "end": idx}
    entry["source"] = entry.get("source", "") + (
        f"; gpt-image gap-fill (artist did not author): "
        f"{', '.join(args.fills)} at frames "
        f"{n_existing}..{n_existing + n - 1}")
    mpath.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"\n  -> {sheet_path} ({out.width}x{out.height}, "
          f"{out.width // fw} frames)")
    print(f"  manifest updated; artist frames 0..{n_existing - 1} untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
