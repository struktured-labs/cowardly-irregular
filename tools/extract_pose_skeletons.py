"""
Extract OpenPose skeleton images from artist fighter sprite sheets.

For each animation in the source fighter directory:
  - Split the strip into 256x256 frames
  - Upscale each frame to 768x768 (nearest-neighbor)
  - Try OpenposeDetector; fall back to hand-crafted COCO keypoints on failure
  - Save skeleton PNGs to output_dir/{animation}/frame_{NN}.png
  - Write keypoints.json with COCO-format keypoints for all frames

Usage:
    uv run python tools/extract_pose_skeletons.py [--source-dir ...] [--output-dir ...] [--method auto|detect|manual]
"""

import argparse
import json
import warnings
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# ── OpenPose colour scheme ────────────────────────────────────────────────────
# 18 COCO keypoints: nose(0) neck(1) r_shoulder(2) r_elbow(3) r_wrist(4)
#                    l_shoulder(5) l_elbow(6) l_wrist(7) r_hip(8) r_knee(9)
#                    r_ankle(10) l_hip(11) l_knee(12) l_ankle(13)
#                    r_eye(14) l_eye(15) r_ear(16) l_ear(17)

JOINT_COLORS = {
    "spine":       (85,  170, 255),   # blue:  nose-neck-hip chain
    "right":       (255,  85,  85),   # red:   right side limbs
    "left":        (85,  255,  85),   # green: left side limbs
    "face_right":  (255, 170,  85),   # orange: right eye/ear
    "face_left":   (170, 255,  85),   # yellow-green: left eye/ear
}

LIMB_PAIRS = [
    # spine chain
    (0,  1,  "spine"),
    (1,  8,  "spine"),
    (1,  11, "spine"),
    (8,  11, "spine"),
    # right arm
    (1,  2,  "right"),
    (2,  3,  "right"),
    (3,  4,  "right"),
    # left arm
    (1,  5,  "left"),
    (5,  6,  "left"),
    (6,  7,  "left"),
    # right leg
    (8,  9,  "right"),
    (9,  10, "right"),
    # left leg
    (11, 12, "left"),
    (12, 13, "left"),
    # face
    (0,  14, "face_right"),
    (14, 16, "face_right"),
    (0,  15, "face_left"),
    (15, 17, "face_left"),
]

JOINT_RADIUS = 6
LINE_WIDTH   = 3

# ── Manual keypoints at 768x768 ───────────────────────────────────────────────
# Coordinate system: (x, y) in pixels, origin top-left.
# JRPG battle sprite proportions: character occupies roughly x 200-568, y 80-700.
# Head centre ~y=120, neck ~y=185, shoulders ~y=220, hips ~y=430, knees ~y=570, ankles ~y=680.
# Right = character's right = screen LEFT (standard OpenPose viewer convention).

def _kp(x, y):
    return [x, y, 2]   # 2 = visible

