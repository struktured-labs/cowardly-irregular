#!/usr/bin/env python3
"""Recipe-card frames for the earned-autobattle-recipe reveal: a PREVIEW, not registered anywhere.

Draws a 64x88 pixel card in three rarity tiers (common / rare / epic) plus a LOCKED state, and a
few sample 20x20 recipe icons, procedurally (T1, $0, no model). No text is baked into the art:
the game draws the recipe name and the "6/10" progress in its own font, so a renamed recipe never
needs new pixels. Nothing here touches assets/ or data/sprite_manifest.json; the spec decides
where (and whether) these land.

    uv run python tools/gen_recipe_card_frames.py --out tmp/recipe_cards
writes card_<tier>.png, card_locked.png, icon_<id>.png and preview.png (4x, on the grey
(128,128,128) review ground).
"""
import argparse
from pathlib import Path

from PIL import Image

W, H = 64, 88
WIN = (6, 6, 58, 50)            # art window, icon centred in it
INK = (20, 16, 24, 255)         # outline

# tier -> (base, light, dark, window tint)
TIERS = {
    "common": ((138, 132, 124), (188, 182, 170), (86, 80, 76), (44, 42, 48)),
    "rare":   ((58, 104, 176), (120, 168, 232), (30, 56, 110), (24, 32, 60)),
    "epic":   ((204, 156, 44), (252, 222, 120), (128, 86, 20), (52, 38, 20)),
}
LOCKED = ((70, 66, 74), (98, 94, 104), (44, 40, 48), (16, 14, 20))


def _rect(px, x0, y0, x1, y1, c):
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[x, y] = c


def card(tier):
    base, light, dark, tint = (TIERS[tier] if tier in TIERS else LOCKED)
    a = lambda c: tuple(c) + (255,)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    # body, rounded by clipping the four outer corners
    _rect(px, 1, 1, W - 1, H - 1, a(base))
    for x, y in ((1, 1), (W - 2, 1), (1, H - 2), (W - 2, H - 2)):
        px[x, y] = (0, 0, 0, 0)
    # outline
    for x in range(2, W - 2):
        px[x, 0] = INK
        px[x, H - 1] = INK
    for y in range(2, H - 2):
        px[0, y] = INK
        px[W - 1, y] = INK
    for x, y in ((1, 1), (W - 2, 1), (1, H - 2), (W - 2, H - 2)):
        px[x, y] = INK
    # bevel: light top/left, dark bottom/right, two pixels deep
    for d in (1, 2):
        for x in range(1 + d, W - 1 - d):
            px[x, d] = a(light)
            px[x, H - 1 - d] = a(dark)
        for y in range(1 + d, H - 1 - d):
            px[d, y] = a(light)
            px[W - 1 - d, y] = a(dark)
    # art window, inset (dark rim on top/left reads as recessed)
    x0, y0, x1, y1 = WIN
    _rect(px, x0, y0, x1, y1, a(tint))
    for x in range(x0 - 1, x1 + 1):
        px[x, y0 - 1] = a(dark)
        px[x, y1] = a(light)
    for y in range(y0 - 1, y1 + 1):
        px[x0 - 1, y] = a(dark)
        px[x1, y] = a(light)
    # name plate (the game writes the name here) and a progress trough below it
    _rect(px, 6, 54, 58, 66, a(dark))
    _rect(px, 7, 55, 57, 65, a(tint))
    _rect(px, 6, 70, 58, 76, a(dark))
    _rect(px, 7, 71, 57, 75, a(tint))
    # corner studs, tier-coloured light
    for x, y in ((4, 80), (59, 80), (4, 4), (59, 4)):
        px[x, y] = a(light)
        px[x - 1, y] = px[x + 1, y] = px[x, y - 1] = px[x, y + 1] = a(dark)
    if tier == "locked":
        # a "?" in the window, so a silhouette reads as unearned at a glance
        q = ["  ####  ", " ##  ## ", "     ## ", "    ##  ", "   ##   ", "   ##   ", "        ", "   ##   "]
        cx, cy = (x0 + x1) // 2 - 8, (y0 + y1) // 2 - 8
        for j, row in enumerate(q):
            for i, ch in enumerate(row):
                if ch == "#":
                    _rect(px, cx + i * 2, cy + j * 2, cx + i * 2 + 2, cy + j * 2 + 2, a(light))
    return im


