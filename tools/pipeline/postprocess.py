from pathlib import Path

import numpy as np
import torch
from PIL import Image

from .config import FRAME_W, FRAME_H, ANIMATIONS, REFERENCE_DIR


def pixelize_frame(img: Image.Image, pixel_size: int = 12, num_colors: int = 32,
                   use_pixeloe: bool = True, pixeloe_quant: bool = False) -> Image.Image:
    """Apply PixelOE pixelization then upscale back to target frame size.

    pixel_size: how many input pixels become 1 pixel art pixel.
                For 768->64 effective resolution, use 12 (768/64=12).
    """
    try:
        if not use_pixeloe:
            raise RuntimeError("PixelOE disabled, using manual downscale")
        from pixeloe.torch.pixelize import pixelize

        arr = np.array(img.convert("RGB"))
        tensor = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).float() / 255.0
        tensor = tensor.cuda()

        pix_kwargs = dict(pixel_size=pixel_size, thickness=1, mode="contrast")
        if pixeloe_quant:
            pix_kwargs.update(do_quant=True, num_colors=num_colors, quant_mode="kmeans")
        else:
            pix_kwargs["do_quant"] = False
        result = pixelize(tensor, **pix_kwargs)

        out_arr = (result.squeeze(0).permute(1, 2, 0).cpu().numpy() * 255).astype(np.uint8)
        pix_img = Image.fromarray(out_arr)

        final = pix_img.resize((FRAME_W, FRAME_H), Image.NEAREST)
        return final
    except Exception as e:
        print(f"  PixelOE failed ({e}), using manual downscale")
        import traceback; traceback.print_exc()
        effective = img.size[0] // pixel_size
        intermediate = effective * 2
        smooth = img.resize((intermediate, intermediate), Image.LANCZOS)
        small = smooth.resize((effective, effective), Image.BOX)
        small = small.quantize(colors=num_colors, method=Image.Quantize.MEDIANCUT).convert("RGBA")
        return small.resize((FRAME_W, FRAME_H), Image.NEAREST)


def extract_reference_palette(source_path: str = None) -> set:
    """Extract palette from a reference image or artist's fighter sprites.

    If source_path is given (e.g. hero_reference.png), extract from that.
    Otherwise fall back to fighter sprite sheets.
    """
    from collections import Counter
    all_colors = Counter()

    if source_path and Path(source_path).exists():
        img = Image.open(source_path).convert("RGBA")
        arr = np.array(img)
        mask = arr[:, :, 3] > 10
        pixels = arr[mask][:, :3]
        for p in pixels:
            all_colors[tuple(int(c) for c in p)] += 1
        print(f"  Extracted {len(all_colors)} colors from {source_path}")
    else:
        for anim in ANIMATIONS:
            path = REFERENCE_DIR / f"{anim}.png"
            if path.exists():
                img = Image.open(path).convert("RGBA")
                arr = np.array(img)
                mask = arr[:, :, 3] > 10
                pixels = arr[mask][:, :3]
                for p in pixels:
                    all_colors[tuple(int(c) for c in p)] += 1

    min_count = max(1, len(all_colors) * 0.001)
    return set(c for c, cnt in all_colors.items() if cnt >= min_count)


def snap_to_palette(img: Image.Image, palette: set, threshold: float = 60.0) -> Image.Image:
    """Snap colors to nearest reference palette color.

    Higher threshold = more aggressive snapping (forces artist's colors).
    """
    arr = np.array(img.convert("RGBA"))
    palette_arr = np.array(list(palette))

    mask = arr[:, :, 3] > 10
    ys, xs = np.where(mask)

    for y, x in zip(ys, xs):
        c = arr[y, x, :3].astype(float)
        dists = np.sqrt(((palette_arr - c) ** 2).sum(axis=1))
        min_idx = dists.argmin()
        if dists[min_idx] < threshold:
            arr[y, x, :3] = palette_arr[min_idx]

    return Image.fromarray(arr)