def _build_manual_keypoints():
    """
    Returns dict: animation -> list[frame_keypoints]
    Each frame_keypoints is a list of 18 [x, y, v] entries.
    """
    W, H = 384, 384   # centre of 768x768 canvas

    def idle_frame(lean=0):
        return [
            _kp(W,       120),        # 0  nose
            _kp(W,       185),        # 1  neck
            _kp(W - 80,  220),        # 2  r_shoulder
            _kp(W - 95,  320),        # 3  r_elbow
            _kp(W - 85,  410),        # 4  r_wrist
            _kp(W + 80,  220),        # 5  l_shoulder
            _kp(W + 95,  320),        # 6  l_elbow
            _kp(W + 85,  410),        # 7  l_wrist
            _kp(W - 55,  430),        # 8  r_hip
            _kp(W - 55,  570),        # 9  r_knee
            _kp(W - 55 + lean, 680),  # 10 r_ankle
            _kp(W + 55,  430),        # 11 l_hip
            _kp(W + 55,  570),        # 12 l_knee
            _kp(W + 55 - lean, 680),  # 13 l_ankle
            _kp(W - 20,  100),        # 14 r_eye
            _kp(W + 20,  100),        # 15 l_eye
            _kp(W - 40,  115),        # 16 r_ear
            _kp(W + 40,  115),        # 17 l_ear
        ]

    # walk cycle: weight shift side to side, legs alternating stride
    def walk_frame(phase):
        strides = [
            (-30,  30,  -50,  50),   # r_fwd, r_back, l_fwd, l_back  (ankle offsets)
            (-15,  15,  -25,  25),
            (  0,   0,    0,   0),
            ( 30, -30,   50, -50),
            ( 15, -15,   25, -25),
            (  0,   0,    0,   0),
        ]
        rx, ry, lx, ly = strides[phase % 6]
        body_x = W + int(phase % 2 == 1) * 5   # slight horizontal bob
        return [
            _kp(body_x,         120),
            _kp(body_x,         185),
            _kp(body_x - 80,    220),
            _kp(body_x - 90,    315),
            _kp(body_x - 80,    400 + ry),
            _kp(body_x + 80,    220),
            _kp(body_x + 90,    315),
            _kp(body_x + 80,    400 + ly),
            _kp(body_x - 55,    430),
            _kp(body_x - 55 + rx//2, 565),
            _kp(body_x - 55 + rx,    675),
            _kp(body_x + 55,    430),
            _kp(body_x + 55 + lx//2, 565),
            _kp(body_x + 55 + lx,    675),
            _kp(body_x - 20,    100),
            _kp(body_x + 20,    100),
            _kp(body_x - 40,    115),
            _kp(body_x + 40,    115),
        ]

    def attack_frame(phase):
        # Wind-up → strike forward → follow-through → recover
        configs = [
            # wind-up: lean back, r_arm raised
            dict(bx=W-20, r_elbow=(W-150, 200), r_wrist=(W-130, 130),
                 l_elbow=(W+90, 320), l_wrist=(W+75, 410)),
            # mid swing: body leaning forward
            dict(bx=W,    r_elbow=(W-60,  270), r_wrist=(W+20,  200),
                 l_elbow=(W+85, 310), l_wrist=(W+70, 400)),
            # strike: arm fully extended forward
            dict(bx=W+30, r_elbow=(W+40,  280), r_wrist=(W+150, 300),
                 l_elbow=(W+90, 320), l_wrist=(W+80, 415)),
            # follow: arm crossing past centre
            dict(bx=W+20, r_elbow=(W+80,  310), r_wrist=(W+170, 380),
                 l_elbow=(W+85, 310), l_wrist=(W+75, 405)),
            # recoil
            dict(bx=W+10, r_elbow=(W+30,  330), r_wrist=(W+80,  420),
                 l_elbow=(W+80, 315), l_wrist=(W+65, 410)),
            # recover: back to idle-ish
            dict(bx=W,    r_elbow=(W-95, 320), r_wrist=(W-85,  410),
                 l_elbow=(W+95, 320), l_wrist=(W+85, 410)),
        ]
        c = configs[phase % 6]
        bx = c["bx"]
        return [
            _kp(bx,        120),
            _kp(bx,        185),
            _kp(bx - 80,   220),
            _kp(*c["r_elbow"]),
            _kp(*c["r_wrist"]),
            _kp(bx + 80,   220),
            _kp(*c["l_elbow"]),
            _kp(*c["l_wrist"]),
            _kp(bx - 55,   430),
            _kp(bx - 55,   570),
            _kp(bx - 55,   680),
            _kp(bx + 55,   430),
            _kp(bx + 55,   570),
            _kp(bx + 55,   680),
            _kp(bx - 20,   100),
            _kp(bx + 20,   100),
            _kp(bx - 40,   115),
            _kp(bx + 40,   115),
        ]

    def hit_frame(phase):
        # Recoil backward, stagger, recover
        leans = [30, 50, 35, 15]
        lean = leans[phase % 4]
        return [
            _kp(W + lean,        120),
            _kp(W + lean,        185),
            _kp(W + lean - 75,   220),
            _kp(W + lean - 60,   305),
            _kp(W + lean - 50,   395 - lean),
            _kp(W + lean + 75,   220),
            _kp(W + lean + 90,   310),
            _kp(W + lean + 80,   400 + lean),
            _kp(W + lean - 55,   430),
            _kp(W + lean - 55,   570),
            _kp(W + lean - 55,   680),
            _kp(W + lean + 55,   430),
            _kp(W + lean + 55,   570),
            _kp(W + lean + 55,   680),
            _kp(W + lean - 20,   100),
            _kp(W + lean + 20,   100),
            _kp(W + lean - 40,   115),
            _kp(W + lean + 40,   115),
        ]

    def dead_frame(phase):
        # Falling → collapsed on ground
        drops = [
            (400, 150),   # phase 0: stumbling, upright
            (500, 300),   # phase 1: knees buckling
            (600, 500),   # phase 2: crumpling
            (680, 700),   # phase 3: flat on ground
        ]
        nose_y, neck_y = drops[phase % 4]
        ground = 720
        return [
            _kp(W,  nose_y),
            _kp(W,  neck_y),
            _kp(W - 80, min(neck_y + 40,  ground - 40)),
            _kp(W - 60, min(neck_y + 120, ground - 20)),
            _kp(W + 20, min(neck_y + 180, ground)),
            _kp(W + 80, min(neck_y + 40,  ground - 40)),
            _kp(W + 60, min(neck_y + 120, ground - 20)),
            _kp(W - 20, min(neck_y + 180, ground)),
            _kp(W - 55, min(neck_y + 250, ground)),
            _kp(W - 55, min(neck_y + 370, ground)),
            _kp(W - 30, min(neck_y + 480, ground)),
            _kp(W + 55, min(neck_y + 250, ground)),
            _kp(W + 55, min(neck_y + 370, ground)),
            _kp(W + 30, min(neck_y + 480, ground)),
            _kp(W - 20, max(nose_y - 20, 60)),
            _kp(W + 20, max(nose_y - 20, 60)),
            _kp(W - 40, max(nose_y - 5,  75)),
            _kp(W + 40, max(nose_y - 5,  75)),
        ]

    def cast_frame(phase):
        # Arms raised / gathering energy / releasing
        arm_states = [
            # arms slowly rising
            dict(r_elbow=(W-90, 280), r_wrist=(W-70, 180),
                 l_elbow=(W+90, 280), l_wrist=(W+70, 180)),
            dict(r_elbow=(W-95, 240), r_wrist=(W-80, 130),
                 l_elbow=(W+95, 240), l_wrist=(W+80, 130)),
            # arms held high, gathering
            dict(r_elbow=(W-100, 210), r_wrist=(W-90, 100),
                 l_elbow=(W+100, 210), l_wrist=(W+90, 100)),
            # release: arms thrust forward
            dict(r_elbow=(W-40,  270), r_wrist=(W+60,  230),
                 l_elbow=(W+40,  270), l_wrist=(W-60,  230)),
        ]
        a = arm_states[phase % 4]
        return [
            _kp(W,   120),
            _kp(W,   185),
            _kp(W - 80, 220),
            _kp(*a["r_elbow"]),
            _kp(*a["r_wrist"]),
            _kp(W + 80, 220),
            _kp(*a["l_elbow"]),
            _kp(*a["l_wrist"]),
            _kp(W - 55, 430),
            _kp(W - 55, 570),
            _kp(W - 55, 680),
            _kp(W + 55, 430),
            _kp(W + 55, 570),
            _kp(W + 55, 680),
            _kp(W - 20, 100),
            _kp(W + 20, 100),
            _kp(W - 40, 115),
            _kp(W + 40, 115),
        ]

    def defend_frame(phase):
        # Shield raised, body compact
        shields = [0, 10, 20, 10]
        raise_y = shields[phase % 4]
        return [
            _kp(W,        120),
            _kp(W,        185),
            _kp(W - 85,   215),
            _kp(W - 110,  290 - raise_y),
            _kp(W - 120,  200 - raise_y),   # r_wrist high (shield)
            _kp(W + 75,   225),
            _kp(W + 85,   325),
            _kp(W + 75,   415),
            _kp(W - 60,   435),
            _kp(W - 65,   565),
            _kp(W - 65,   675),
            _kp(W + 50,   435),
            _kp(W + 50,   565),
            _kp(W + 50,   675),
            _kp(W - 20,   100),
            _kp(W + 20,   100),
            _kp(W - 40,   115),
            _kp(W + 40,   115),
        ]

    def item_frame(phase):
        # Reach into bag / pull out item / use / return
        item_poses = [
            dict(r_elbow=(W-85, 310), r_wrist=(W-60, 420)),  # reaching down
            dict(r_elbow=(W-80, 290), r_wrist=(W-50, 370)),  # gripping
            dict(r_elbow=(W-70, 240), r_wrist=(W-40, 150)),  # raising item
            dict(r_elbow=(W-85, 320), r_wrist=(W-75, 415)),  # returning
        ]
        p = item_poses[phase % 4]
        return [
            _kp(W,   120),
            _kp(W,   185),
            _kp(W - 80, 220),
            _kp(*p["r_elbow"]),
            _kp(*p["r_wrist"]),
            _kp(W + 80, 220),
            _kp(W + 90, 320),
            _kp(W + 80, 415),
            _kp(W - 55, 430),
            _kp(W - 55, 570),
            _kp(W - 55, 680),
            _kp(W + 55, 430),
            _kp(W + 55, 570),
            _kp(W + 55, 680),
            _kp(W - 20, 100),
            _kp(W + 20, 100),
            _kp(W - 40, 115),
            _kp(W + 40, 115),
        ]

    def victory_frame(phase):
        # Arms raised in celebration
        raises = [
            dict(r_elbow=(W-90, 200), r_wrist=(W-70, 100),
                 l_elbow=(W+90, 200), l_wrist=(W+70, 100)),
            dict(r_elbow=(W-95, 185), r_wrist=(W-75,  80),
                 l_elbow=(W+95, 185), l_wrist=(W+75,  80)),
            dict(r_elbow=(W-90, 200), r_wrist=(W-70, 100),
                 l_elbow=(W+90, 200), l_wrist=(W+70, 100)),
            dict(r_elbow=(W-85, 210), r_wrist=(W-65, 115),
                 l_elbow=(W+85, 210), l_wrist=(W+65, 115)),
        ]
        r = raises[phase % 4]
        return [
            _kp(W,   115),
            _kp(W,   180),
            _kp(W - 80, 215),
            _kp(*r["r_elbow"]),
            _kp(*r["r_wrist"]),
            _kp(W + 80, 215),
            _kp(*r["l_elbow"]),
            _kp(*r["l_wrist"]),
            _kp(W - 55, 430),
            _kp(W - 55, 565),
            _kp(W - 55, 675),
            _kp(W + 55, 430),
            _kp(W + 55, 565),
            _kp(W + 55, 675),
            _kp(W - 20,  95),
            _kp(W + 20,  95),
            _kp(W - 40, 110),
            _kp(W + 40, 110),
        ]

    frame_counts = {
        "idle":    2,
        "walk":    6,
        "attack":  6,
        "hit":     4,
        "dead":    4,
        "cast":    4,
        "defend":  4,
        "item":    4,
        "victory": 4,
    }

    builders = {
        "idle":    lambda i: idle_frame(lean=i * 8),
        "walk":    walk_frame,
        "attack":  attack_frame,
        "hit":     hit_frame,
        "dead":    dead_frame,
        "cast":    cast_frame,
        "defend":  defend_frame,
        "item":    item_frame,
        "victory": victory_frame,
    }

    result = {}
    for anim, count in frame_counts.items():
        result[anim] = [builders[anim](i) for i in range(count)]
    return result


# ── Rendering ─────────────────────────────────────────────────────────────────

def render_skeleton(keypoints, size=(768, 768)):
    img = Image.new("RGB", size, color=(0, 0, 0))
    draw = ImageDraw.Draw(img)

    visible = [(kp[0], kp[1]) if kp[2] > 0 else None for kp in keypoints]

    for a, b, group in LIMB_PAIRS:
        pa, pb = visible[a], visible[b]
        if pa and pb:
            draw.line([pa, pb], fill=JOINT_COLORS[group], width=LINE_WIDTH)

    for pt in visible:
        if pt:
            x, y = pt
            r = JOINT_RADIUS
            draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255))

    return img


