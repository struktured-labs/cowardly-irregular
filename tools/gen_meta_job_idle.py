#!/usr/bin/env python3
"""Generate the 5 missing meta-job idle.png battle sheets.

Measured on origin/main: bossbinder / necromancer / scriptweaver / skiptrotter /
time_mage have an overworld.png and NO idle.png at all. That is the last T0
surface in the game — they render procedurally in battle AND have no dialogue
portrait, because CutsceneDialogue._create_bust_from_job_sheet crops frame 0 of
this exact file.

TWO anchors, following gen_overworld_gpt_image's pattern:
  style    the artist's fighter idle frame 0 (T2) — palette, proportion, rendering
  identity the job's OWN overworld.png — silhouette, colours already established

Output: 512x256 (2 frames of 256x256), matching guardian/ninja/speculator/summoner.

  python3 tools/gen_meta_job_idle.py --dry-run
  python3 tools/gen_meta_job_idle.py --quality medium
"""
import argparse, base64, importlib.util, io, os, sys
from pathlib import Path
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "_rap", Path(__file__).resolve().parent / "regen_archetype_portraits.py")
_rap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rap)

GAME_REPO = _rap.GAME_REPO
JOBS_DIR = GAME_REPO / "assets" / "sprites" / "jobs"
RAW_DIR = PROJECT / "tmp" / "meta_job_idle_gen"
STYLE_ANCHOR = JOBS_DIR / "fighter" / "idle.png"

FRAME = 256
FRAMES = 2

PREFIX = (
    "16-bit SNES-era JRPG battle sprite, full body, facing RIGHT toward the enemy. "
    "Single character centred on a fully transparent background. Clean pixel art with "
    "bold dark outlines, soft cel shading, limited palette, no anti-aliasing fuzz, no "
    "floating pixels, no duplicate limbs, no weapons doubled, no scenery, no ground "
    "shadow. Heroic readable silhouette at small size — the pose must read instantly "
    "as this class. Match the reference sprite's proportions, line weight and shading "
    "exactly: same head-to-body ratio, same outline darkness, same palette discipline. "
)

JOBS = {
    "scriptweaver": (
        "Character: a SCRIPTWEAVER — a reality-editing meta-mage. Charcoal robe with "
        "luminous phosphor-green glyphs running down the sleeves and hem, hood down, "
        "dark hair, one hand raised with green code-like symbols hovering above the palm. "
        "Reads: is editing the rules of the fight while standing in it. "
        "Palette: charcoal + phosphor green + pale skin."
    ),
    "time_mage": (
        "Character: a TIME MAGE — deep-indigo robe with brass gear motifs at the "
        "shoulders and cuffs, pale blue-white hair, a slow brass pocket-watch orbiting "
        "one hand. Serene ageless posture, weight settled, unhurried. "
        "Palette: indigo + brass + pale blue-white."
    ),
    "necromancer": (
        "Character: a NECROMANCER — tattered dark-grey shroud with bone clasps at the "
        "shoulders, lank black hair over a gaunt face, one hand extended low with a "
        "sickly green wisp curling from the fingers. Hunched, patient, unwell. "
        "Palette: grey + bone white + sick green."
    ),
    "bossbinder": (
        "Character: a BOSSBINDER — a warrior who binds monsters to their will. "
        "CRITICAL: the HEAD must be clearly readable — a distinct face with visible "
        "eyes, skin tone, and dark hair tied back in a topknot, sitting clearly ABOVE "
        "the shoulders with open transparent space around it. Do NOT let the head merge "
        "into the armour or the background. "
        "Body: crimson and black-iron armour, heavy pauldrons, a spectral chain held "
        "taut in one fist. Braced fighting stance, weight low, facing right. "
        "Clear separation between head, torso, arms and legs — every limb readable as "
        "its own shape at small size. Palette: crimson + black iron + warm skin."
    ),
    "skiptrotter": (
        "Character: a SKIPTROTTER — a traveller who skips ahead of the story. "
        "CRITICAL: keep the SILHOUETTE crisp — the coat must read as a separate shape "
        "from the torso with a clear open gap between coat-tail and legs, NOT one fused "
        "mass. A distinct readable face with visible eyes and a grin, goggles pushed up "
        "on the forehead above windswept sandy hair. "
        "Body: worn tan travelling coat with a high popped collar, mid-stride with one "
        "boot lifted and clearly separated from the other, facing right, a thin blue "
        "slipstream trailing from the raised heel. "
        "Every limb readable as its own shape at small size. Palette: tan + sky blue + "
        "sandy hair + warm skin."
    ),
}


