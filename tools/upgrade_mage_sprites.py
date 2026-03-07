#!/usr/bin/env python3
"""
Mage sprite animation upgrade: expand frame counts for smoother animation.

Target frame counts (256x256 frames each):
  idle    : 2 → 4  (1024x256)
  walk    : 6 → 8  (2048x256)
  attack  : 6 → 8  (2048x256)
  hit     : 4 → 6  (1536x256)
  dead    : 4 → 6  (1536x256)
  cast    : 4 → 6  (1536x256)
  victory : 4 → 6  (1536x256)
  defend  : 4  (unchanged)
  item    : 4  (unchanged)

Strategy: Use the mage's make_frame() API with interpolated parameter values
between existing keyframes. The mage is fully procedural so we simply call
make_frame() with tweened parameters — no pixel blending needed.

Interpolation uses nearest-integer (pixel art style) — we vary parameters
by 1-3px per step for staff position, 1-2px for body sway, etc.
"""

import sys
import math
import os
from pathlib import Path
from PIL import Image

# ── Insert mage generator source inline via exec ───────────────────────────
# We need the make_frame() function from gen_mage_sprites.py
MAGE_GEN = Path("/home/struktured/projects/cowardly-irregular/tools/gen_mage_sprites.py")
OUT_DIR   = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/mage")
FRAME_W   = 256
FRAME_H   = 256

# Execute the generator to bring all helpers into our namespace
_ns = {}
exec(compile(MAGE_GEN.read_text(), str(MAGE_GEN), 'exec'), _ns)
make_frame = _ns['make_frame']
TRANSPARENT = _ns['TRANSPARENT']

# ── Interpolation helpers ──────────────────────────────────────────────────

def lerp(a, b, t):
    """Linear interpolate, snap to nearest integer."""
    return int(round(a + (b - a) * t))

def lerp_f(a, b, t):
    """Float lerp (for orb_bright etc.)."""
    return a + (b - a) * t

def tween(params_a, params_b, t):
    """Tween two param dicts. Int params get snapped; float params are lerped."""
    result = {}
    all_keys = set(params_a.keys()) | set(params_b.keys())
    for k in all_keys:
        va = params_a.get(k, params_b.get(k))
        vb = params_b.get(k, params_a.get(k))
        if isinstance(va, bool) or isinstance(vb, bool):
            result[k] = va if t < 0.5 else vb
        elif isinstance(va, float) or isinstance(vb, float):
            result[k] = lerp_f(float(va), float(vb), t)
        elif isinstance(va, int) and isinstance(vb, int):
            result[k] = lerp(va, vb, t)
        else:
            result[k] = va if t < 0.5 else vb
    return result

def build_strip(frames, n):
    strip = Image.new("RGBA", (FRAME_W * n, FRAME_H), TRANSPARENT)
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip

# ── Common base params (idle standing pose) ───────────────────────────────
# From the original gen_mage_sprites.py idle frame analysis:
#   cx=128, foot_y=226, hat_tilt=0, body_sway=0, robe_bob=0
#   boot_spread=10, orb_bright=0.5, eyes_open=True
#   left_hand: cx-22=106, waist_y+30=148
#   right_hand: cx+20=148, waist_y+30=148
#   staff_top: cx-28=100, waist_y-55=63

BASE_CX    = 128
BASE_FY    = 226
BASE_WAIST = BASE_FY - 108  # = 118
BASE_LHX   = BASE_CX - 22   # = 106
BASE_LHY   = BASE_WAIST + 30 # = 148
BASE_RHX   = BASE_CX + 20   # = 148
BASE_RHY   = BASE_WAIST + 30 # = 148
BASE_STX   = BASE_CX - 28   # = 100
BASE_STY   = BASE_WAIST - 55 # = 63


def base(**overrides):
    """Return the base idle param dict, optionally overriding keys."""
    d = dict(
        cx=BASE_CX, foot_y=BASE_FY,
        hat_tilt=0, body_sway=0, robe_bob=0, boot_spread=10,
        orb_bright=0.5, eyes_open=True,
        left_hand_x=BASE_LHX, left_hand_y=BASE_LHY,
        right_hand_x=BASE_RHX, right_hand_y=BASE_RHY,
        staff_top_x=BASE_STX, staff_top_y=BASE_STY,
    )
    d.update(overrides)
    return d