# ── Detection ─────────────────────────────────────────────────────────────────

def try_detect_pose(frame_img):
    """
    Attempt OpenPose detection on a single upscaled frame.
    Returns PIL Image of the skeleton on black background, or None on failure.
    """
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            from controlnet_aux import OpenposeDetector
        detector = OpenposeDetector.from_pretrained("lllyasviel/ControlNet")
        result = detector(
            frame_img,
            detect_resolution=768,
            image_resolution=768,
            include_body=True,
            include_hand=False,
            include_face=False,
            output_type="pil",
        )
        arr = np.array(result)
        if arr.max() < 5:
            return None
        return result
    except Exception:
        return None


# ── Frame extraction ──────────────────────────────────────────────────────────

def split_strip(path, frame_w=256, frame_h=256):
    strip = Image.open(path).convert("RGBA")
    w, h = strip.size
    n = w // frame_w
    frames = []
    for i in range(n):
        box = (i * frame_w, 0, (i + 1) * frame_w, frame_h)
        frames.append(strip.crop(box))
    return frames


# ── Main ──────────────────────────────────────────────────────────────────────

ANIMATIONS = ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory"]


def run(source_dir: Path, output_dir: Path, method: str):
    output_dir.mkdir(parents=True, exist_ok=True)

    manual_kps = _build_manual_keypoints()
    keypoints_out = {}

    for anim in ANIMATIONS:
        sprite_path = source_dir / f"{anim}.png"
        if not sprite_path.exists():
            print(f"  [skip] {anim}.png not found in {source_dir}")
            continue

        frames = split_strip(sprite_path)
        anim_dir = output_dir / anim
        anim_dir.mkdir(parents=True, exist_ok=True)

        keypoints_out[anim] = []
        detected_any = False

        for i, frame in enumerate(frames):
            upscaled = frame.convert("RGB").resize((768, 768), Image.NEAREST)
            skeleton_img = None

            if method in ("auto", "detect"):
                skeleton_img = try_detect_pose(upscaled)
                if skeleton_img is not None:
                    detected_any = True
                    print(f"  [detect] {anim} frame {i}: OpenPose succeeded")

            if skeleton_img is None:
                if method == "detect":
                    print(f"  [warn]   {anim} frame {i}: detection failed, skipping (--method=detect)")
                    keypoints_out[anim].append(None)
                    continue
                kps = manual_kps.get(anim, [])
                if i < len(kps):
                    kp = kps[i]
                else:
                    kp = kps[-1] if kps else []
                skeleton_img = render_skeleton(kp)
                source_label = "manual"
                keypoints_out[anim].append(kp)
                if method == "auto" and not detected_any:
                    print(f"  [manual] {anim} frame {i}: using hand-crafted skeleton")
                else:
                    print(f"  [manual] {anim} frame {i}: detect fallback")
            else:
                keypoints_out[anim].append(None)

            out_path = anim_dir / f"frame_{i:02d}.png"
            skeleton_img.save(str(out_path))

        print(f"  [{anim}] {len(frames)} frames -> {anim_dir}")

    kp_path = output_dir / "keypoints.json"
    with open(str(kp_path), "w") as f:
        json.dump(keypoints_out, f, indent=2)
    print(f"\nKeypoints written to {kp_path}")


def main():
    default_source = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter")
    default_output = Path(__file__).parent / "pose_skeletons"

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=default_source,
                        help="Directory containing fighter animation PNGs")
    parser.add_argument("--output-dir", type=Path, default=default_output,
                        help="Directory to write skeleton PNGs and keypoints.json")
    parser.add_argument("--method", choices=["auto", "detect", "manual"], default="auto",
                        help="auto: try detect then fall back to manual; detect: only OpenPose; manual: only hand-crafted")
    args = parser.parse_args()

    print(f"Source : {args.source_dir}")
    print(f"Output : {args.output_dir}")
    print(f"Method : {args.method}")
    print()
    run(args.source_dir, args.output_dir, args.method)


if __name__ == "__main__":
    main()
