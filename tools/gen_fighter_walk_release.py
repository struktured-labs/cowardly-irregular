#!/usr/bin/env python3
"""
Fighter walk cycle - FINAL RELEASE VERSION
- 100% upper body pixels from idle (pixel-perfect verified)
- Legs from idle's two leg shapes (steel + crimson armored)
- Correct shadow at idle's exact ground level (row 160)
- 6 frames: right-fwd, mid, left-fwd, mid, right-fwd, mid
- Output: 1536x256 PNG transparent background
"""

from PIL import Image
import numpy as np

idle = Image.open("/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/idle.png")
idle_rgba = idle.convert("RGBA")
idle_arr = np.array(idle_rgba)
f1_arr = idle_arr[:, :256, :].copy()

# ─── Pixel extraction helpers ────────────────────────────────────────────────
def extract_pixels(arr, y0, y1, x0, x1):
    result = []
    for row in range(y0, y1+1):
        for col in range(x0, x1+1):
            px = tuple(arr[row, col])
            if px[3] > 10:
                result.append((col, row, px))
    return result

def draw_pixels(arr, pixels, dx=0, dy=0, darken=1.0):
    for x, y, col in pixels:
        nx, ny = x + dx, y + dy
        if 0 <= nx < 256 and 0 <= ny < 256:
            if darken < 1.0:
                r = min(255, int(col[0] * darken))
                g = min(255, int(col[1] * darken))
                b = min(255, int(col[2] * darken))
                arr[ny, nx] = (r, g, b, col[3])
            else:
                arr[ny, nx] = col

def normalize(pixels):
    min_x = min(p[0] for p in pixels)
    min_y = min(p[1] for p in pixels)
    return [(x-min_x, y-min_y, c) for x,y,c in pixels], min_x, min_y

# ─── Extract sprite regions ──────────────────────────────────────────────────

# Upper body (head + torso + arms + pauldrons): rows 66-135
upper_body = extract_pixels(f1_arr, 66, 135, 0, 255)

# Sword lower extension: steel pixels far-left in leg region
sword_steel = {
    (174,179,204), (125,129,144), (76,78,86),
    (93,98,110), (51,57,65), (54,61,77), (36,34,52),
}
sword_lower = [(x, y, c) for x, y, c in extract_pixels(f1_arr, 134, 163, 50, 92)
               if c[:3] in sword_steel]

# Steel-armored leg (left cluster, front leg in idle)
left_leg = [(x, y, c) for x, y, c in extract_pixels(f1_arr, 136, 163, 60, 116)
            if not (c[:3] in sword_steel and x < 76)]

# Crimson-armored leg (right cluster, back leg in idle)
right_leg = extract_pixels(f1_arr, 136, 163, 90, 155)

ll_norm, ll_ox, ll_oy = normalize(left_leg)
rl_norm, rl_ox, rl_oy = normalize(right_leg)

ll_w = max(p[0] for p in ll_norm) + 1
rl_w = max(p[0] for p in rl_norm) + 1

print(f"Regions extracted: upper={len(upper_body)}px, sword={len(sword_lower)}px, "
      f"steel_leg={len(ll_norm)}px, crimson_leg={len(rl_norm)}px")
print(f"Leg sizes: steel={ll_w}px wide, crimson={rl_w}px wide")

# ─── Animation parameters ────────────────────────────────────────────────────
BODY_CX   = 103    # hip center x
HIP_Y     = 136    # top of leg region
SHADOW_Y  = 160    # ground level (matches idle row 160 shadow center)
STRIDE    = 16     # leg stride amplitude
DARK      = 0.52   # back-leg darkening factor

