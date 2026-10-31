#!/usr/bin/env python3
"""Redraw overworld NPC walk sheets in the ARTIST's villager proportions (48px cells).

struktured 2026-10-16: "take my artist sprites and use those as guides to redo all the
overworld npc sprites as higher quality using gpt" -> artist proportions at 48px, all 145.

The 145 T1 NPC sheets are 32px big-head chibis. The artist's three villagers (Rotha, Roy,
Kid Acrees; T2) are slim ~44px figures in 48px cells. Two references per call:

  1. STYLE / PROPORTION / LAYOUT  a composite of the three artist walkers (front, side, back),
                                  nearest-upscaled. Never the sheet being replaced: the chibi
                                  shape is the thing this redo removes, and a reference that
                                  carries it wins over the prompt
                                  (feedback_never_anchor_a_regen_on_the_asset_youre_replacing).
  2. IDENTITY                     the NPC's portrait bust (face, hair, palette), plus a written
                                  description; world variants add the world's wardrobe.

Output is assembled by gen_overworld_gpt_image.assemble_game_grid at target=48 and STAGED in
tmp/npc_artist_walker/out/<id>.png. --deploy writes assets/sprites/npcs/.../overworld.png and
the manifest entry (48x48, tier T1). Artist sheets (T2/T3) are refused before any API call.

PLAYER MODE (--player), struktured 2026-10-30: "our own characters are too small relative to npcs
now". The 14 overworld_player_sheets are 32px while the villagers above are 48px, so in a village
the party stands at 2/3 an NPC's height. --player redraws them at the same 48px cell and ADULT_H,
with the job's BATTLE sheet idle frame as identity (the five starters' battle sheets are the
artist's). It writes assets/sprites/jobs/<job>/overworld.png IN PLACE so every guard that reads that
path keeps judging what ships; artist_guard.assert_writable gates each write. The art alone changes
nothing: OverworldPlayer.SPRITE_SIZE (32) shrinks every frame back down, so cowir-main lands
SPRITE_SIZE 32 -> 48 in the same fold.

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_npc_artist_walker.py --ids farmer old_woman guard          # stage
    uv run python tools/gen_npc_artist_walker.py --ids farmer --deploy                 # stage + ship
    uv run python tools/gen_npc_artist_walker.py --all --deploy --skip-existing
    uv run python tools/gen_npc_artist_walker.py --player --all                         # stage the party
"""

from __future__ import annotations

import argparse
import base64
import importlib.util
import io
import json
import re
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "data/sprite_manifest.json"
PORTRAITS = REPO / "assets/sprites/portraits/npcs"
WORK = REPO / "tmp/npc_artist_walker"
OUT = WORK / "out"
CELL = 48
ARTIST_GUIDES = ("rotha", "kid_acrees", "roy")
WORLD_RE = re.compile(r"_(suburban|steampunk|industrial|digital|abstract)$")
SECTION = "overworld_npc_sheets"  # --player switches to overworld_player_sheets
JOBS = REPO / "assets/sprites/jobs"
PLAYER = False

_spec = importlib.util.spec_from_file_location("ow", REPO / "tools/gen_overworld_gpt_image.py")
ow = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ow)
_spec2 = importlib.util.spec_from_file_location("wv", REPO / "tools/gen_npc_world_variants.py")
wv = importlib.util.module_from_spec(_spec2)
_spec2.loader.exec_module(wv)

## Roles the existing tool does not describe; the portrait carries the rest of the identity.
EXTRA_DESC = {
    "bram": "Bram, a sturdy village man in plain working clothes",
    "marta": "Marta, a kindly middle-aged village woman in a simple dress and apron",
    "elder": "a village elder, an old man in long modest robes with a walking staff",
    "elder_theron": "Elder Theron, the village's dignified old leader in long robes with a staff",
    "scholar_milo": "Milo, a young bookish scholar in a long coat, carrying a book",
    "phil": "Phil, an ordinary friendly townsman in everyday clothes",
    "chancellor_mordaine": "Chancellor Mordaine, a stern mature noblewoman with a silver updo, "
                           "a small gemmed band, a violet sash over teal robes",
    "fairy": "a tiny fairy with translucent wings and a light flowing dress",
    "ghost": "a pale translucent wandering ghost in tattered grey clothes",
    "mysterious": "a mysterious hooded stranger in a dark travelling cloak, face in shadow",
    "arbiter": "a severe robed judge-like official",
    "curator": "a meticulous robed archivist carrying a ledger",
    "tempo": "a nimble courier in fitted travelling clothes",
    "warden": "a stoic armoured gatekeeper",
}

