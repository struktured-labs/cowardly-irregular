#!/usr/bin/env python3
"""Per-world job sprites — the costume progression.

struktured 2026-08-06, in session:
    "also lets make sprites for the characters and their class types for each overworld"
    "your characters are supposed to xform as they shift overworlds"
    scope "all jobs" · reach "50" (both assets) · style "leaning toward B for simplicity"

B = COSTUME PROGRESSION. The same 16-bit sprite in world-appropriate dress, NOT a
rendering-era change. He floated rendering-era (A) for ENVIRONMENTS instead — parked,
bg-tiler/overworld's if it ever lands.

  14 jobs x 5 worlds x 2 assets = 140   (+5 meta idle bases, shipped in 97ad5a9c = 145)

CONVENTION, agreed across five lanes:
  jobs/<job>/overworld_<suffix>.png   nested — flat <job>_<suffix> collides with the
  jobs/<job>/idle_<suffix>.png        real cleric_artist / bard_sdxl dirs
  base overworld.png / idle.png stay untouched as the fallback

⚠️ SUFFIXES ARE THE RUNTIME VOCABULARY, enumerated from _get_current_world_suffix's
RETURN statements — NOT its body. `futuristic` appears in that body 39 times and is
returned zero times; a fighter_futuristic.png would pass every presence check and never
load. World 5 is `digital`. And `medieval` is the BASE — unsuffixed — so 5 per subject.

HEAD-LOCK: raw generation lands at 6-37 diffs; the gate demands <4 and every shipped
sheet measures 0. fix_head_lock.repair() is applied to every overworld sheet before it
is written — it finds the walk bob and re-lays frame 0's head band at that offset, so
garble goes and the rhythm survives.

  python3 tools/gen_world_job_sprites.py --jobs fighter --dry-run
  python3 tools/gen_world_job_sprites.py --jobs fighter --asset overworld
"""
import argparse, importlib.util, io, os, sys
from pathlib import Path
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
SPRITES_REPO = Path("/home/struktured/projects/cowir-sprites")


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_rap = _load("_rap", Path(__file__).resolve().parent / "regen_archetype_portraits.py")
_hl = _load("_hl", SPRITES_REPO / "tools" / "fix_head_lock.py")

GAME_REPO = _rap.GAME_REPO
JOBS_DIR = GAME_REPO / "assets" / "sprites" / "jobs"
RAW_DIR = PROJECT / "tmp" / "world_job_gen"

## Runtime vocabulary minus medieval (the base). Verified from RETURN statements.
WORLDS = ["suburban", "steampunk", "industrial", "digital", "abstract"]

## What each world does to a costume. Same sprite era, different dress.
## Each job's signature colour, held CONSTANT across every world.
##
## Measured defect, 2026-08: the first 39-sheet batch dressed every job in the
## world's palette and chromatic separation between jobs collapsed — mean pairwise
## colour distance fell 67.8 (artist base) -> 29.5 suburban / 40.6 industrial.
## Silhouettes survived (IoU 0.37 -> 0.37); it was purely colour. On screen a World-4
## party read as four interchangeable construction workers.
##
## So the world now supplies GARMENTS AND MATERIALS ONLY, and the job keeps its hue.
## Hand-authored rather than sampled: extraction kept returning skin tone as the
## dominant hue for 8 of 14 jobs. The LIST is still derived from JOB_CORE, and
## _check_signature_coverage() fails loudly if a job ever lacks an entry.
JOB_SIGNATURE = {
    "fighter":      "crimson red with steel grey",
    "cleric":       "white and silver with sky blue",
    "mage":         "deep purple with emerald green",
    "rogue":        "dark crimson with black-violet",
    "bard":         "warm orange with teal",
    "guardian":     "royal blue with gold",
    "ninja":        "black-purple with a red sash",
    "summoner":     "violet and white with gold",
    "speculator":   "charcoal black with crisp white",
    "scriptweaver": "charcoal with phosphor green",
    "time_mage":    "deep indigo with brass",
    "necromancer":  "ash grey with sickly green",
    "bossbinder":   "crimson with black iron",
    "skiptrotter":  "tan with sky blue",
}


def _check_signature_coverage():
    """A job with no signature would silently inherit the world palette again."""
    missing = sorted(set(JOB_CORE) - set(JOB_SIGNATURE))
    if missing:
        raise SystemExit(f"ERROR: no JOB_SIGNATURE for {missing} — they would lose their identity colour")