def load_ref(path: Path, frame_only: bool = False) -> bytes:
    """First frame of a sheet, padded square, as PNG bytes."""
    img = Image.open(path).convert("RGBA")
    if frame_only and img.width > img.height:
        img = img.crop((0, 0, img.height, img.height))
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    buf = io.BytesIO()
    canvas.resize((1024, 1024), Image.NEAREST).save(buf, format="PNG")
    return buf.getvalue()


def build_strip(frame: Image.Image) -> Image.Image:
    """A 2-frame idle: base pose + a 1px settle. Matches the shipped 512x256 shape."""
    strip = Image.new("RGBA", (FRAME * FRAMES, FRAME), (0, 0, 0, 0))
    strip.paste(frame, (0, 0))
    strip.paste(frame, (FRAME, 1))
    return strip


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", default=list(JOBS))
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    unknown = [i for i in args.ids if i not in JOBS]
    if unknown:
        print(f"ERROR: unknown job(s): {unknown}", file=sys.stderr)
        return 2
    ids = [i for i in args.ids
           if args.force or not (JOBS_DIR / i / "idle.png").exists()]
    skipped = [i for i in args.ids if i not in ids]

    unit = _rap.COST[args.quality]
    print(f"{len(ids)} meta-job idle sheet(s) at {args.quality} — est ${unit*len(ids):.2f}")
    if skipped:
        print(f"skipping (already exist): {skipped}")
    if args.dry_run:
        for i in ids:
            print(f"  {i:14s} -> {(JOBS_DIR/i/'idle.png').relative_to(GAME_REPO)}  "
                  f"{FRAME*FRAMES}x{FRAME}")
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1
    if not STYLE_ANCHOR.exists():
        print(f"ERROR: style anchor missing: {STYLE_ANCHOR}", file=sys.stderr)
        return 1

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    from openai import OpenAI
    client = OpenAI()
    style_bytes = load_ref(STYLE_ANCHOR, frame_only=True)

    total, made = 0.0, []
    for job in ids:
        ident = JOBS_DIR / job / "overworld.png"
        refs = [("ref_style.png", style_bytes, "image/png")]
        if ident.exists():
            refs.append(("ref_identity.png", load_ref(ident), "image/png"))
        print(f"[{job}] gpt-image-1 {args.quality} (${unit:.3f}) "
              f"{'+identity anchor' if len(refs) > 1 else '(style only)'}")
        try:
            raw = _rap.call_gpt(client, PREFIX + JOBS[job], refs, args.quality)
        except Exception as e:
            print(f"  FAILED {job}: {e}", file=sys.stderr)
            continue
        raw.save(RAW_DIR / f"{job}_raw.png")
        frame = _rap.transparent_bg(_rap.downscale(raw, FRAME))
        out = JOBS_DIR / job / "idle.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        build_strip(frame).save(out)
        total += unit
        made.append(job)
        print(f"  -> {out.relative_to(GAME_REPO)}  {FRAME*FRAMES}x{FRAME}")

    print(f"\nGenerated {len(made)}/{len(ids)} — spent ~${total:.2f}")
    if len(made) != len(ids):
        print(f"MISSING: {[i for i in ids if i not in made]}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