## Written from each job's battle idle frame, and preferred over gen_overworld_gpt_image's char_desc:
## that table predates the artist's Sep-Oct redesigns (it says the rogue carries a BOW; hers is a crossbow).
JOB_DESC = {
    "fighter": "a brown-haired young knight in deep red armour with copper shoulder plates, carrying a broad steel sword",
    "cleric": "a cleric with long silver-white hair in a white hooded robe with blue accents, holding one ornate golden "
              "star-tipped staff",
    "mage": "a white-haired mage in a tall purple-blue pointed hat with a gold band and a long dark green cloak, "
            "holding a curved golden staff",
    "rogue": "a young woman rogue with a long brown ponytail in a dark navy coat with red trim, a crossbow over her "
             "shoulder and a dagger at her hip",
    "bard": "a young woman bard with long bright orange hair, a crimson and white outfit, carrying a large ornate "
            "stringed instrument",
    "guardian": "a guardian knight in full steel plate armour with gold trim on the pauldrons and chest, "
                "a closed helmet with a visor",
    "ninja": "a ninja in close-fitting black and dark purple garb with a face mask and a red sash, a short sword",
    "summoner": "a summoner in flowing light-blue robes with gold trim and small curved horns",
    "speculator": "a young businessman with brown hair and glasses in a dark navy suit and tie, "
                  "carrying a brown leather briefcase",
    "scriptweaver": "a slim dark-haired young man in a long dark hooded coat with thin glowing green trim",
    "time_mage": "a white-haired time mage in a tall pointed blue hat and long blue robes with gold trim, "
                 "holding a gold pocket watch",
    "necromancer": "a gaunt hooded necromancer in tattered grey-black robes",
    "bossbinder": "a muscular brawler with dark hair tied in a topknot, in dark red and black plated armour, "
                  "carrying a heavy chain",
    "skiptrotter": "an adventurer with aviator goggles on a cap, a long tan trench coat and brown boots",
}

PROMPT = """Redraw this character as a 3-direction overworld WALK SHEET for a 16-bit JRPG.

THE CHARACTER: {desc}. Face, hair colour, skin tone and colour palette come from Reference Image 2
(their portrait). Keep them instantly recognisable as that person.

THE STYLE, PROPORTIONS AND SCALE come ONLY from Reference Image 1 (the game artist's villagers):
  - SLIM, REALISTIC proportions about 5 to 6 heads tall, exactly like those villagers.
    NOT chibi, NOT big-headed, NOT squat. Head small relative to body, long legs, narrow shoulders.
  - The same crisp hand-placed pixel art: dark coloured outline, 2-3 tone shading on clothes,
    small readable face. No anti-aliasing, no gradients, no blur.
  - Same 3/4 top-down overworld camera as the villagers.

LAYOUT - exactly 3 rows on a plain white background, 3 frames per row, figures evenly spaced and
not touching:
  Row 1: walking SOUTH toward the viewer (front, face visible)
  Row 2: walking EAST, side profile facing RIGHT
  Row 3: walking NORTH away from the viewer (back view: back of head only, NO face)
  In every row: frame 1 standing, frame 2 right foot forward, frame 3 left foot forward.
Every figure the same height, full body from head to feet, nothing cropped. SIZE LIMIT: each figure is
at most 380 pixels tall on this 1536-pixel-tall canvas, so the three rows fit with clear white gaps between
them, and the bottom row's feet end at least 120 pixels above the bottom edge. No figure may touch or
cross any edge of the image. Smaller figures are fine; cropped figures are not.
Return only the sprite sheet: no text, no labels, no borders, no shadows."""


def manifest() -> dict:
    return json.loads(MANIFEST.read_text())


def base_id(npc: str) -> tuple[str, str | None]:
    m = WORLD_RE.search(npc)
    return (npc[: m.start()], m.group(1)) if m else (npc, None)


# World variants whose portrait outweighed the wardrobe text, named outfit and all (each matches the sheet it replaces).
WARDROBE = {
    "king_suburban": "a gold crown worn with an ordinary blue business suit and tie -- NOT royal robes, NOT a cape",
    "guard_suburban": "a teal baseball cap and a khaki work jacket, holding a tall spear upright like a security guard",
    "king_industrial": ("a hard hat with yellow hazard stripes and a small gold crown badge, dark riveted work overalls "
                        "and heavy gloves -- NOT royal robes, NOT a cape"),
    "old_woman_industrial": ("clearly ELDERLY: grey hair, lined face, a little stooped; a dark steel safety helmet, "
                             "heavy dark work coat and gloves"),
}