# 20x20 sample icons; '.' clear, letters index the palette
ICON_PAL = {
    "k": INK, "r": (206, 52, 60, 255), "R": (250, 120, 120, 255), "w": (240, 236, 224, 255),
    "g": (90, 190, 90, 255), "y": (250, 210, 70, 255), "Y": (196, 140, 30, 255), "b": (120, 90, 60, 255),
}
ICONS = {
    # Triage: a heart with a white cross
    "heal_ally_under_50": [
        "....................", "....................", "...kkk......kkk.....", "..kRRrk....kRrrk....",
        ".kRRrrrk..krrrrrk...", ".kRrrrrrkkrrrrrrk...", ".krrrrrrwwrrrrrrk...", ".krrrrrrwwrrrrrrk...",
        ".krrrrwwwwwwrrrrk...", ".krrrrwwwwwwrrrrk...", "..krrrrrwwrrrrrk....", "...krrrrwwrrrrk.....",
        "....krrrrrrrrk......", ".....krrrrrrk.......", "......krrrrk........", ".......krrk.........",
        "........kk..........", "....................", "....................", "....................",
    ],
    # Strategic Cowardice: a white flag on a pole
    "defer_at_low_ap": [
        "....................", "...kk...............", "...kbkkkkkkkkk......", "...kbkwwwwwwwwwk....",
        "...kbkwwwwwwwwwwk...", "...kbkwwwwwwwwwwk...", "...kbkwwwwwwwwwk....", "...kbkwwwwwwwwk.....",
        "...kbkwwwwwwwwwk....", "...kbkkkkkkkkkkkk...", "...kbk..............", "...kbk..............",
        "...kbk..............", "...kbk..............", "...kbk..............", "...kbk..............",
        "..kkbkk.............", ".kbbbbbk............", ".kkkkkkk............", "....................",
    ],
    # All In: a stack of gold coins
    "advance_full_bank": [
        "....................", "....................", "......kkkkkkk.......", ".....kyyyyyyyk......",
        ".....kYYYYYYYk......", "......kkkkkkk.......", ".....kyyyyyyyk......", ".....kYYYYYYYk......",
        "......kkkkkkk.......", ".....kyyyyyyyk......", ".....kYYYYYYYk......", "...kkkkkkkkkkkkk....",
        "..kyyyyyyykyyyyyk...", "..kYYYYYYYkYYYYYk...", "...kkkkkkkkkkkkk....", "..kyyyyyyykyyyyyk...",
        "..kYYYYYYYkYYYYYk...", "...kkkkkkkkkkkkk....", "....................", "....................",
    ],
}


def icon(rows):
    assert len(rows) == 20 and all(len(r) == 20 for r in rows), "icons are 20x20"
    im = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                im.putpixel((x, y), ICON_PAL[ch])
    return im


def with_icon(c, ic):
    out = c.copy()
    x0, y0, x1, y1 = WIN
    s = 2  # integer nearest-neighbour only
    big = ic.resize((ic.width * s, ic.height * s), Image.NEAREST)
    out.alpha_composite(big, ((x0 + x1 - big.width) // 2, (y0 + y1 - big.height) // 2))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="tmp/recipe_cards")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cards = {t: card(t) for t in (*TIERS, "locked")}
    icons = {k: icon(v) for k, v in ICONS.items()}
    for t, im in cards.items():
        im.save(out / f"card_{t}.png")
    for k, im in icons.items():
        im.save(out / f"icon_{k}.png")
    # preview: row 1 the bare tiers + locked, row 2 each sample icon on a tier, 4x, grey ground
    tiles = [cards[t] for t in (*TIERS, "locked")]
    tiles += [with_icon(cards[t], icons[k]) for t, k in zip(TIERS, ICONS)]
    gap, s = 8, 4
    cols = 4
    pw = cols * (W + gap) + gap
    ph = 2 * (H + gap) + gap
    pv = Image.new("RGBA", (pw, ph), (128, 128, 128, 255))
    for i, t in enumerate(tiles):
        pv.alpha_composite(t, (gap + (i % cols) * (W + gap), gap + (i // cols) * (H + gap)))
    pv = pv.resize((pw * s, ph * s), Image.NEAREST)
    pv.save(out / "preview.png")
    print(f"wrote {len(cards)} cards, {len(icons)} icons, preview {pv.size} -> {out}")


if __name__ == "__main__":
    main()