# ════════════════════════════════════════════════════════════════════════════
# IDLE — expand 2 → 4 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 2:
#   F0: base idle (staff angled upper-left, both hands low)
#   F1: slight bob (body_sway=1, hat_tilt=1, staff sways 1px)
#
# New 4-frame breathing cycle:
#   F0: rest
#   F1: slight sway right (sway=1, staff follows, hat tilts)
#   F2: peak sway (sway=2, staff more, hat tilts more, robe_bob=1)
#   F3: returning (sway=1, mirror of F1)

def generate_idle():
    f0 = base()
    f1 = base(body_sway=1, hat_tilt=1,
              staff_top_x=BASE_STX+1, robe_bob=0,
              left_hand_x=BASE_LHX+1, right_hand_x=BASE_RHX+1)
    f2 = base(body_sway=2, hat_tilt=2,
              staff_top_x=BASE_STX+2, robe_bob=1, orb_bright=0.6,
              left_hand_x=BASE_LHX+1, right_hand_x=BASE_RHX+1)
    f3 = base(body_sway=1, hat_tilt=1,
              staff_top_x=BASE_STX+1, robe_bob=0,
              left_hand_x=BASE_LHX+1, right_hand_x=BASE_RHX+1)

    frames = [make_frame(**p) for p in [f0, f1, f2, f3]]
    return build_strip(frames, 4)


# ════════════════════════════════════════════════════════════════════════════
# WALK — expand 6 → 8 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 6-frame walk used body_sway oscillation ±3px, staff following,
# boot_spread alternating 8-12.
# The 6-frame pattern was:
#   F0: sway L   F1: centre-up  F2: sway R
#   F3: sway L'  F4: centre-up' F5: sway R'
#
# New 8-frame cycle inserts half-step transitions:
#   F0: sway L full (sway=-3, spread=12)
#   F1: half-way L to centre (sway=-2, spread=11)
#   F2: centre/peak-up (sway=0, spread=8, bob=-2)
#   F3: half-way to sway R (sway=2, spread=11)
#   F4: sway R full (sway=3, spread=12)
#   F5: half-way R to centre (sway=2, spread=11)
#   F6: centre/peak-up mirror (sway=0, spread=8, bob=-2)
#   F7: half-way back (sway=-2, spread=11)