def describe(npc: str) -> str:
    if PLAYER:
        cfg = ow.ENTITY_SOURCES.get(npc) or {}
        return JOB_DESC.get(npc) or cfg.get("char_desc") or npc.replace("_", " ")
    base, world = base_id(npc)
    cfg = ow.ENTITY_SOURCES.get(base)
    desc = (cfg or {}).get("char_desc") or EXTRA_DESC.get(base) or base.replace("_", " ")
    if world:
        desc = (f"{desc} -- the SAME person, re-dressed for {wv.WORLDS[world]}; keep their face, "
                f"hair and build, change only the clothes and accessories")
    if npc in WARDROBE:
        desc = f"{desc}. Outfit: {WARDROBE[npc]}"
    return desc


def refuse_artist(npc: str, entry: dict) -> None:
    if str(entry.get("tier", "")) in ("T2", "T3") or npc in ARTIST_GUIDES:
        raise SystemExit(f"REFUSED {npc}: tier {entry.get('tier')} is artist work; this tool never overwrites it")


def style_reference(entries: dict) -> bytes:
    """Front, side and back standing frames of each artist villager, x5 nearest, on transparency."""
    frames = []
    for g in ARTIST_GUIDES:
        e = entries[g]
        fw, fh = int(e.get("frame_width", 48)), int(e.get("frame_height", 48))
        sheet = Image.open(REPO / e["path"].replace("res://", "")).convert("RGBA")
        for row in (0, 2, 3):  # down, right, up
            cell = sheet.crop((0, row * fh, fw, (row + 1) * fh))
            bb = cell.getbbox()
            frames.append(cell.crop(bb) if bb else cell)
    s = 5
    h = max(f.height for f in frames) * s
    canvas = Image.new("RGBA", (sum(f.width * s + 24 for f in frames), h + 16), (0, 0, 0, 0))
    x = 8
    for f in frames:
        big = f.resize((f.width * s, f.height * s), Image.NEAREST)
        canvas.paste(big, (x, 8 + h - big.height), big)
        x += big.width + 24
    return ow.pad_to_square(canvas, 1024)


def battle_identity_frame(job: str) -> Image.Image:
    """The job's first battle frame: idle if it has one. For the five starters that is artist art."""
    for anim in ("idle", "walk", "attack", "cast", "defend"):
        p = JOBS / job / f"{anim}.png"
        if p.exists():
            sheet = Image.open(p).convert("RGBA")
            cell = sheet.crop((0, 0, sheet.height, sheet.height))
            bb = cell.getbbox()
            return cell.crop(bb) if bb else cell
    raise SystemExit(f"{job}: no battle frame under {JOBS / job}")


def identity_reference(npc: str, entries: dict) -> bytes:
    if PLAYER:
        f = battle_identity_frame(npc)
        return ow.pad_to_square(f.resize((f.width * 3, f.height * 3), Image.NEAREST), 1024)
    base, _ = base_id(npc)
    for p in (PORTRAITS / f"{base}.png", PORTRAITS / f"{npc}.png"):
        if p.exists():
            return ow.pad_to_square(Image.open(p).convert("RGBA"), 1024)
    # The Masterite roles (arbiter, curator, tempo, warden) have no portrait: their battle sheet's
    # idle frame for this world is the identity.
    _, world = base_id(npc)
    mon = manifest()["monster_sheets"].get(f"masterite_{base}_{world or 'medieval'}")
    if mon:
        sheet = Image.open(REPO / mon["path"].replace("res://", "")).convert("RGBA")
        fw = int(mon.get("frame_width", 256))
        i = int(mon.get("animations", {}).get("idle", {}).get("start", 0))
        return ow.pad_to_square(sheet.crop((i * fw, 0, (i + 1) * fw, int(mon.get("frame_height", fw)))), 1024)
    raise SystemExit(f"{npc}: no portrait at {PORTRAITS}/{base}.png and no masterite battle sheet")


## Figure height in the 48px cell, by role. The artist's villagers stand 41-47px tall (Kid 41, Rotha 47).
HEIGHT = {"child": 38, "fairy": 30, "ghost": 42}
ADULT_H = 44
EDGE = 6  # a figure within this many px of the canvas edge was cut off by the model


class BadRoll(Exception):
    pass


