#!/usr/bin/env python3
from PIL import Image
import os
import sys

mage_dir = '/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/mage'
expected = {
    'idle.png':    (512,  256, 2),
    'walk.png':    (1536, 256, 6),
    'attack.png':  (1536, 256, 6),
    'hit.png':     (1024, 256, 4),
    'dead.png':    (1024, 256, 4),
    'cast.png':    (1024, 256, 4),
    'defend.png':  (1024, 256, 4),
    'item.png':    (1024, 256, 4),
    'victory.png': (1024, 256, 4),
}

all_ok = True
for name, (ew, eh, nf) in expected.items():
    path = os.path.join(mage_dir, name)
    if not os.path.exists(path):
        print(f'MISSING: {name}')
        all_ok = False
        continue
    img = Image.open(path)
    if img.width != ew or img.height != eh:
        print(f'WRONG SIZE: {name} -> {img.width}x{img.height} (expected {ew}x{eh})')
        all_ok = False
    elif img.mode != 'RGBA':
        print(f'WRONG MODE: {name} -> {img.mode}')
        all_ok = False
    else:
        # Check top-left corner of first frame is transparent (background)
        has_transparent_bg = (img.getpixel((0, 0))[3] == 0)
        # Check character pixels exist (some non-transparent pixel in the frame)
        mid_x = ew // (nf * 2)
        mid_y = eh // 2
        has_content = False
        for cy in range(50, eh - 30):
            for cx in range(mid_x - 40, mid_x + 40):
                if img.getpixel((cx, cy))[3] > 0:
                    has_content = True
                    break
            if has_content:
                break
        print(f'OK: {name:14s}  {ew}x{eh}  {nf} frames  RGBA  transparent_bg={has_transparent_bg}  has_content={has_content}')

print()
if all_ok:
    print('All 9 mage sprites pass validation.')
else:
    print('ERRORS found.')
    sys.exit(1)