def remove_background(img: Image.Image, tolerance: int = 35) -> Image.Image:
    """Remove background using flood-fill from all edges.

    Strategy: sample the entire border (all 4 edges), find the dominant
    color(s), then flood-fill from every border pixel that matches.
    This handles non-uniform backgrounds (slight gradients, dither patterns).
    """
    from scipy import ndimage
    from collections import Counter

    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]
    rgb = arr[:, :, :3].astype(float)

    border_pixels = []
    for x in range(w):
        border_pixels.append(rgb[0, x])
        border_pixels.append(rgb[1, x])
        border_pixels.append(rgb[h-1, x])
        border_pixels.append(rgb[h-2, x])
    for y in range(h):
        border_pixels.append(rgb[y, 0])
        border_pixels.append(rgb[y, 1])
        border_pixels.append(rgb[y, w-1])
        border_pixels.append(rgb[y, w-2])

    border_arr = np.array(border_pixels)

    border_tuples = [tuple(int(v) for v in p) for p in border_arr]
    color_counts = Counter(border_tuples)

    min_count = len(border_tuples) * 0.03
    bg_colors = [np.array(c) for c, cnt in color_counts.items() if cnt > min_count]

    if not bg_colors:
        bg_colors = [np.array(color_counts.most_common(1)[0][0])]

    bg_mask = np.zeros((h, w), dtype=bool)
    for bg_color in bg_colors:
        dist = np.sqrt(((rgb - bg_color.astype(float)) ** 2).sum(axis=2))
        bg_mask |= (dist < tolerance)

    labeled, n_labels = ndimage.label(bg_mask)

    edge_labels = set()
    edge_labels.update(labeled[0, :].flatten())
    edge_labels.update(labeled[-1, :].flatten())
    edge_labels.update(labeled[:, 0].flatten())
    edge_labels.update(labeled[:, -1].flatten())
    edge_labels.discard(0)

    final_bg = np.zeros((h, w), dtype=bool)
    for label_id in edge_labels:
        final_bg |= (labeled == label_id)

    arr[final_bg, 3] = 0
    return Image.fromarray(arr)


def _measure_char_height(img: Image.Image) -> int:
    """Measure the height of the character (bounding box of opaque pixels)."""
    arr = np.array(img)
    mask = arr[:, :, 3] > 10
    if not mask.any():
        return 0
    ys = np.where(mask.any(axis=1))[0]
    return ys[-1] - ys[0] + 1 if len(ys) > 0 else 0


def center_character(img: Image.Image, target_w: int = FRAME_W, target_h: int = FRAME_H,
                     target_char_h: int = None) -> Image.Image:
    """Center the non-transparent character within the target frame size.

    Args:
        target_char_h: If provided, scale character to this exact pixel height.
                       Used for cross-frame normalization.
    """
    arr = np.array(img)
    mask = arr[:, :, 3] > 10

    if not mask.any():
        return img

    ys, xs = np.where(mask)
    y_min, y_max = ys.min(), ys.max()
    x_min, x_max = xs.min(), xs.max()

    cropped = arr[y_min:y_max+1, x_min:x_max+1]
    ch, cw = cropped.shape[:2]

    if target_char_h and ch > 0:
        scale = target_char_h / ch
        scale = min(scale, 2.0, (target_h * 0.85) / ch, (target_w * 0.70) / cw)
        scale = max(scale, 0.3)
    else:
        max_char_h = int(target_h * 0.85)
        max_char_w = int(target_w * 0.70)
        scale = min(max_char_w / max(1, cw), max_char_h / max(1, ch), 1.0)

    if abs(scale - 1.0) > 0.01:
        new_w = max(1, int(cw * scale))
        new_h = max(1, int(ch * scale))
        cropped_img = Image.fromarray(cropped).resize((new_w, new_h), Image.NEAREST)
        cropped = np.array(cropped_img)
        ch, cw = cropped.shape[:2]

    canvas = np.zeros((target_h, target_w, 4), dtype=np.uint8)
    x_offset = (target_w - cw) // 2
    y_offset = target_h - ch - int(target_h * 0.08)
    y_offset = max(0, min(y_offset, target_h - ch))
    x_offset = max(0, min(x_offset, target_w - cw))

    canvas[y_offset:y_offset+ch, x_offset:x_offset+cw] = cropped

    return Image.fromarray(canvas)