WORLD_DRESS = {
    "suburban":   ("late-20th-century SUBURBAN streetwear — letterman jacket, denim, "
                   "sneakers, backpack straps. Mall-and-cul-de-sac ordinary."),
    "steampunk":  ("VICTORIAN STEAMPUNK dress — brass goggles, layered leather coat with "
                   "buckles, riveted pauldron, oil-stained gloves."),
    "industrial": ("heavy INDUSTRIAL workwear — hard hat or welding visor, hi-visibility "
                   "banding, thick canvas overalls, steel-toed boots."),
    "digital":    ("DIGITAL/CYBER dress — a slim visor with a thin light bar, panelled "
                   "bodysuit with glowing seams, hard-edged geometric plating."),
    # The first abstract pilot read as a MISSING ASSET — a grey untextured figure. Cause was
    # "flat unshaded, no texture" landing on a sprite that had also lost its colour to the
    # old palette clause. With JOB_SIGNATURE holding the hue, minimalism can read as a
    # deliberate style instead of unfinished art, but only if it keeps a crisp outline and a
    # few value steps: truly flat at 256px downscales to a silhouette with no interior form.
    "abstract":   ("MINIMALIST ABSTRACT dress — the costume reduced to its essential "
                   "geometric shapes, bold flat colour blocks with only two or three value "
                   "steps, no fabric texture and no small ornament, but a CRISP DARK "
                   "OUTLINE and clearly separated forms so it reads as a deliberate "
                   "graphic style rather than an unfinished sprite. The silhouette must "
                   "remain unmistakably this class, and the figure must never read as a "
                   "flat grey or untextured blank. "),
}

## Per-job identity that must survive every costume change.
JOB_CORE = {
    "fighter":      "a broad-shouldered melee warrior with a sword at the hip",
    "cleric":       "a gentle robed healer with a staff and a soft aura",
    "mage":         "a slight hooded spellcaster with an arcane focus",
    "rogue":        "a lean hooded scout with daggers and light footing",
    "bard":         "a jaunty performer with a stringed instrument slung across the back",
    "guardian":     "a heavily armoured shield-bearer, immovable stance",
    "ninja":        "a masked shadow-runner, face wrapped, only the eyes visible",
    "summoner":     "a dreaming caster in flowing robes with a floating rune mote",
    "speculator":   "a sly waistcoated dealer with a gold watch chain",
    "scriptweaver": "a meta-mage in a coat hung with luminous green glyphs",
    "time_mage":    "a serene caster with a brass pocket-watch orbiting one hand",
    "necromancer":  "a gaunt figure in a tattered shroud with a sickly green wisp",
    "bossbinder":   "a braced warrior in crimson plate holding a taut spectral chain",
    "skiptrotter":  "a grinning traveller in a long coat with goggles pushed up",
}

GRID_PROMPT = """Generate a 4-direction walk-cycle sprite sheet for {core}, dressed in {dress}

⚠️ THE SINGLE MOST IMPORTANT REQUIREMENT — SCALE:
Each cell shows the character's ENTIRE BODY, HEAD TO FEET, standing at FULL LENGTH.
This is a tiny top-down overworld walking sprite, NOT a portrait and NOT a bust.
The whole figure — head, torso, arms, legs AND FEET — must fit inside its cell with
clear empty margin above the head and below the feet. The head should be roughly
ONE THIRD of the figure's height (chibi proportions), not the whole frame.
If you can only see the character's head and shoulders, the scale is WRONG.

Output format — match this EXACTLY:
  - 1024x1024 canvas, fully transparent background, a 4-row by 4-column GRID of 256x256 cells
  - The full standing figure occupies about 70% of each cell's HEIGHT, centred, feet near
    the cell's lower edge and empty space above the head
  - Top-down 3/4 JRPG overworld view, the classic 16-bit RPG camera angle

Row layout (top to bottom):
  Row 0: walking SOUTH — facing the viewer, face visible
  Row 1: walking WEST  — side profile facing LEFT
  Row 2: walking EAST  — side profile facing RIGHT
  Row 3: walking NORTH — BACK VIEW. Only the back of the head. NO eyes, NO face.

Column layout (left to right) — a standard 4-frame walk cycle:
  Col 0: standing, legs together    Col 1: right foot forward
  Col 2: standing, legs together    Col 3: left foot forward

The head and torso must be IDENTICAL across all four frames of a row; ONLY THE LEGS
move between columns. The legs must be clearly visible and clearly different between
columns — that difference is the entire animation.

Use the SECOND reference image for SCALE AND FRAMING (how big the figure sits in its
cell) and the FIRST only for the character's colours and equipment. Clean pixel art,
bold dark outlines, limited palette, no anti-aliasing fuzz, no floating pixels."""

