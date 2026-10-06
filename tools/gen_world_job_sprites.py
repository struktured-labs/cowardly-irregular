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

VICTORY (struktured 2026-10-05: "victory animations arent replaced in suburban / alternate
worlds either, still ones from medeivail"). idle was the only battle anim with a world
sheet, so in W2+ the costume snapped back to medieval the moment victory played.
  --asset victory  ->  jobs/<job>/victory_<suffix>.png, SAME frame count and width as the
  artist's victory.png (kept untouched as the fallback), so frame_durations_ms still applies.
ONE call per job x world, not one per frame: separate calls redraw the costume differently
each time and an 11-frame flourish at 110ms flickers. The call is handed the job's DISTINCT
poses as a grid (frames clustered by silhouette, IoU >= 0.85) and the shipped
idle_<suffix> frame as the costume, so victory matches idle in the same world. Each base
frame then takes its pose's cell, normalised to THAT frame's height, footing and centre, so
the artist's timing and travel survive. Needs idle_<suffix>.png first.
"""
import argparse, importlib.util, io, os, sys
from pathlib import Path
from PIL import Image
import sys as _sys, pathlib as _pl
_sys.path.insert(0, str(_pl.Path(__file__).resolve().parent.parent))
from tools.artist_guard import assert_writable  # refuses a write over artist pixels


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


## Every output filename's suffix must be one the RUNTIME can actually ask for.
##
## The trap is `futuristic`, and the durable form is a RELATIONSHIP, not a count.
##
## ⚠️ I first wrote "there are THREE vocabularies here, not two" and it was stale within the
## hour — cowir-cutscenes found a fourth inside SoundManager itself (`_area_wav_cache`, an
## in-memory Dictionary key, spelled `futuristic` and CORRECT). A note that names a COUNT is
## a hand-list wearing a rule's clothes, and it goes wrong in both directions like any other.
##
## THE RULE: `futuristic` is wrong ONLY when a value that names a MAP or a MONSTER reaches a
## consumer expecting a WORLD SUFFIX. Every other spelling of it is correct — map-id-to-map-id
## cannot misfire, and audio's own procedural cache legitimately says `futuristic` one line
## after its manifest lookup says `digital`.
##
## For THIS check the consumer is the SPRITE suffix list, HybridSpriteLoader.WORLD_SUFFIXES —
## not audio's, since the loader stopped consulting SoundManager when the resolver unified.
## The two agree today, but they are separate literals: agreement is a fact to re-check, not
## a guarantee.
## A batch written as idle_futuristic.png would generate cleanly, import cleanly, sit on
## disk forever and never be requested once — and nothing downstream reports it, because
## the lookup just falls back to base art and the game looks right.
##
## Checked BEFORE the API spends: the failure costs real money per sheet and is invisible
## afterwards. This is an INDEPENDENT literal, deliberately not derived from WORLD_DRESS —
## the whole point is to disagree with WORLD_DRESS when someone adds a world under a name
## the runtime never returns. Deriving it from the thing it checks would make it vacuous.
_RUNTIME_SUFFIXES = {"medieval", "suburban", "steampunk", "industrial", "digital", "abstract"}


def _check_output_names(worlds):
    unrequestable = sorted(w for w in worlds if w not in _RUNTIME_SUFFIXES)
    if unrequestable:
        raise SystemExit(
            f"ERROR: {unrequestable} is not a suffix the runtime ever asks for. "
            f"Valid: {sorted(_RUNTIME_SUFFIXES)}. Note world 5 is 'digital', NOT 'futuristic' "
            f"— its map ids say futuristic but the resolver returns digital, so the art would "
            f"generate, import, and never once be requested.")


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
    # "glowing seams" invited BLOOM, and bloom fills the frame: 3 of 4 digital rolls on
    # 2026-09-11 came back with a lit backdrop that transparent_bg could not key (it only
    # clears R,G,B >= 240, and a tinted glow sits under that). Light is now ON the garment.
    "digital":    ("DIGITAL/CYBER dress — a slim visor with a thin light bar, panelled "
                   "bodysuit whose seams are lit as CRISP PIXEL LINES on the garment "
                   "itself, hard-edged geometric plating. NO glow, bloom, halo or light "
                   "spill beyond the character's own outline — the area around the figure "
                   "is EMPTY and fully transparent."),
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

BUST_PROMPT = """16-bit SNES-era JRPG battle sprite, full body, facing LEFT (the enemy line is to the LEFT). ⚠️ LEFT is the shipped convention: BattleScene:980 gives 256px sheets flip_h=false, so a right-facing sprite renders backwards next to the artist's party.
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
    ap.add_argument("--asset", choices=["overworld", "idle", "victory", "both"], default="overworld")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--from-raw", action="store_true",
                    help="victory only: rebuild sheets from tmp/world_job_gen/*_victory_raw.png, no API call")
    args = ap.parse_args()

    bad = [j for j in args.jobs if j not in JOB_CORE] + [w for w in args.worlds if w not in WORLD_DRESS]
    if bad:
        print(f"ERROR: unknown job/world: {bad}", file=sys.stderr)
        return 2

    _check_signature_coverage()
    _check_output_names(args.worlds)
    assets = ["overworld", "idle"] if args.asset == "both" else [args.asset]
    todo = []
    for job in args.jobs:
        for world in args.worlds:
            for asset in assets:
                out = JOBS_DIR / job / f"{asset}_{world}.png"
                if args.force or not out.exists():
                    todo.append((job, world, asset, out))

    if args.from_raw:
        if args.asset != "victory":
            print("ERROR: --from-raw rebuilds victory sheets only", file=sys.stderr)
            return 2
        rebuilt = 0
        for job in args.jobs:
            for world in args.worlds:
                rawp = RAW_DIR / f"{job}_{world}_victory_raw.png"
                plan = victory_plan(job, world)
                if not rawp.exists() or "skip" in plan:
                    continue
                strip, why = assemble_victory(Image.open(rawp), plan)
                out = JOBS_DIR / job / f"victory_{world}.png"
                if strip is None:
                    print(f"  REFUSED {job}/{world}: {why}", file=sys.stderr)
                    continue
                assert_writable(out)
                strip.save(out)
                rebuilt += 1
                print(f"  rebuilt {out.relative_to(GAME_REPO)} from its raw")
        print(f"rebuilt {rebuilt} sheet(s), spent $0")
        return 0
    unit = _rap.COST[args.quality]
    print(f"{len(todo)} sheet(s) at {args.quality} — est ${unit*len(todo):.2f}")
    if args.dry_run:
        for job, world, asset, out in todo:
            note = ""
            if asset == "victory":
                plan = victory_plan(job, world)
                note = plan["skip"] if "skip" in plan else (
                    f"{len(plan['keys'])} pose(s), {plan['cols']}x{plan['rows']} grid, {len(plan['frames'])} frames")
            print(f"  {job:13s} {world:11s} {asset:9s} -> {out.relative_to(GAME_REPO)}  {note}")
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    from openai import OpenAI
    client = OpenAI()

    total, made, locked, refused = 0.0, [], [], []
    for job, world, asset, out in todo:
        base_ow = JOBS_DIR / job / "overworld.png"
        base_idle = JOBS_DIR / job / "idle.png"
        if asset == "victory":
            cost, ok = _victory(client, job, world, out, args.quality)
            total += cost  # a refused roll was still paid for
            (made if ok else refused).append(f"{job}/{world}/{asset}")
            continue
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
        assert_writable(RAW_DIR / f"{job}_{world}_{asset}_raw.png")
        raw.save(RAW_DIR / f"{job}_{world}_{asset}_raw.png")

        if asset == "overworld":
            sheet = _rap.transparent_bg(_rap.downscale(raw, 128))
            specks = _despeckle(sheet)
            if specks:
                print(f"  despeckled {specks} stray blob(s) <= 4px")
            bad = _backdrop_residue(sheet)
            if bad:
                print(f"  REFUSED {job}/{world}: {bad} -- re-roll this one", file=sys.stderr)
                refused.append(f"{job}/{world}")
                continue
            assert_writable(out)
            sheet.save(out)
            # Raw generation lands at 6-37 diffs; the gate demands <4.
            n = head_lock_to_gate(out)
            locked.append((f"{job}/{world}", n))
            print(f"  head-lock: locked {n} frame(s) to the gate's own band")
        else:
            frame = _rap.transparent_bg(_rap.downscale(raw, 256))
            strip = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
            strip.paste(frame, (0, 0)); strip.paste(frame, (256, 1))
            assert_writable(out)
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
    if refused:
        print(f"REFUSED (reason printed with each; re-roll these): {refused}", file=sys.stderr)
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
    assert_writable(path)
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
## transparent_bg keys only pixels whose R, G AND B are all >= 240. A dithered or slightly tinted
## white backdrop sits just under that and SURVIVES as speckle -- and on a 4x4 grid the speckle
## BRIDGES frames, so the usual small-blob cleanup cannot split them without eating sprite content.
##
## Measured 2026-09-11: 9 of 20 rolls in one session carried residue. One of them,
## ninja/overworld_industrial.png, SHIPPED in v3.33.298 and v3.33.299 -- 844 opaque blobs, 754 of
## them <= 4px, rendering as a speckled haze over the terrain. Nothing checked, because the
## OpaqueBackdrop refusal I added to regen_masterite_portraits.py an hour earlier was never added
## here. Harden one writer, miss the rest.
##
## Refuse rather than clean: a re-roll costs ~$0.04 and a cleanup on a bridged grid risks the
## subject, which is this lane's 2026-09-09 defect.
## A few isolated sub-5px blobs survive transparent_bg on most rolls -- single pixels of near-white
## backdrop that sit just under the 240 threshold. At a 32px frame they render as visible dots on
## the terrain. Safe to remove ONLY because they are isolated: the ninja/industrial disaster had
## 754 of them BRIDGING frames into one blob, which is why that sheet was re-rolled rather than
## cleaned. Bounded at 4px so it can never reach sprite content.
def _despeckle(sheet: Image.Image, max_blob: int = 4) -> int:
    from collections import deque
    px = sheet.load()
    W, H = sheet.size
    seen = [[False] * H for _ in range(W)]
    removed = 0
    for sx in range(W):
        for sy in range(H):
            if seen[sx][sy] or px[sx, sy][3] <= 10:
                continue
            blob = []
            q = deque([(sx, sy)])
            seen[sx][sy] = True
            while q:
                x, y = q.popleft()
                blob.append((x, y))
                if len(blob) > max_blob:
                    break
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < W and 0 <= ny < H and not seen[nx][ny] and px[nx, ny][3] > 10:
                        seen[nx][ny] = True
                        q.append((nx, ny))
            if len(blob) <= max_blob:
                for x, y in blob:
                    px[x, y] = (0, 0, 0, 0)
                removed += 1
    return removed