def generate_walk():
    params = []
    # Staff tracks body sway: when body sways left, staff tilts slightly too
    for sway, bob, spread, stx_off, hat_t in [
        (-3,  0,  12,  -1, -2),   # F0: sway left
        (-2, -1,  11,  -1, -1),   # F1: transition
        ( 0, -2,   8,   0,  0),   # F2: centre, body up (stride cross)
        ( 2, -1,  11,   1,  1),   # F3: transition to right
        ( 3,  0,  12,   2,  2),   # F4: sway right
        ( 2, -1,  11,   1,  1),   # F5: transition back
        ( 0, -2,   8,   0,  0),   # F6: centre, body up (mirror)
        (-2, -1,  11,  -1, -1),   # F7: transition left
    ]:
        p = base(
                 body_sway=sway, robe_bob=bob, boot_spread=spread,
                 hat_tilt=hat_t,
                 staff_top_x=BASE_STX + stx_off,
                 left_hand_x=BASE_LHX + sway//3,
                 right_hand_x=BASE_RHX + sway//3)
        params.append(p)

    frames = [make_frame(**p) for p in params]
    return build_strip(frames, 8)


# ════════════════════════════════════════════════════════════════════════════
# ATTACK — expand 6 → 8 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 6: F0 idle, F1 lean+raise, F2 wand extend, F3 burst,
#             F4 recoil, F5 recover
#
# New 8: insert tween between F1→F2 and F3→F4:
#   F0: idle stance
#   F1: wand begins to raise (lean=1, staff starts moving up)
#   F2: lean more, staff raising (tween F1→F3)   [NEW]
#   F3: wand fully extended forward
#   F4: burst (magic_burst)
#   F5: post-burst recoil (tween F4→F6)           [NEW]
#   F6: recoil full
#   F7: recovery

def generate_attack():
    # Original keyframe params (re-derived from gen_mage_sprites.py)
    # F0: idle
    p0 = base()

    # F1: lean right 2, wand starts moving to horizontal
    p1 = base(body_sway=2, hat_tilt=1,
              left_hand_x=BASE_LHX+2, left_hand_y=BASE_LHY-3,
              right_hand_x=BASE_RHX+2, right_hand_y=BASE_RHY-2,
              staff_top_x=BASE_STX+4, staff_top_y=BASE_STY+8)

    # F2 (NEW): midpoint between F1 and full extend
    p2 = base(body_sway=3, hat_tilt=2,
              left_hand_x=BASE_LHX+3, left_hand_y=BASE_LHY-6,
              right_hand_x=BASE_RHX+4, right_hand_y=BASE_RHY-5,
              staff_top_x=BASE_STX+10, staff_top_y=BASE_STY+14,
              orb_bright=0.7)

    # F3: wand extended forward (staff points mostly right, orb near right edge)
    p3 = base(body_sway=4, hat_tilt=2,
              left_hand_x=BASE_LHX+4, left_hand_y=BASE_LHY-8,
              right_hand_x=BASE_RHX+6, right_hand_y=BASE_RHY-8,
              staff_top_x=BASE_CX + 24, staff_top_y=BASE_STY+18,
              orb_bright=0.9)

    # F4: burst
    burst_x = BASE_CX + 52
    burst_y = BASE_WAIST + 8
    p4 = base(body_sway=4, hat_tilt=3,
              left_hand_x=BASE_LHX+4, left_hand_y=BASE_LHY-8,
              right_hand_x=BASE_RHX+6, right_hand_y=BASE_RHY-8,
              staff_top_x=BASE_CX + 24, staff_top_y=BASE_STY+18,
              orb_bright=1.0,
              magic_burst_x=burst_x, magic_burst_y=burst_y, magic_burst_size=25)

    # F5 (NEW): post-burst, staff starting to recoil, orb dim
    p5 = base(body_sway=3, hat_tilt=2,
              left_hand_x=BASE_LHX+3, left_hand_y=BASE_LHY-5,
              right_hand_x=BASE_RHX+4, right_hand_y=BASE_RHY-4,
              staff_top_x=BASE_CX + 12, staff_top_y=BASE_STY+10,
              orb_bright=0.6)

    # F6: full recoil
    p6 = base(body_sway=1, hat_tilt=1,
              left_hand_x=BASE_LHX+1, left_hand_y=BASE_LHY+2,
              right_hand_x=BASE_RHX+1, right_hand_y=BASE_RHY+2,
              staff_top_x=BASE_STX+2, staff_top_y=BASE_STY+4,
              orb_bright=0.3)

    # F7: recovery
    p7 = base(orb_bright=0.5)

    params = [p0, p1, p2, p3, p4, p5, p6, p7]
    frames = [make_frame(**p) for p in params]
    return build_strip(frames, 8)


# ════════════════════════════════════════════════════════════════════════════
# HIT — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4:
#   F0: pre-impact (normal stance)
#   F1: impact (rock back, half_closed eyes, hat tilts)
#   F2: max recoil (body sways further)
#   F3: recovery
#
# New 6: add micro-anticipation and multi-step recovery:
#   F0: micro-lean-in (eyes open)
#   F1: impact (hit snap, eyes half_closed)
#   F2: max recoil (furthest back)
#   F3: recoil mid (coming back)    [NEW]
#   F4: recovery near-idle
#   F5: settled back to idle        [NEW]

def generate_hit():
    p0 = base(body_sway=2, hat_tilt=1,
              staff_top_x=BASE_STX+1)  # slight lean-in anticipation

    p1 = base(body_sway=-4, hat_tilt=-3, robe_bob=2,
              left_hand_x=BASE_LHX-2, right_hand_x=BASE_RHX-2,
              staff_top_x=BASE_STX-3, staff_top_y=BASE_STY-2,
              orb_bright=0.2, eyes_open=False, half_closed=True)

    p2 = base(body_sway=-6, hat_tilt=-5, robe_bob=3,
              left_hand_x=BASE_LHX-3, right_hand_x=BASE_RHX-3,
              staff_top_x=BASE_STX-5, staff_top_y=BASE_STY-3,
              orb_bright=0.1, eyes_open=False, half_closed=True)

    p3 = base(body_sway=-4, hat_tilt=-3, robe_bob=2,
              left_hand_x=BASE_LHX-2, right_hand_x=BASE_RHX-2,
              staff_top_x=BASE_STX-2, staff_top_y=BASE_STY-1,
              orb_bright=0.25, eyes_open=False, half_closed=True)  # NEW

    p4 = base(body_sway=-2, hat_tilt=-1,
              staff_top_x=BASE_STX-1,
              orb_bright=0.35)

    p5 = base()  # settled, back to idle

    params = [p0, p1, p2, p3, p4, p5]
    frames = [make_frame(**p) for p in params]
    return build_strip(frames, 6)


# ════════════════════════════════════════════════════════════════════════════
# DEAD — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4:
#   F0: stagger (slight tilt, body normal-ish)
#   F1: falling (more tilt)
#   F2: collapsed (mostly prone)
#   F3: fully prone
#
# New 6: smoother fall arc with 2 more intermediate angles:
#   F0: stagger (dead_rot=0.1)
#   F1: early fall (dead_rot=0.3)   [NEW]
#   F2: mid fall (dead_rot=0.6)
#   F3: late fall (dead_rot=1.0)    [NEW]
#   F4: collapsed (dead_rot=1.3)
#   F5: fully prone (dead_rot=pi/2=1.57)

def generate_dead():
    rots = [0.1, 0.3, 0.6, 1.0, 1.3, math.pi / 2]
    hat_x_offsets = [BASE_CX - 5, BASE_CX - 8, BASE_CX - 14, BASE_CX - 22, BASE_CX - 28, BASE_CX - 35]
    hat_y_offsets = [BASE_FY - 5, BASE_FY - 2, BASE_FY, BASE_FY, BASE_FY, BASE_FY]

    frames = []
    for i, rot in enumerate(rots):
        p = dict(
            dead=True, dead_rot=rot,
            cx=BASE_CX, foot_y=BASE_FY,
            hat_off_x=hat_x_offsets[i],
            hat_off_y=hat_y_offsets[i],
            orb_bright=max(0.0, 0.5 - rot * 0.3),
        )
        frames.append(make_frame(**p))
    return build_strip(frames, 6)


# ════════════════════════════════════════════════════════════════════════════
# CAST — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4:
#   F0: resting with magic_circle starting to glow
#   F1: arms raising, circle grows, staff raised
#   F2: full cast - staff up, magic_burst
#   F3: follow-through, ring fading
#
# New 6: smoother wind-up and release:
#   F0: idle stance, no effects
#   F1: slight raise, tiny circle starting   [NEW smoothing]
#   F2: mid raise, circle forming
#   F3: arms peak, staff fully raised
#   F4: release burst
#   F5: follow-through, settling

def generate_cast():
    # F0: idle stance (no effects yet)
    p0 = base()

    # F1: body starts to lean, staff begins rising (new gentle intro)
    p1 = base(body_sway=-1, hat_tilt=-1,
              left_hand_x=BASE_LHX, left_hand_y=BASE_LHY-5,
              right_hand_x=BASE_RHX+2, right_hand_y=BASE_RHY-8,
              staff_top_x=BASE_STX-2, staff_top_y=BASE_STY-8,
              orb_bright=0.6,
              magic_circle_x=BASE_CX-12, magic_circle_y=BASE_WAIST+5,
              magic_circle_r=10)

    # F2: mid wind-up, circle visible
    p2 = base(body_sway=-2, hat_tilt=-2,
              left_hand_x=BASE_LHX-2, left_hand_y=BASE_LHY-10,
              right_hand_x=BASE_RHX+3, right_hand_y=BASE_RHY-15,
              staff_top_x=BASE_STX-4, staff_top_y=BASE_STY-14,
              orb_bright=0.8,
              magic_circle_x=BASE_CX-15, magic_circle_y=BASE_WAIST+2,
              magic_circle_r=16)

    # F3: peak wind-up, staff overhead
    p3 = base(body_sway=-2, hat_tilt=-3,
              left_hand_x=BASE_LHX-3, left_hand_y=BASE_LHY-18,
              right_hand_x=BASE_RHX+4, right_hand_y=BASE_RHY-20,
              staff_top_x=BASE_CX-8, staff_top_y=BASE_WAIST-70,
              orb_bright=1.0)

    # F4: release — burst
    burst_y = BASE_WAIST - 45
    burst_x = BASE_CX
    p4 = base(body_sway=-1, hat_tilt=-2,
              left_hand_x=BASE_LHX-2, left_hand_y=BASE_LHY-16,
              right_hand_x=BASE_RHX+3, right_hand_y=BASE_RHY-18,
              staff_top_x=BASE_CX-8, staff_top_y=BASE_WAIST-70,
              orb_bright=1.0,
              magic_burst_x=burst_x, magic_burst_y=burst_y, magic_burst_size=22)

    # F5: follow-through, settling
    p5 = base(body_sway=1, hat_tilt=1,
              left_hand_x=BASE_LHX+1, left_hand_y=BASE_LHY-4,
              right_hand_x=BASE_RHX+1, right_hand_y=BASE_RHY-5,
              staff_top_x=BASE_STX+2, staff_top_y=BASE_STY+5,
              orb_bright=0.4)

    params = [p0, p1, p2, p3, p4, p5]
    frames = [make_frame(**p) for p in params]
    return build_strip(frames, 6)


# ════════════════════════════════════════════════════════════════════════════
# VICTORY — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4:
#   F0: staff raised slightly, lean right
#   F1: staff raising, orb brightening
#   F2: staff fully up, big sparkle, orb max bright
#   F3: hold, body bounces slightly
#
# New 6: more expressive arc with arm reaching up:
#   F0: starting - body leans right, staff begins to rise
#   F1: mid rise - staff halfway up                          [NEW tween]
#   F2: three-quarters up, orb glowing
#   F3: peak - staff fully raised, full orb blast
#   F4: slight bounce hold (up)                             [NEW second beat]
#   F5: settle - orb fading slightly, triumphant pose

def generate_victory():
    # F0: starting lean right, staff at normal angle
    p0 = base(body_sway=3, hat_tilt=2,
              right_hand_x=BASE_RHX+4, right_hand_y=BASE_RHY-5,
              staff_top_x=BASE_STX-2, staff_top_y=BASE_STY-5,
              orb_bright=0.6)

    # F1: mid-rise (new tween)
    p1 = base(body_sway=2, hat_tilt=1, robe_bob=-1,
              left_hand_x=BASE_LHX-2, left_hand_y=BASE_LHY-12,
              right_hand_x=BASE_RHX+3, right_hand_y=BASE_RHY-8,
              staff_top_x=BASE_STX-4, staff_top_y=BASE_STY-20,
              orb_bright=0.75)

    # F2: three-quarters raised
    p2 = base(body_sway=1, hat_tilt=0, robe_bob=-2,
              left_hand_x=BASE_LHX-4, left_hand_y=BASE_LHY-22,
              right_hand_x=BASE_RHX+2, right_hand_y=BASE_RHY-14,
              staff_top_x=BASE_STX-6, staff_top_y=BASE_STY-36,
              orb_bright=0.9)

    # F3: peak - staff up, orb blast
    burst_x = BASE_STX - 8
    burst_y  = BASE_STY - 52
    p3 = base(body_sway=0, hat_tilt=-1, robe_bob=-3,
              left_hand_x=BASE_LHX-6, left_hand_y=BASE_LHY-32,
              right_hand_x=BASE_RHX+2, right_hand_y=BASE_RHY-18,
              staff_top_x=BASE_STX-8, staff_top_y=BASE_STY-52,
              orb_bright=1.0,
              magic_burst_x=burst_x, magic_burst_y=burst_y, magic_burst_size=18)

    # F4: bounce up (new second beat)
    p4 = base(body_sway=0, hat_tilt=-2, robe_bob=-4,
              left_hand_x=BASE_LHX-6, left_hand_y=BASE_LHY-34,
              right_hand_x=BASE_RHX+2, right_hand_y=BASE_RHY-20,
              staff_top_x=BASE_STX-8, staff_top_y=BASE_STY-56,
              orb_bright=1.0)

    # F5: settle, orb fading but still victorious
    p5 = base(body_sway=1, hat_tilt=0, robe_bob=-2,
              left_hand_x=BASE_LHX-5, left_hand_y=BASE_LHY-28,
              right_hand_x=BASE_RHX+2, right_hand_y=BASE_RHY-16,
              staff_top_x=BASE_STX-7, staff_top_y=BASE_STY-44,
              orb_bright=0.8)

    params = [p0, p1, p2, p3, p4, p5]
    frames = [make_frame(**p) for p in params]
    return build_strip(frames, 6)


# ════════════════════════════════════════════════════════════════════════════
# VALIDATION
# ════════════════════════════════════════════════════════════════════════════

def validate_strip(strip, name, expected_frames, expected_w, expected_h=FRAME_H):
    import numpy as np
    assert strip.width  == expected_w, f"{name}: width {strip.width} != {expected_w}"
    assert strip.height == expected_h, f"{name}: height {strip.height} != {expected_h}"
    arr = np.array(strip)
    for i in range(expected_frames):
        frame = arr[:, i * FRAME_W:(i+1) * FRAME_W, :]
        opaque = int((frame[:, :, 3] > 10).sum())
        assert opaque >= 500, f"{name} frame {i}: only {opaque} opaque pixels"
    print(f"  {name}: {expected_w}x{expected_h}, {expected_frames} frames — PASS")


# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════

def main():
    print("=== Mage sprite animation upgrade (expanded frame counts) ===\n")

    print("Generating IDLE (4 frames, 1024x256)...")
    idle = generate_idle()
    idle.save(OUT_DIR / "idle.png")
    validate_strip(idle, "idle", 4, FRAME_W * 4)

    print("Generating WALK (8 frames, 2048x256)...")
    walk = generate_walk()
    walk.save(OUT_DIR / "walk.png")
    validate_strip(walk, "walk", 8, FRAME_W * 8)

    print("Generating ATTACK (8 frames, 2048x256)...")
    attack = generate_attack()
    attack.save(OUT_DIR / "attack.png")
    validate_strip(attack, "attack", 8, FRAME_W * 8)

    print("Generating HIT (6 frames, 1536x256)...")
    hit = generate_hit()
    hit.save(OUT_DIR / "hit.png")
    validate_strip(hit, "hit", 6, FRAME_W * 6)

    print("Generating DEAD (6 frames, 1536x256)...")
    dead = generate_dead()
    dead.save(OUT_DIR / "dead.png")
    validate_strip(dead, "dead", 6, FRAME_W * 6)

    print("Generating CAST (6 frames, 1536x256)...")
    cast = generate_cast()
    cast.save(OUT_DIR / "cast.png")
    validate_strip(cast, "cast", 6, FRAME_W * 6)

    print("Generating VICTORY (6 frames, 1536x256)...")
    victory = generate_victory()
    victory.save(OUT_DIR / "victory.png")
    validate_strip(victory, "victory", 6, FRAME_W * 6)

    print("\n=== Final dimension check ===")
    expected = {
        "idle.png":    (1024, 256),
        "walk.png":    (2048, 256),
        "attack.png":  (2048, 256),
        "hit.png":     (1536, 256),
        "dead.png":    (1536, 256),
        "cast.png":    (1536, 256),
        "victory.png": (1536, 256),
        "defend.png":  (1024, 256),
        "item.png":    (1024, 256),
    }
    all_ok = True
    for fname, (ew, eh) in expected.items():
        fpath = OUT_DIR / fname
        if not fpath.exists():
            print(f"  MISSING: {fname}")
            all_ok = False
            continue
        img = Image.open(fpath)
        ok = img.size == (ew, eh)
        status = "PASS" if ok else f"FAIL (got {img.size})"
        print(f"  {fname}: {ew}x{eh} — {status}")
        if not ok:
            all_ok = False

    print("\nAll done." if all_ok else "\nSome checks FAILED.")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