BUST_PROMPT = """16-bit SNES-era JRPG battle sprite, full body, facing RIGHT toward the enemy.
{core}, dressed in {dress}

Single character centred on a fully transparent background. Clean pixel art with bold
dark outlines, soft cel shading, limited palette. No floating pixels, no duplicate limbs,
no scenery, no ground shadow. A distinct readable head with a visible face, clearly
separated from the body. Every limb readable as its own shape at small size.
Match the reference sprite's proportions and line weight exactly, and keep the class
silhouette unmistakable through the costume change."""


def ref_bytes(path: Path, first_frame: bool = False) -> bytes:
    img = Image.open(path).convert("RGBA")
    if first_frame and img.width > img.height:
        img = img.crop((0, 0, img.height, img.height))
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    buf = io.BytesIO()
    canvas.resize((1024, 1024), Image.NEAREST).save(buf, format="PNG")
    return buf.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", nargs="+", default=["fighter"])
    ap.add_argument("--worlds", nargs="+", default=WORLDS)
    ap.add_argument("--asset", choices=["overworld", "idle", "both"], default="overworld")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    bad = [j for j in args.jobs if j not in JOB_CORE] + [w for w in args.worlds if w not in WORLD_DRESS]
    if bad:
        print(f"ERROR: unknown job/world: {bad}", file=sys.stderr)
        return 2

    _check_signature_coverage()
    assets = ["overworld", "idle"] if args.asset == "both" else [args.asset]
    todo = []
    for job in args.jobs:
        for world in args.worlds:
            for asset in assets:
                out = JOBS_DIR / job / f"{asset}_{world}.png"
                if args.force or not out.exists():
                    todo.append((job, world, asset, out))

    unit = _rap.COST[args.quality]
    print(f"{len(todo)} sheet(s) at {args.quality} — est ${unit*len(todo):.2f}")
    if args.dry_run:
        for job, world, asset, out in todo:
            print(f"  {job:13s} {world:11s} {asset:9s} -> {out.relative_to(GAME_REPO)}")
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    from openai import OpenAI
    client = OpenAI()

    total, made, locked = 0.0, [], []
    for job, world, asset, out in todo:
        base_ow = JOBS_DIR / job / "overworld.png"
        base_idle = JOBS_DIR / job / "idle.png"
        refs = []
        if base_idle.exists():
            refs.append(("ref_identity.png", ref_bytes(base_idle, first_frame=True), "image/png"))
        if asset == "overworld" and base_ow.exists():
            refs.append(("ref_format.png", ref_bytes(base_ow), "image/png"))
        if not refs:
            print(f"  SKIP {job}/{world}/{asset}: no reference art", file=sys.stderr)
            continue

        tmpl = GRID_PROMPT if asset == "overworld" else BUST_PROMPT
        dress = (WORLD_DRESS[world] + " CRITICAL — KEEP THIS CHARACTER'S IDENTITY COLOUR: the "
                 "garments must be rendered in " + JOB_SIGNATURE[job] + ". The world changes the "
                 "CUT and MATERIAL of the clothing, never its hue. This character must remain "
                 "instantly distinguishable from the rest of the party by colour alone.")
        prompt = tmpl.format(core=JOB_CORE[job], dress=dress)
        print(f"[{job}/{world}/{asset}] gpt-image-1 {args.quality} (${unit:.3f}) "
              f"{len(refs)} ref(s)")
        try:
            raw = _rap.call_gpt(client, prompt, refs, args.quality)
        except Exception as e:
            print(f"  FAILED {job}/{world}/{asset}: {e}", file=sys.stderr)
            continue
        raw.save(RAW_DIR / f"{job}_{world}_{asset}_raw.png")

        if asset == "overworld":
            sheet = _rap.transparent_bg(_rap.downscale(raw, 128))
            sheet.save(out)
            # Raw generation lands at 6-37 diffs; the gate demands <4.
            n = head_lock_to_gate(out)
            locked.append((f"{job}/{world}", n))
            print(f"  head-lock: locked {n} frame(s) to the gate's own band")
        else:
            frame = _rap.transparent_bg(_rap.downscale(raw, 256))
            strip = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
            strip.paste(frame, (0, 0)); strip.paste(frame, (256, 1))
            strip.save(out)
            if base_idle.exists():
                f, bot = normalize_idle_to_base(out, base_idle)
                if f:
                    print(f"  normalized: fill {f:.1%}, footing {bot} (from the job's own base)")

        total += unit
        made.append(f"{job}/{world}/{asset}")
        print(f"  -> {out.relative_to(GAME_REPO)}")

    print(f"\nGenerated {len(made)}/{len(todo)} — spent ~${total:.2f}")
    if locked:
        print(f"head-lock repairs: {locked}")
    if len(made) != len(todo):
        return 1
    return 0