# 6 walk frames
# (front_type, front_cx, back_type, back_cx, bob)
walk_frames = [
    ('ll', BODY_CX - STRIDE,     'rl', BODY_CX + STRIDE,     0),   # F0
    ('ll', BODY_CX - STRIDE//3,  'rl', BODY_CX + STRIDE//3,  -2),  # F1
    ('rl', BODY_CX - STRIDE,     'll', BODY_CX + STRIDE,     0),   # F2
    ('rl', BODY_CX - STRIDE//3,  'll', BODY_CX + STRIDE//3,  -2),  # F3
    ('ll', BODY_CX - STRIDE,     'rl', BODY_CX + STRIDE,     0),   # F4
    ('ll', BODY_CX - STRIDE//3,  'rl', BODY_CX + STRIDE//3,  -2),  # F5
]

def get_leg(t): return ll_norm if t == 'll' else rl_norm
def get_w(t):   return ll_w    if t == 'll' else rl_w

def generate_frame(fdata):
    ft, fcx, bt, bcx, bob = fdata
    arr = np.zeros((256, 256, 4), dtype=np.uint8)
    
    fw = get_w(ft); bw = get_w(bt)
    fox = fcx - fw // 2
    box = bcx - bw // 2
    
    # Layer 1: back leg (darkened)
    draw_pixels(arr, get_leg(bt), dx=box, dy=HIP_Y+bob, darken=DARK)
    
    # Layer 2: upper body with bob
    draw_pixels(arr, upper_body, dx=0, dy=bob)
    
    # Layer 3: sword lower extension with bob
    draw_pixels(arr, sword_lower, dx=0, dy=bob)
    
    # Layer 4: front leg (full brightness)
    draw_pixels(arr, get_leg(ft), dx=fox, dy=HIP_Y+bob, darken=1.0)
    
    # Layer 5: ground shadow at correct level
    sy = SHADOW_Y + bob
    stride_gap = abs(fcx - bcx)
    sw = 18 + stride_gap // 3
    for sx in range(-sw, sw+1, 2):
        af = max(0.0, 1.0 - (abs(sx)/sw) ** 1.3)
        alpha = int(72 * af)
        for offs in range(0, 6, 2):
            nx, ny = BODY_CX + sx, sy + offs
            if 0 <= nx < 256 and 0 <= ny < 256:
                if arr[ny, nx, 3] < 10:
                    arr[ny, nx] = (36, 34, 52, alpha)
    
    return Image.fromarray(arr, 'RGBA')

print("\nGenerating frames...")
frames = []
for i, fd in enumerate(walk_frames):
    f = generate_frame(fd)
    frames.append(f)
    print(f"  F{i}: {fd[0]}@{fd[1]} fwd, {fd[2]}@{fd[3]} back, bob={fd[4]}")

# ─── Quality checks ──────────────────────────────────────────────────────────
print("\nQuality validation:")

# 1. Upper body pixel fidelity (frame 0)
wd = np.array(frames[0])
matches = sum(1 for row in range(66,136) for col in range(256)
              if tuple(f1_arr[row,col]) == tuple(wd[row,col]) and f1_arr[row,col,3] > 10)
total = sum(1 for row in range(66,136) for col in range(256) if f1_arr[row,col,3] > 10)
print(f"  Upper body match (F0): {matches}/{total} ({100*matches/total:.1f}%)")

# 2. Overall character bounds per frame
for i, f in enumerate(frames):
    fa = np.array(f)
    alpha = fa[:,:,3]
    rows_w = np.where(np.any(alpha>10, axis=1))[0]
    if len(rows_w):
        print(f"  F{i} bounds: rows {rows_w[0]}-{rows_w[-1]} (h={rows_w[-1]-rows_w[0]+1})")

# 3. Transparent background check
print(f"  Background transparency: {'PASS' if frames[0].getpixel((0,0))[3]==0 else 'FAIL'}")

# ─── Assemble and save ───────────────────────────────────────────────────────
strip = Image.new("RGBA", (1536, 256), (0,0,0,0))
for i, f in enumerate(frames):
    strip.paste(f, (i*256, 0))

assert strip.size == (1536, 256)
assert strip.getpixel((0,0))[3] == 0, "Background not transparent"

out = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/walk.png"
strip.save(out)
print(f"\nSaved to: {out}")
print(f"Size: {strip.size} | Mode: {strip.mode} | Transparent: YES")
