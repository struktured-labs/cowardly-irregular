#!/usr/bin/env python3
"""Generate 32x32 pixel art save crystal sprite with 4-frame shimmer animation."""

from PIL import Image
import numpy as np
import math

# Palette — JRPG save crystal blues
T = (0, 0, 0, 0)            # transparent
OL = (16, 24, 64, 255)      # dark outline
DC = (32, 64, 160, 255)     # deep crystal blue
MC = (64, 112, 208, 255)    # medium crystal
LC = (96, 160, 240, 255)    # light crystal
BC = (144, 200, 255, 255)   # bright crystal
WH = (220, 240, 255, 255)   # white highlight
GL = (180, 220, 255, 200)   # glow aura
SG = (100, 160, 255, 120)   # soft glow
FG = (60, 100, 200, 80)     # faint glow
BS = (48, 80, 180, 255)     # base shadow
BD = (24, 40, 100, 200)     # base dark
BL = (80, 140, 220, 180)    # base light


def draw_crystal_body(px, highlight_offset=0):
    """Draw the main crystal shape — a faceted hexagonal gem."""
    # Crystal body occupies roughly x=9..22, y=4..24

    # ── Top point ──
    for x in range(14, 18):
        px[x, 4] = OL
    for x in range(15, 17):
        px[x, 5] = LC

    # ── Upper facets (y=6..10) ──
    for y in range(6, 11):
        spread = (y - 5)  # widens as we go down
        left = 14 - spread
        right = 17 + spread
        for x in range(left, right + 1):
            if x == left or x == right:
                px[x, y] = OL
            elif x < 16:
                # left facet — darker
                t = (x - left) / max(1, 16 - left)
                if t < 0.3:
                    px[x, y] = DC
                elif t < 0.7:
                    px[x, y] = MC
                else:
                    px[x, y] = LC
            else:
                # right facet — lighter
                t = (x - 16) / max(1, right - 16)
                if t < 0.4:
                    px[x, y] = LC
                elif t < 0.7:
                    px[x, y] = MC
                else:
                    px[x, y] = DC

    # ── Middle body (y=11..18) — widest part ──
    for y in range(11, 19):
        left = 8
        right = 23
        for x in range(left, right + 1):
            if x == left or x == right:
                px[x, y] = OL
            elif x < 13:
                px[x, y] = DC
            elif x < 16:
                px[x, y] = MC
            elif x < 19:
                px[x, y] = LC
            else:
                px[x, y] = MC

    # ── Lower facets (y=19..23) — tapers ──
    for y in range(19, 24):
        shrink = y - 18
        left = 8 + shrink
        right = 23 - shrink
        if left >= right:
            break
        for x in range(left, right + 1):
            if x == left or x == right:
                px[x, y] = OL
            elif x < 14:
                px[x, y] = DC
            elif x < 17:
                px[x, y] = MC
            else:
                px[x, y] = DC

    # ── Bottom point ──
    for x in range(14, 18):
        px[x, 24] = OL
    px[15, 24] = DC
    px[16, 24] = DC

    # ── Facet lines (internal edges) ──
    for y in range(7, 23):
        if 8 <= 15 <= 23:
            px[15, y] = blend(px[15, y], MC, 0.3) if px[15, y] != T and px[15, y] != OL else px[15, y]

    # ── Highlight shimmer (shifts per frame) ──
    h_positions = [
        [(12, 8), (13, 9), (13, 10)],   # frame 0
        [(17, 9), (18, 10), (18, 11)],   # frame 1
        [(14, 12), (15, 13), (14, 14)],  # frame 2
        [(19, 8), (20, 9), (19, 10)],    # frame 3
    ]
    idx = highlight_offset % 4
    for (hx, hy) in h_positions[idx]:
        if px[hx, hy] != T and px[hx, hy] != OL:
            px[hx, hy] = WH
    # Secondary highlight (always present but shifts)
    static_highlights = [(11, 12), (12, 13), (20, 15), (21, 14)]
    sh = static_highlights[idx]
    if px[sh[0], sh[1]] != T and px[sh[0], sh[1]] != OL:
        px[sh[0], sh[1]] = BC


def blend(c1, c2, t):
    """Blend two RGBA tuples."""
    if c1 == T:
        return c2
    return tuple(int(c1[i] * (1 - t) + c2[i] * t) for i in range(4))


def draw_glow_aura(px, frame=0):
    """Draw soft glow around the crystal, varies per frame."""
    cx, cy = 16, 14
    # Glow radius pulses
    base_r = 13 + frame * 0.5
    for y in range(32):
        for x in range(32):
            if px[x, y] != T:
                continue
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            if dist < base_r:
                alpha = int(60 * (1 - dist / base_r))
                if alpha > 5:
                    px[x, y] = (100, 160, 255, alpha)


def draw_base(px):
    """Draw floating platform/glow beneath crystal."""
    # Small glowing base ellipse at bottom
    cx, cy = 16, 26
    for y in range(25, 29):
        for x in range(10, 22):
            dx = abs(x - cx)
            dy = abs(y - cy)
            if dx * 1.5 + dy < 5:
                if dx * 1.5 + dy < 3:
                    px[x, y] = BL
                else:
                    px[x, y] = BD


def make_crystal_frame(frame_idx):
    """Create one 32x32 frame of the save crystal."""
    img = Image.new("RGBA", (32, 32), T)
    px = img.load()

    draw_base(px)
    draw_crystal_body(px, highlight_offset=frame_idx)
    draw_glow_aura(px, frame=frame_idx)

    return img


if __name__ == "__main__":
    from pathlib import Path

    out_dir = Path("tmp/generated/save_crystal")
    out_dir.mkdir(parents=True, exist_ok=True)

    frames = []
    for i in range(4):
        frame = make_crystal_frame(i)
        frame.save(out_dir / f"crystal_frame{i}.png")
        frames.append(frame)

    # Horizontal strip (4 frames)
    strip = Image.new("RGBA", (128, 32), T)
    for i, f in enumerate(frames):
        strip.paste(f, (i * 32, 0))
    strip.save(out_dir / "save_crystal.png")

    # 2x previews
    for i, f in enumerate(frames):
        f.resize((64, 64), Image.NEAREST).save(out_dir / f"crystal_frame{i}_2x.png")

    # 4x preview strip for easy viewing
    strip_4x = strip.resize((512, 128), Image.NEAREST)
    strip_4x.save(out_dir / "save_crystal_4x.png")

    print(f"Generated save crystal sprites in {out_dir}/")
    print(f"  save_crystal.png: {strip.size} (4-frame strip)")
    print(f"  Individual frames: crystal_frame0..3.png (32x32)")
