#!/usr/bin/env python3
"""Generate 32x32 pixel art treasure chest sprites (closed + open) for overworld."""

from PIL import Image, ImageDraw
import numpy as np

# Palette
O = (26, 16, 16, 255)       # outline
DW = (92, 51, 16, 255)      # dark wood
MW = (139, 85, 48, 255)     # medium wood
LW = (176, 119, 64, 255)    # light wood
HW = (212, 160, 80, 255)    # wood highlight
GM = (192, 144, 32, 255)    # gold metal
GH = (232, 192, 64, 255)    # gold highlight
GS = (136, 112, 32, 255)    # gold shadow
KH = (42, 26, 10, 255)      # keyhole/dark
SH = (58, 42, 26, 128)      # shadow (semi-transparent)
GL = (255, 232, 112, 255)   # open chest glow
WH = (255, 255, 240, 200)   # sparkle/white glow
T = (0, 0, 0, 0)            # transparent


def make_closed_chest():
    """Create a 32x32 closed treasure chest."""
    img = Image.new("RGBA", (32, 32), T)
    px = img.load()

    # ── LID (rounded top) ──
    # Row 8: top curve
    for x in range(11, 21):
        px[x, 8] = O

    # Row 9: wider lid top
    for x in range(9, 23):
        px[x, 9] = O if x in (9, 22) else LW
    px[10, 9] = HW  # highlight

    # Rows 10-14: lid body
    for y in range(10, 15):
        for x in range(8, 24):
            if x == 8 or x == 23:
                px[x, y] = O
            elif y == 12:  # gold band
                px[x, y] = GM if x % 2 == 0 else GH
            elif y == 10:
                px[x, y] = HW if x < 14 else LW
            else:
                px[x, y] = MW if (x + y) % 3 != 0 else LW

    # Row 15: lid-body divider (metal trim)
    for x in range(8, 24):
        if x == 8 or x == 23:
            px[x, 15] = O
        elif x == 15 or x == 16:
            px[x, 15] = GH  # clasp
        else:
            px[x, 15] = GS

    # ── BODY (rectangular box) ──
    for y in range(16, 24):
        for x in range(8, 24):
            if x == 8 or x == 23:
                px[x, y] = O
            elif y == 23:  # bottom outline
                px[x, y] = O
            elif y == 19:  # gold band on body
                px[x, y] = GM if x % 2 == 0 else GH
            elif y == 20 and x in (15, 16):  # keyhole
                px[x, y] = KH
            elif y == 16:
                px[x, y] = DW  # top of body is darker (shadow from lid)
            else:
                px[x, y] = MW if (x + y) % 4 != 0 else DW

    # top edge of body
    for x in range(9, 23):
        px[x, 16] = DW

    # Bottom shadow
    for x in range(7, 25):
        px[x, 24] = SH

    # Corner reinforcements (gold rivets)
    for (rx, ry) in [(9, 10), (22, 10), (9, 22), (22, 22)]:
        px[rx, ry] = GH

    return img


def make_open_chest():
    """Create a 32x32 open treasure chest with glowing interior."""
    img = Image.new("RGBA", (32, 32), T)
    px = img.load()

    # ── LID (tilted back, shown behind/above the body) ──
    # Lid is now open, drawn at top tilted backward
    # Row 3-4: top of open lid
    for x in range(10, 22):
        px[x, 3] = O
    for x in range(9, 23):
        px[x, 4] = O if x in (9, 22) else LW

    # Rows 5-8: visible lid interior (darker, foreshortened)
    for y in range(5, 9):
        for x in range(8, 24):
            if x == 8 or x == 23:
                px[x, y] = O
            elif y == 7:  # gold band on lid
                px[x, y] = GM if x % 2 == 0 else GH
            else:
                px[x, y] = DW if (x + y) % 3 != 0 else MW

    # Row 9: bottom of open lid / hinge line
    for x in range(8, 24):
        px[x, 9] = O if x in (8, 23) else GS

    # ── GLOW from inside ──
    # Rows 10-12: golden glow emanating upward
    for y in range(10, 13):
        spread = 13 - y  # wider at top
        for x in range(16 - spread, 16 + spread):
            if 8 < x < 23:
                alpha = int(200 * (13 - y) / 3)
                px[x, y] = (255, 232, 112, alpha)

    # ── BODY (same as closed but interior visible) ──
    for y in range(13, 24):
        for x in range(8, 24):
            if x == 8 or x == 23:
                px[x, y] = O
            elif y == 23:  # bottom outline
                px[x, y] = O
            elif y == 13:  # rim of chest opening
                px[x, y] = GH
            elif y == 14:  # inside glow top
                px[x, y] = GL if 11 < x < 20 else DW
            elif y == 15:  # inside still glowy
                px[x, y] = (255, 220, 100, 220) if 12 < x < 19 else MW
            elif y == 19:  # gold band on body
                px[x, y] = GM if x % 2 == 0 else GH
            elif y == 16:
                px[x, y] = MW
            else:
                px[x, y] = MW if (x + y) % 4 != 0 else DW

    # Corner rivets
    for (rx, ry) in [(9, 13), (22, 13), (9, 22), (22, 22)]:
        px[rx, ry] = GH

    # Sparkle above chest (item gleam)
    px[15, 6] = WH
    px[16, 5] = WH
    px[14, 7] = (255, 255, 240, 120)
    px[17, 7] = (255, 255, 240, 120)

    # Bottom shadow
    for x in range(7, 25):
        px[x, 24] = SH

    return img


if __name__ == "__main__":
    import sys
    from pathlib import Path

    out_dir = Path("tmp/generated/treasure_chest")
    out_dir.mkdir(parents=True, exist_ok=True)

    closed = make_closed_chest()
    opened = make_open_chest()

    closed.save(out_dir / "chest_closed.png")
    opened.save(out_dir / "chest_open.png")

    # Also create a 2-frame horizontal strip (closed | open)
    strip = Image.new("RGBA", (64, 32), T)
    strip.paste(closed, (0, 0))
    strip.paste(opened, (32, 0))
    strip.save(out_dir / "treasure_chest.png")

    # Create 2x scaled versions for preview
    closed_2x = closed.resize((64, 64), Image.NEAREST)
    opened_2x = opened.resize((64, 64), Image.NEAREST)
    closed_2x.save(out_dir / "chest_closed_2x.png")
    opened_2x.save(out_dir / "chest_open_2x.png")

    print(f"Generated treasure chest sprites in {out_dir}/")
    print(f"  chest_closed.png: {closed.size}")
    print(f"  chest_open.png: {opened.size}")
    print(f"  treasure_chest.png: {strip.size} (2-frame strip)")