def _merge_slivers(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Fold a narrow column (a spear shaft, a staff) into its nearest neighbour.

    The x-range detector splits on empty gutters, and a held pole often stands clear of the body,
    so it came back as a 'figure' of its own: the pilot guard's side frames assembled at 90 opaque
    px, the shaft alone. A sliver is any range under 40% of the row's median width."""
    if len(ranges) < 2:
        return ranges
    widths = sorted(b - a for a, b in ranges)
    med = widths[len(widths) // 2]
    out = [list(r) for r in ranges]
    i = 0
    while i < len(out) and len(out) > 1:
        a, b = out[i]
        if b - a < 0.4 * med:
            left = out[i - 1] if i > 0 else None
            right = out[i + 1] if i + 1 < len(out) else None
            gl = a - left[1] if left else 10**9
            gr = right[0] - b if right else 10**9
            tgt = left if gl <= gr else right
            tgt[0], tgt[1] = min(tgt[0], a), max(tgt[1], b)
            out.pop(i)
            continue
        i += 1
    return [tuple(r) for r in out]


def extract_rows(raw: Image.Image, n_rows: int) -> list[list[Image.Image]]:
    """Cut each content row of a GPT raw into its figures (tight crops), refusing a cropped roll.

    Alpha is snapped at 128 first: the model sometimes returns a TRANSPARENT background carrying a
    faint low-alpha haze over the whole canvas, which read as one figure from y 0 to the bottom."""
    keyed = ow._binarize_alpha(ow._strip_white_bg(raw.copy()), 128)
    if n_rows == 1:
        bb = keyed.getbbox()
        bands = [(0, keyed.height)] if bb else None
    else:
        bands = ow._detect_row_bands(keyed, n_rows)
    if bands is None:
        raise BadRoll(f"{ow._count_row_bands(keyed)} content rows, need {n_rows}")
    rows = []
    for y0, y1 in bands:
        band = keyed.crop((0, y0, keyed.width, y1))
        figs = []
        for x0, x1 in _merge_slivers(ow._detect_chibi_x_ranges(band)):
            cell = band.crop((max(0, x0 - 8), 0, min(band.width, x1 + 8), band.height))
            bb = cell.getbbox()
            if not bb:
                continue
            ax0, ay0 = max(0, x0 - 8) + bb[0], y0 + bb[1]
            ax1, ay1 = max(0, x0 - 8) + bb[2], y0 + bb[3]
            if ax0 < EDGE or ay0 < EDGE or ax1 > keyed.width - EDGE or ay1 > keyed.height - EDGE:
                raise BadRoll(f"a figure touches the canvas edge at y {ay0}-{ay1}: the model cropped it")
            figs.append(cell.crop(bb))
        if len(figs) < 2:
            raise BadRoll(f"a row holds {len(figs)} figure(s), need 2-3")
        rows.append(figs)
    return rows


def build_grid(rows: list[list[Image.Image]], figure_h: int, back_ratio: float = 1.0) -> Image.Image:
    """3 rows (south, east, north) -> 4 game rows (down, left, right, up) of 48px cells.

    ONE scale serves the sheet and every figure stands on the cell floor, so a frame the model drew
    smaller or cropped cannot be blown up to fill its cell (the pilot's back rows came out as giant
    heads that way). back_ratio rescales a north row drawn in a SEPARATE call, whose figures sit at
    their own scale: it is that call's height relative to the front row's."""
    from PIL import ImageOps
    tallest = max(f.height for f in rows[0])
    s0 = figure_h / tallest
    scales = [s0, s0, s0 * back_ratio]
    fit = min((CELL - 2) / max(f.width for f in figs) / sc for figs, sc in zip(rows, scales))
    fit = min(fit, min((CELL - 1) / max(f.height for f in figs) / sc for figs, sc in zip(rows, scales)))
    k = min(1.0, fit)  # shrink the whole sheet together if a prop would overflow a cell

    def shrink(f: Image.Image, sc: float) -> Image.Image:
        w, h = max(1, round(f.width * sc * k)), max(1, round(f.height * sc * k))
        w, h = min(w, CELL), min(h, CELL - 1)
        small = ow._binarize_alpha(f.resize((w, h), Image.BOX))
        tile = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        tile.paste(small, ((CELL - w) // 2, CELL - 1 - h), small)
        return tile

    walk = [[shrink(f, sc) for f in figs] for figs, sc in zip(rows, scales)]
    walk = [ow.head_lock_row(ow._build_4frame_walk(r)) for r in walk]
    grid = Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 0))
    # Which way the "east" row faces depends on the MODEL. gpt-image-1 drew it facing LEFT despite the
    # prompt (55 of 70 NPC sheets by eye, 2026-10-16); gpt-image-2 draws it facing RIGHT as asked (14 of
    # 14 player sheets at 10x, 2026-10-30). As-drawn goes on the row it faces; --flip fixes exceptions.
    left_row, right_row = (CELL, CELL * 2) if MODEL == "gpt-image-1" else (CELL * 2, CELL)
    for col in range(4):
        grid.paste(walk[0][col], (col * CELL, 0))
        grid.paste(walk[1][col], (col * CELL, left_row))
        grid.paste(ImageOps.mirror(walk[1][col]), (col * CELL, right_row))
        grid.paste(walk[2][col], (col * CELL, CELL * 3))
    return grid


def assemble_artist_grid(raw: Image.Image, figure_h: int) -> Image.Image:
    return build_grid(extract_rows(raw, 3), figure_h)


## SPLIT MODE. Some tall roles (robes, gowns, a crown) ran their THIRD row off the bottom edge on every
## roll, and neither a pixel limit in the text nor a box-layout reference fixed it (the box layout fixed
## the crop and scrambled which view went in which row). Asking for fewer rows per call leaves room.
SPLIT_FRONT_SIDE = PROMPT.replace(
    "LAYOUT - exactly 3 rows", "LAYOUT - exactly 2 rows").replace(
    "  Row 3: walking NORTH away from the viewer (back view: back of head only, NO face)\n", "")
SPLIT_BACK = PROMPT.replace("3-direction overworld WALK SHEET", "BACK-VIEW walk row").replace(
    "LAYOUT - exactly 3 rows", "LAYOUT - exactly 1 row").replace(
    "  Row 1: walking SOUTH toward the viewer (front, face visible)\n"
    "  Row 2: walking EAST, side profile facing RIGHT\n"
    "  Row 3: walking NORTH away from the viewer (back view: back of head only, NO face)\n",
    "  The row: walking NORTH away from the viewer (back view: back of head only, NO face)\n")


## gpt-image-1 drew the 145 villagers (2026-10-16) and was RETIRED by 2026-10-30: still listed by
## /v1/models, but edit AND generate both return 400 "does not exist". --model picks its successor.
MODEL = "gpt-image-2"


def _call(client, refs, prompt: str, size: str, quality: str) -> Image.Image:
    resp = client.images.edit(model=MODEL, image=refs, prompt=prompt, size=size, quality=quality, n=1)
    return Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")


def generate(client, npc: str, entries: dict, quality: str, attempts: int = 3, split: bool = False) -> Image.Image:
    desc = describe(npc)
    # The artist guides live in the NPC section whichever section is being redrawn.
    refs = [("ref1_artist_villagers.png", style_reference(manifest()["overworld_npc_sheets"]), "image/png"),
            ("ref2_identity_portrait.png", identity_reference(npc, entries), "image/png")]
    prompt = PROMPT.replace("(their portrait)", "(their battle sprite)") if PLAYER else PROMPT
    figure_h = HEIGHT.get(base_id(npc)[0], ADULT_H)
    last = None
    for n in range(1, attempts + 1):
        try:
            if split:
                fs = SPLIT_FRONT_SIDE.replace("(their portrait)", "(their battle sprite)") if PLAYER else SPLIT_FRONT_SIDE
                a = _call(client, refs, fs.format(desc=desc), "1024x1536", quality)
                a.save(WORK / f"{npc}_rawA{n}.png")
                front_side = extract_rows(a, 2)
                bk = SPLIT_BACK.replace("(their portrait)", "(their battle sprite)") if PLAYER else SPLIT_BACK
                b = _call(client, refs, bk.format(desc=desc), "1536x1024", quality)
                b.save(WORK / f"{npc}_rawB{n}.png")
                back = extract_rows(b, 1)[0]
                ratio = max(f.height for f in front_side[0]) / max(f.height for f in back)
                grid = build_grid(front_side + [back], figure_h, back_ratio=ratio)
            else:
                raw = _call(client, refs, prompt.format(desc=desc), "1024x1536", quality)
                raw.save(WORK / f"{npc}_raw{n}.png")
                grid = assemble_artist_grid(raw, figure_h)
            ow.refuse_hollow_grid(grid, npc, target=CELL)
            return grid
        except (BadRoll, ow.RowCountMismatch, ValueError, SystemExit, RuntimeError) as e:  # bad roll: re-roll
            last = e
            print(f"  re-roll {n}/{attempts} {npc}: {e}", flush=True)
    raise RuntimeError(f"{npc}: {attempts} rolls unusable -- {last}")


def deploy(npc: str, grid: Image.Image) -> None:
    m = manifest()
    entry = m[SECTION][npc]
    refuse_artist(npc, entry)
    dest = REPO / entry["path"].replace("res://", "")
    if PLAYER:
        # jobs/<job>/ also holds the artist's battle sheets: refuse fail-closed on provenance, not on the label.
        sys.path.insert(0, str(REPO / "tools"))
        import artist_guard
        artist_guard.assert_writable(str(dest.relative_to(REPO)))
    backup = WORK / "replaced" / f"{npc}.png"
    backup.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and not backup.exists():
        backup.write_bytes(dest.read_bytes())
    grid.save(dest)
    entry["frame_width"] = CELL
    entry["frame_height"] = CELL
    entry["tier"] = "T1"
    entry["source"] = ("gpt-image-1 redraw in the artist villagers' proportions (Rotha, Roy, Kid "
                       "Acrees as style guide; the NPC's portrait as identity), 48px cells -- "
                       "tools/gen_npc_artist_walker.py, struktured 2026-10-16. T1: artist veto applies.")
    if PLAYER:
        entry["source"] = (f"{MODEL} redraw at the villagers' 48px scale (Rotha, Roy, Kid Acrees as style "
                           "guide; the job's battle idle frame as identity) -- tools/gen_npc_artist_walker.py "
                           "--player, struktured 2026-10-30 'our own characters are too small relative to npcs'. "
                           "Pairs with OverworldPlayer.SPRITE_SIZE 48. T1: artist veto applies.")
    raw = MANIFEST.read_text()
    indent = 2 if raw.startswith("{\n  ") else (1 if raw.startswith("{\n ") else "\t")
    MANIFEST.write_text(json.dumps(m, indent=indent, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))


def main() -> int:
    global SECTION, PLAYER, WORK, OUT, MODEL
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", default=[])
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--deploy", action="store_true")
    ap.add_argument("--skip-existing", action="store_true", help="skip ids already staged in tmp/.../out")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--split", action="store_true", help="two calls per sheet: front+side, then back (for roles whose 3rd row crops)")
    ap.add_argument("--flip", nargs="+", default=[], metavar="ID",
                    help="swap the left and right rows of these STAGED sheets (the model drew 'east' facing left), then exit")
    ap.add_argument("--player", action="store_true",
                    help="redraw overworld_player_sheets (the 14 jobs) instead of NPCs; stages under tmp/player_artist_walker")
    ap.add_argument("--model", default=MODEL, help=f"image model (default {MODEL}; gpt-image-1 is retired)")
    args = ap.parse_args()
    MODEL = args.model
    if args.player:
        SECTION, PLAYER = "overworld_player_sheets", True
        WORK = REPO / "tmp/player_artist_walker"
        OUT = WORK / "out"
    if args.flip:
        for npc in args.flip:
            p = OUT / f"{npc}.png"
            g = Image.open(p).convert("RGBA")
            left, right = g.crop((0, CELL, CELL * 4, CELL * 2)), g.crop((0, CELL * 2, CELL * 4, CELL * 3))
            g.paste(right, (0, CELL))
            g.paste(left, (0, CELL * 2))
            g.save(p)
            print("flipped", npc)
        return 0
    entries = manifest()[SECTION]
    ids = [k for k in entries if str(entries[k].get("tier")) == "T1"] if args.all else args.ids
    for npc in ids:
        refuse_artist(npc, entries[npc])
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    if args.dry_run:
        for npc in ids:
            print(npc, "|", describe(npc)[:110])
        return 0
    from openai import OpenAI
    client = OpenAI()
    done, failed = 0, []
    for npc in ids:
        staged = OUT / f"{npc}.png"
        if args.skip_existing and staged.exists():
            grid = Image.open(staged).convert("RGBA")
        else:
            try:
                grid = generate(client, npc, entries, args.quality, split=args.split)
            except Exception as e:
                failed.append(f"{npc}: {e}")
                print("FAILED", npc, e, flush=True)
                continue
            grid.save(staged)
        if args.deploy:
            deploy(npc, grid)
        done += 1
        print(f"ok {npc} ({done}/{len(ids)})", flush=True)
    print(f"done {done} · failed {len(failed)}")
    for f in failed:
        print("  ", f)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