def _backdrop_residue(sheet: Image.Image) -> str:
    im = sheet.convert("RGBA")
    W, H = im.size
    a = im.getchannel("A")
    corners = [a.getpixel(p) for p in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]]
    if max(corners) > 10:
        return "corner alphas %s -- the backdrop was not keyed out" % corners
    opaque = sum(1 for v in a.getdata() if v > 10) / float(W * H)
    # shipped starter variants measure 0.33-0.49; 0.70 leaves ~1.4x headroom over the worst
    if opaque > 0.70:
        return "%.0f%% of the sheet is opaque -- backdrop residue, not a sprite" % (100 * opaque)
    return ""


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
    assert_writable(strip)
    out.save(strip)
    return (target_fill, target_bottom)


## ---------------------------------------------------------------------------
## Victory: one call per job x world, the distinct poses as a grid, the world idle as costume.

VICTORY_POSE_IOU = 0.85
FRAME = 256

VICTORY_PROMPT = """Image 1 is a reference sheet: a {cols}x{rows} grid of {n} POSES from a 16-bit SNES-era JRPG
battle sprite's victory celebration, read left-to-right, top-to-bottom. {empty}
Image 2 is the SAME character dressed for this world: {dress}

Redraw image 1 cell for cell. The SAME grid, the SAME pose in each cell, at the SAME position,
size and facing within its cell (the character faces LEFT), but wearing EXACTLY the costume of
image 2 — its garments, materials and colours ({signature}). The character is {core}.

Rules:
  - 1024x1024 canvas, a FULLY TRANSPARENT background, the same {cols}x{rows} grid of equal square cells.
    Draw NO grid lines, borders, gutters, labels or text.
  - One full-body figure per cell, head to feet, at the SAME SIZE as in image 1 — about two thirds of its cell's
    height — with clear empty space above the head and below the feet. No figure may touch or cross its cell's
    edges; a figure drawn too large is cut off and wasted.
  - The costume is IDENTICAL in every cell; only the pose changes between cells.
  - Clean pixel art, bold dark outlines, limited palette. No scenery, no ground shadow, and no glow
    or light spill beyond the character's own outline."""