## ---------------------------------------------------------------------------
## Head-lock that matches THE SHIPPED GATE, not the older repair tool.
##
## fix_head_lock.repair() anchors on row_sprite_top() — the largest contiguous
## opaque band — and locks CELL*0.65 = 20 rows from there. The gate
## (test_overworld_head_lock_regression) anchors on _frame_bbox_y's FIRST opaque
## row and locks 0.65 * (bbox height). Those are different regions, so the tool
## can report "repaired" and leave the rows the gate actually reads untouched.
## Measured on the fighter pilot: 12 frames "repaired" each, gate metric still
## 239-423 diffs against a threshold of 4.
##
## This locks exactly what the gate reads: frame 0's band, copied to frames 1-3
## at the same coordinates, legs below untouched.
def head_lock_to_gate(path: Path) -> int:
    im = Image.open(path).convert("RGBA")
    if im.size != (128, 128):
        return -1
    px = im.load()
    fixed = 0
    for row in range(4):
        ys = [y for y in range(32)
              if any(px[x, row * 32 + y][3] > 12 for x in range(32))]
        if not ys:
            continue
        top, bot = min(ys), max(ys)
        lock_end = min(32, top + max(1, int((bot - top + 1) * 0.65)))
        for col in (1, 2, 3):
            for y in range(top, lock_end):
                for x in range(32):
                    px[x + col * 32, row * 32 + y] = px[x, row * 32 + y]
            fixed += 1
    im.save(path)
    return fixed


## ---------------------------------------------------------------------------
## Post-process an idle strip to the ARTIST'S OWN measurements.
##
## Raw generation fills 56-77% of frame height; the artist's fighter fills 37.5%.
## BattleScene scales uniformly by frame height, so an unnormalised sprite towers
## over the party. And after rescaling, the figure sits low in its frame unless
## the footing is aligned too — measured on the pilot: bbox bottom 246 vs 162.
##
## Both targets are READ FROM THE JOB'S OWN BASE idle.png, never hardcoded, so a
## job whose artist art sits differently still matches itself.
def normalize_idle_to_base(strip: Path, base: Path) -> tuple:
    import importlib.util as _il
    s = _il.spec_from_file_location("_nz", SPRITES_REPO / "tools" / "normalize_job_scale.py")
    nz = _il.module_from_spec(s); s.loader.exec_module(nz)

    b = Image.open(base).convert("RGBA").crop((0, 0, 256, 256))
    bb = b.split()[3].getbbox()
    if bb is None:
        return (None, None)
    target_fill = (bb[3] - bb[1]) / 256.0
    target_bottom = bb[3]

    nz.normalize_strip_scale(strip, target_fill, backup=False)

    im = Image.open(strip).convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for fi in range(im.width // 256):
        fr = im.crop((fi * 256, 0, fi * 256 + 256, 256))
        fb = fr.split()[3].getbbox()
        if fb is None:
            out.paste(fr, (fi * 256, 0)); continue
        shifted = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        shifted.paste(fr, (0, target_bottom - fb[3]))
        out.alpha_composite(shifted, (fi * 256, 0))
    out.save(strip)
    return (target_fill, target_bottom)


if __name__ == "__main__":
    sys.exit(main())