def _frames(path: Path) -> list:
    im = Image.open(path).convert("RGBA")
    return [im.crop((i * FRAME, 0, i * FRAME + FRAME, FRAME)) for i in range(im.width // FRAME)]


def _mask(fr: Image.Image) -> set:
    return {i for i, v in enumerate(fr.getchannel("A").getdata()) if v >= 128}


def victory_key_poses(frames: list) -> tuple:
    """Greedy silhouette clusters: (key frame indices, the key each frame takes). Deterministic, in frame order."""
    masks = [_mask(f) for f in frames]
    keys, assign = [], []
    for i, m in enumerate(masks):
        hit = next((k for k in keys if len(m & masks[k]) / max(1, len(m | masks[k])) >= VICTORY_POSE_IOU), None)
        if hit is None:
            keys.append(i)
            hit = i
        assign.append(hit)
    return keys, assign


def _grid_shape(n: int) -> tuple:
    cols = 1
    while cols * cols < n:
        cols += 1
    rows = (n + cols - 1) // cols
    return cols, max(rows, cols)  # always square, so every cell is square in the 1024 canvas


## The reference draws each pose at this share of its cell. The AI enlarges what it is shown, and drawn at
## full cell size the first batch's rogue and bard poses ran off their cells' bottom edges; assembly rescales
## to the artist's size anyway, so the reference's scale costs nothing.
POSE_IN_CELL = 0.7


def _pose_grid(frames: list, keys: list, cols: int) -> bytes:
    """EVERY cell filled: poses repeat to fill the grid. Given a 2x2 with two empty cells the AI ignored the
    grid and drew two large figures across the whole canvas (bard, first batch)."""
    cell = 1024 // cols
    canvas = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    side = round(cell * POSE_IN_CELL)
    for slot in range(cols * cols):
        fr = frames[keys[slot % len(keys)]].resize((side, side), Image.NEAREST)
        canvas.alpha_composite(fr, ((slot % cols) * cell + (cell - side) // 2, (slot // cols) * cell + (cell - side) // 2))
    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def _key_backdrop(cell: Image.Image, tol: float = 40.0) -> Image.Image:
    """Clear the backdrop by FLOOD from the cell's border through anything near its colour.

    transparent_bg keys R,G,B >= 240 only. The pilot fighter's backdrop was an off-white whose noise dips
    just under that on one channel, so a sparse speckle survived across every cell: invisible, but it
    made the figure's box span the whole cell (221 of 256 rows) and threw both the scale and the footing.
    Flooding from the border reaches only backdrop, so an enclosed white (an eye, a highlight) survives."""
    from collections import deque
    im = cell.convert("RGBA")
    px = im.load()
    W, H = im.size
    border = [px[x, y] for x in range(W) for y in (0, H - 1)] + [px[x, y] for y in range(H) for x in (0, W - 1)]
    bg = tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))
    near = lambda c: c[3] < 16 or ((c[0] - bg[0]) ** 2 + (c[1] - bg[1]) ** 2 + (c[2] - bg[2]) ** 2) ** 0.5 <= tol
    seen = bytearray(W * H)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        if seen[y * W + x]:
            continue
        seen[y * W + x] = 1
        if not near(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < W and 0 <= ny < H and not seen[ny * W + nx]:
                q.append((nx, ny))
    return im


def _main_figure(cell: Image.Image, reach: int = 6) -> tuple:
    """(the cell's figure alone, whether it touches the cell's top or bottom edge).

    The AI does not respect cell walls: on the first batch rogue/suburban drew poses straddling two cells, so
    the crops held a hood in one frame and floating feet in the next, and rogue/abstract filled all 9 cells of
    a 7-pose grid, its feet spilling into the cells below. Keeps the largest 8-connected blob at alpha >= 128
    plus any blob within `reach` px of it (a blade or a slash arc keyed loose from the hand); clears the rest."""
    from collections import deque
    im = cell.convert("RGBA")
    px = im.load()
    W, H = im.size
    label = [[-1] * W for _ in range(H)]
    blobs = []
    for sy in range(H):
        for sx in range(W):
            if label[sy][sx] != -1 or px[sx, sy][3] < 128:
                continue
            idx = len(blobs)
            pts = []
            q = deque([(sx, sy)])
            label[sy][sx] = idx
            while q:
                x, y = q.popleft()
                pts.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < W and 0 <= ny < H and label[ny][nx] == -1 and px[nx, ny][3] >= 128:
                            label[ny][nx] = idx
                            q.append((nx, ny))
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            blobs.append((len(pts), (min(xs), min(ys), max(xs), max(ys))))
    if not blobs:
        return im, False
    main = max(range(len(blobs)), key=lambda i: blobs[i][0])
    mb = blobs[main][1]
    keep = set()
    for i, (_, b) in enumerate(blobs):
        if i == main or (b[0] <= mb[2] + reach and b[2] >= mb[0] - reach and b[1] <= mb[3] + reach and b[3] >= mb[1] - reach):
            keep.add(i)
    for y in range(H):
        for x in range(W):
            lab = label[y][x]
            # faint fringe (alpha < 128) is kept only beside a kept pixel, so the outline's soft edge survives
            if lab == -1:
                if px[x, y][3] > 0 and not any(0 <= x + dx < W and 0 <= y + dy < H and label[y + dy][x + dx] in keep
                                              for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                    px[x, y] = (0, 0, 0, 0)
            elif lab not in keep:
                px[x, y] = (0, 0, 0, 0)
    top = min(blobs[i][1][1] for i in keep)
    bottom = max(blobs[i][1][3] for i in keep)
    return im, top <= 0 or bottom >= H - 1


def _has_real_alpha(raw: Image.Image) -> bool:
    """The model returned real transparency: its border is clear. Then nothing is keyed — keying by colour
    against the RGB hidden under clear pixels ate a dark rogue through his own outlines, and the white key
    would delete every highlight brighter than 240."""
    a = raw.convert("RGBA").getchannel("A").resize((256, 256), Image.BOX)
    edge = [a.getpixel((x, y)) for x in range(256) for y in (0, 255)] + [a.getpixel((x, y)) for y in range(256) for x in (0, 255)]
    return sum(1 for v in edge if v < 16) >= 0.9 * len(edge)


def _cells(raw: Image.Image, n: int, cols: int) -> list:
    clear = _has_real_alpha(raw)
    raw = raw.convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    cell = 1024 // cols
    out = []
    for slot in range(n):
        c = raw.crop(((slot % cols) * cell, (slot // cols) * cell, (slot % cols) * cell + cell, (slot // cols) * cell + cell))
        out.append(_rap.downscale(c, FRAME) if clear else _rap.transparent_bg(_rap.downscale(_key_backdrop(c), FRAME)))
    return out


def _bbox(img: Image.Image):
    """The figure's box at alpha >= 128. A raw alpha getbbox() counts every faint resample halo and keying
    remnant, so one near-invisible pixel below the feet moved the pilot fighter's footing by 15px."""
    return img.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()


def _median(xs: list) -> float:
    xs = sorted(xs)
    return xs[len(xs) // 2] if len(xs) % 2 else (xs[len(xs) // 2 - 1] + xs[len(xs) // 2]) / 2.0


def strip_scale(cells: list, bases: list) -> float:
    """ONE scale for the whole strip, so the dressed body never swells or shrinks between frames.

    Per-frame fitting to each base bbox was the pilot's first defect: the fighter's box grows when his
    sword goes up and the bard's when her notes rise. Taken from the FIRST pose, the frame the player
    sees straight after idle, so the idle->victory cut does not pop (the median undersized the pilot
    fighter by ~10% against his world idle); the median stands in only if that pose is an outlier."""
    ratios = []
    for c, b in zip(cells, bases):
        cb, bb = _bbox(c), _bbox(b)
        ratios.append((bb[3] - bb[1]) / float(cb[3] - cb[1]))
    med = _median(ratios)
    return ratios[0] if abs(ratios[0] - med) <= 0.25 * med else med


def _place(cell: Image.Image, k: float, base: Image.Image) -> Image.Image:
    """The pose at scale k, centred where the AI put it, its FEET on this base frame's footing.

    Footing is per frame: the pilot fighter's later poses sat 17px high in their cells and the held
    final frame floated; a real jump in the artist's frames still lifts, because his footing does."""
    big = cell.resize((max(1, round(FRAME * k)), max(1, round(FRAME * k))), Image.LANCZOS)
    cb = _bbox(big)
    bb = _bbox(base)
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if cb is None or bb is None:
        return out
    x = round(FRAME / 2.0 - big.width / 2.0)
    # paste with the image as its own mask: clips at the frame edge where alpha_composite would refuse
    out.paste(big, (x, bb[3] - cb[3]), big)
    return out


def _backdrop_is_plain(raw: Image.Image) -> str:
    """"" when the raw stands on plain near-white; else why not. The keying assumes white: rogue/digital and
    rogue/abstract came back on a painted brown gradient, the flood ate into the figures and the strips
    shipped as fragments that every later check measured as a small, oddly-footed sprite."""
    rgba = raw.convert("RGBA").resize((256, 256), Image.BOX)
    edge = [(x, y) for x in range(256) for y in (0, 1, 254, 255)] + [(x, y) for y in range(256) for x in (0, 1, 254, 255)]
    if sum(1 for p in edge if rgba.getpixel(p)[3] < 16) >= 0.9 * len(edge):
        return ""  # a real transparent backdrop
    im = rgba.convert("RGB")
    border = [im.getpixel(p) for p in edge]
    med = tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))
    if min(med) < 225:
        return f"the backdrop is {med}, not plain white"
    near = sum(1 for c in border if sum((c[i] - med[i]) ** 2 for i in range(3)) ** 0.5 <= 40) / float(len(border))
    if near < 0.9:
        return f"only {near:.0%} of the border is backdrop -- something reaches the canvas edge"
    return ""


def assemble_victory(raw: Image.Image, plan: dict) -> tuple:
    """(strip, "") or (None, why it was refused). No API call: also rebuilds a sheet from a saved raw."""
    why = _backdrop_is_plain(raw)
    if why:
        return None, why
    keys, cols = plan["keys"], plan["cols"]
    cells = []
    for slot, c in enumerate(_cells(raw, len(keys), cols)):
        fig, cut = _main_figure(c)
        if cut:
            return None, f"pose {slot} runs off its cell's top or bottom edge -- the AI drew it across two cells"
        cells.append(fig)
    for slot, c in enumerate(cells):
        bb = _bbox(c)
        if bb is None or (bb[3] - bb[1]) < FRAME * 0.2:
            return None, f"pose {slot} came back empty or tiny"
        why = _backdrop_residue(c)
        if why:
            return None, f"pose {slot}: {why}"
    k = strip_scale(cells, [plan["frames"][kk] for kk in keys])
    slot_of = {kk: slot for slot, kk in enumerate(keys)}
    strip = Image.new("RGBA", (FRAME * len(plan["frames"]), FRAME), (0, 0, 0, 0))
    for i, base_fr in enumerate(plan["frames"]):
        strip.alpha_composite(_place(cells[slot_of[plan["assign"][i]]], k, base_fr), (i * FRAME, 0))
    base_w = Image.open(plan["base"]).width
    if strip.width != base_w:
        return None, f"{strip.width}px strip for a {base_w}px base"
    return strip, ""


def victory_plan(job: str, world: str) -> dict:
    base = JOBS_DIR / job / "victory.png"
    costume = JOBS_DIR / job / f"idle_{world}.png"
    if not base.exists():
        return {"skip": f"no artist victory.png for {job}"}
    if not costume.exists():
        return {"skip": f"no idle_{world}.png to take the costume from — dress idle first"}
    frames = _frames(base)
    keys, assign = victory_key_poses(frames)
    cols, rows = _grid_shape(len(keys))
    return {"base": base, "costume": costume, "frames": frames, "keys": keys, "assign": assign, "cols": cols, "rows": rows}


def _victory(client, job: str, world: str, out: Path, quality: str) -> tuple:
    plan = victory_plan(job, world)
    if "skip" in plan:
        print(f"  SKIP {job}/{world}/victory: {plan['skip']}", file=sys.stderr)
        return 0.0, False
    keys, cols, rows = plan["keys"], plan["cols"], plan["rows"]
    empty = (f"Poses repeat to fill the grid: draw EVERY cell, each one with its own reference pose."
             if cols * rows > len(keys) else "")
    dress = WORLD_DRESS[world] + " Keep this character's identity colour: " + JOB_SIGNATURE[job] + "."
    prompt = VICTORY_PROMPT.format(cols=cols, rows=rows, n=len(keys), empty=empty, dress=dress,
                                   signature=JOB_SIGNATURE[job], core=JOB_CORE[job])
    refs = [("ref_poses.png", _pose_grid(plan["frames"], keys, cols), "image/png"),
            ("ref_costume.png", ref_bytes(plan["costume"], first_frame=True), "image/png")]
    unit = _rap.COST[quality]
    print(f"[{job}/{world}/victory] gpt-image-1 {quality} (${unit:.3f}) {len(keys)} pose(s) in a {cols}x{rows} grid "
          f"for {len(plan['frames'])} frames")
    try:
        # Real alpha, not white-then-keyed: 8 of the first 25 rolls came back on a painted backdrop
        raw = _rap.call_gpt(client, prompt, refs, quality, background="transparent")
    except Exception as e:
        print(f"  FAILED {job}/{world}/victory: {e}", file=sys.stderr)
        return 0.0, False
    rawp = RAW_DIR / f"{job}_{world}_victory_raw.png"
    assert_writable(rawp)
    raw.save(rawp)
    strip, why = assemble_victory(raw, plan)
    if strip is None:
        print(f"  REFUSED {job}/{world}: {why} -- re-roll (${unit:.3f} spent on it)", file=sys.stderr)
        return unit, False
    assert_writable(out)
    strip.save(out)
    print(f"  -> {out.relative_to(GAME_REPO)}  ({len(plan['frames'])} frames, poses {plan['assign']})")
    return unit, True


if __name__ == "__main__":
    sys.exit(main())
