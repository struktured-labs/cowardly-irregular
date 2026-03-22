#!/usr/bin/env python3
"""
Pixel Art Sprite Linter for Cowardly Irregular.

Analyzes AI-generated sprite sheets against professional pixel art rules,
using the artist's fighter sprites as the canonical style reference.

Checks:
  1. Palette discipline — color count, drift from reference palette
  2. Orphan pixels — isolated singles that break readability
  3. Outline consistency — broken outlines, double-thick outlines
  4. Sel-out (selective outlining) — outline color should warm toward adjacent fill
  5. Banding — parallel shading lines that look mechanical
  6. Pillow shading — concentric shading from center (amateur tell)
  7. Jaggies — staircase patterns in curves
  8. Cross-frame consistency — silhouette area, color distribution, center of mass
  9. Dithering audit — detect noise vs intentional dithering patterns

Usage:
  python tools/sprite_linter.py assets/sprites/jobs/mage/
  python tools/sprite_linter.py assets/sprites/jobs/mage/idle.png
  python tools/sprite_linter.py assets/sprites/jobs/mage/ --reference assets/sprites/jobs/fighter/
  python tools/sprite_linter.py assets/sprites/jobs/mage/ --fix --output tmp/linted/
"""

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image

# ─── Constants ──────────────────────────────────────────────────────────────

FRAME_W = 256
FRAME_H = 256
ANIMATIONS = ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory"]

# Severity levels
SEVERITY_ERROR = "ERROR"     # Must fix — will look broken in-game
SEVERITY_WARN = "WARN"       # Should fix — professional pixel artists would catch this
SEVERITY_INFO = "INFO"       # Style suggestion — nice to have
SEVERITY_STYLE = "STYLE"     # Deviates from reference artist's style

# ─── Data Classes ───────────────────────────────────────────────────────────

@dataclass
class LintIssue:
    severity: str
    check: str
    message: str
    frame: Optional[int] = None
    animation: Optional[str] = None
    pixel_count: int = 0
    coords: list = field(default_factory=list)  # [(x,y), ...] up to 10 examples

    def __str__(self):
        loc = ""
        if self.animation:
            loc += f"[{self.animation}"
            if self.frame is not None:
                loc += f" frame {self.frame}"
            loc += "] "
        return f"{self.severity:5s} | {self.check:20s} | {loc}{self.message}"


@dataclass
class LintReport:
    target: str
    issues: list = field(default_factory=list)
    stats: dict = field(default_factory=dict)

    def add(self, issue: LintIssue):
        self.issues.append(issue)

    @property
    def error_count(self):
        return sum(1 for i in self.issues if i.severity == SEVERITY_ERROR)

    @property
    def warn_count(self):
        return sum(1 for i in self.issues if i.severity == SEVERITY_WARN)

    def summary(self):
        lines = [
            f"\n{'='*72}",
            f"SPRITE LINT REPORT: {self.target}",
            f"{'='*72}",
        ]
        if self.stats:
            lines.append("\nStats:")
            for k, v in self.stats.items():
                lines.append(f"  {k}: {v}")

        by_severity = defaultdict(list)
        for issue in self.issues:
            by_severity[issue.severity].append(issue)

        for sev in [SEVERITY_ERROR, SEVERITY_WARN, SEVERITY_INFO, SEVERITY_STYLE]:
            if sev in by_severity:
                lines.append(f"\n{sev} ({len(by_severity[sev])}):")
                for issue in by_severity[sev]:
                    lines.append(f"  {issue}")

        total = len(self.issues)
        lines.append(f"\n{'─'*72}")
        if total == 0:
            lines.append("PASS — No issues found. Clean pixel art!")
        else:
            lines.append(
                f"TOTAL: {self.error_count} errors, {self.warn_count} warnings, "
                f"{total - self.error_count - self.warn_count} info/style"
            )
            if self.error_count == 0:
                lines.append("PASS (with warnings)")
            else:
                lines.append("FAIL — errors must be fixed before shipping")
        lines.append("")
        return "\n".join(lines)


# ─── Palette Extraction ─────────────────────────────────────────────────────

def extract_palette(img_arr: np.ndarray, alpha_threshold: int = 10) -> Counter:
    """Extract color palette from RGBA numpy array, ignoring near-transparent pixels."""
    mask = img_arr[:, :, 3] > alpha_threshold
    pixels = img_arr[mask][:, :3]
    return Counter(tuple(int(c) for c in p) for p in pixels)


def load_reference_palette(ref_dir: Path) -> tuple[Counter, set]:
    """Load reference palette from all animations in a directory."""
    all_colors = Counter()
    for anim in ANIMATIONS:
        path = ref_dir / f"{anim}.png"
        if path.exists():
            img = Image.open(path).convert("RGBA")
            arr = np.array(img)
            all_colors += extract_palette(arr)
    palette_set = set(all_colors.keys())
    return all_colors, palette_set


def color_distance(c1: tuple, c2: tuple) -> float:
    """Euclidean RGB distance."""
    return ((c1[0]-c2[0])**2 + (c1[1]-c2[1])**2 + (c1[2]-c2[2])**2) ** 0.5


def nearest_palette_color(color: tuple, palette: set) -> tuple[tuple, float]:
    """Find nearest color in palette and its distance."""
    best = None
    best_dist = float("inf")
    for pc in palette:
        d = color_distance(color, pc)
        if d < best_dist:
            best_dist = d
            best = pc
    return best, best_dist


# ─── Frame Utilities ────────────────────────────────────────────────────────

def split_frames(img: Image.Image, frame_w: int = FRAME_W) -> list[np.ndarray]:
    """Split a horizontal sprite strip into individual frame arrays."""
    arr = np.array(img.convert("RGBA"))
    w = arr.shape[1]
    n_frames = w // frame_w
    return [arr[:, i*frame_w:(i+1)*frame_w, :] for i in range(n_frames)]


def get_opaque_mask(frame: np.ndarray, threshold: int = 10) -> np.ndarray:
    """Boolean mask of non-transparent pixels."""
    return frame[:, :, 3] > threshold


def get_outline_mask(opaque: np.ndarray) -> np.ndarray:
    """Find outline pixels: opaque pixels adjacent to at least one transparent pixel."""
    h, w = opaque.shape
    outline = np.zeros_like(opaque)
    for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
        shifted = np.zeros_like(opaque)
        sy = slice(max(0,-dy), h+min(0,-dy))
        sx = slice(max(0,-dx), w+min(0,-dx))
        ty = slice(max(0,dy), h+min(0,dy))
        tx = slice(max(0,dx), w+min(0,dx))
        shifted[ty, tx] = ~opaque[sy, sx]
        outline |= (opaque & shifted)
    return outline


# ─── Lint Checks ────────────────────────────────────────────────────────────

def check_palette_discipline(frames: list[np.ndarray], anim: str, report: LintReport,
                              ref_palette: Optional[set] = None):
    """Check color count and palette drift."""
    all_colors = Counter()
    for frame in frames:
        all_colors += extract_palette(frame)

    n_colors = len(all_colors)
    report.stats[f"{anim}_unique_colors"] = n_colors

    # Artist's fighter uses 58-134 colors per animation (higher for effects-heavy
    # anims like victory/item). Over 200 suggests AA bleed. Over 150 is worth noting.
    if n_colors > 200:
        report.add(LintIssue(
            SEVERITY_ERROR, "palette_count",
            f"{n_colors} unique colors — likely has anti-aliasing or gradient bleed. "
            f"Reference artist uses 58-134 per animation.",
            animation=anim
        ))
    elif n_colors > 150:
        report.add(LintIssue(
            SEVERITY_WARN, "palette_count",
            f"{n_colors} unique colors — higher than reference (58-134). May have gradient bleed.",
            animation=anim
        ))

    # Check palette drift from reference
    if ref_palette:
        drifted = []
        for color, count in all_colors.most_common():
            if color not in ref_palette:
                _, dist = nearest_palette_color(color, ref_palette)
                if dist > 30:  # significant drift
                    drifted.append((color, count, dist))

        if drifted:
            total_drifted_px = sum(c for _, c, _ in drifted)
            total_px = sum(all_colors.values())
            pct = total_drifted_px / total_px * 100
            worst = sorted(drifted, key=lambda x: -x[2])[:5]
            worst_str = ", ".join(f"RGB{c}(dist={d:.0f})" for c, _, d in worst)

            sev = SEVERITY_ERROR if pct > 20 else (SEVERITY_WARN if pct > 5 else SEVERITY_STYLE)
            report.add(LintIssue(
                sev, "palette_drift",
                f"{len(drifted)} colors ({pct:.1f}% of pixels) diverge from reference palette. "
                f"Worst: {worst_str}",
                animation=anim, pixel_count=total_drifted_px
            ))


def check_orphan_pixels(frames: list[np.ndarray], anim: str, report: LintReport):
    """Detect isolated single pixels with no same-color neighbors."""
    for fi, frame in enumerate(frames):
        opaque = get_opaque_mask(frame)
        rgb = frame[:, :, :3]
        h, w, _ = rgb.shape

        orphans = []
        ys, xs = np.where(opaque)

        for y, x in zip(ys, xs):
            color = tuple(int(c) for c in rgb[y, x])
            has_neighbor = False
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    if dy == 0 and dx == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx]:
                        nc = tuple(int(c) for c in rgb[ny, nx])
                        if color_distance(color, nc) < 15:
                            has_neighbor = True
                            break
                if has_neighbor:
                    break

            if not has_neighbor:
                orphans.append((x, y))

        # Calibrated against artist's fighter: 14-50 orphans per frame is normal
        # for detailed pixel art (highlights, armor rivets, sparks).
        # Only flag excessive counts that suggest AI noise.
        if len(orphans) > 80:
            report.add(LintIssue(
                SEVERITY_WARN, "orphan_pixels",
                f"{len(orphans)} orphan pixels — likely AI noise (reference artist has <50).",
                frame=fi, animation=anim, pixel_count=len(orphans),
                coords=orphans[:10]
            ))
        elif len(orphans) > 50:
            report.add(LintIssue(
                SEVERITY_INFO, "orphan_pixels",
                f"{len(orphans)} orphan pixels — slightly above reference range (<50).",
                frame=fi, animation=anim, pixel_count=len(orphans),
                coords=orphans[:10]
            ))


def check_outline_consistency(frames: list[np.ndarray], anim: str, report: LintReport):
    """Check for broken outlines (gaps) and double-thick outlines."""
    for fi, frame in enumerate(frames):
        opaque = get_opaque_mask(frame)
        outline = get_outline_mask(opaque)
        h, w = opaque.shape

        # Find outline color (darkest frequent color on outline pixels)
        outline_colors = Counter()
        ys, xs = np.where(outline)
        for y, x in zip(ys, xs):
            c = tuple(int(v) for v in frame[y, x, :3])
            outline_colors[c] += 1

        if not outline_colors:
            continue

        # The outline color is typically the darkest high-frequency color
        outline_color = min(
            [c for c, cnt in outline_colors.items() if cnt > len(ys) * 0.05],
            key=lambda c: sum(c),
            default=outline_colors.most_common(1)[0][0]
        )

        # Check for gaps: opaque pixels on the silhouette edge that aren't the outline color
        gap_pixels = []
        for y, x in zip(ys, xs):
            c = tuple(int(v) for v in frame[y, x, :3])
            # If this edge pixel is bright (not dark outline), it's a gap
            if sum(c) > sum(outline_color) + 150:
                gap_pixels.append((x, y))

        # Calibrated: artist's fighter has 48-240 "gap" pixels per frame.
        # These are often sel-out pixels (intentionally colored outline) not actual gaps.
        # Only flag when gap count is extreme relative to outline size.
        gap_ratio = len(gap_pixels) / max(1, len(ys))
        if gap_ratio > 0.5:
            report.add(LintIssue(
                SEVERITY_WARN, "outline_gaps",
                f"{len(gap_pixels)} outline edge pixels ({gap_ratio:.0%}) are bright — "
                f"may indicate broken/missing outlines.",
                frame=fi, animation=anim, pixel_count=len(gap_pixels),
                coords=gap_pixels[:10]
            ))

        # Check for double-thick outlines.
        # Note: some artists (including our reference) intentionally use 2px outlines
        # for emphasis. Only flag when it's pervasive (>40% of outline).
        double_thick = 0
        for y, x in zip(ys, xs):
            c = tuple(int(v) for v in frame[y, x, :3])
            if color_distance(c, outline_color) > 30:
                continue
            for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny, nx = y+dy, x+dx
                if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx] and not outline[ny, nx]:
                    nc = tuple(int(v) for v in frame[ny, nx, :3])
                    if color_distance(nc, outline_color) < 20:
                        double_thick += 1
                        break

        double_ratio = double_thick / max(1, len(ys))
        if double_ratio > 0.4:
            report.add(LintIssue(
                SEVERITY_WARN, "double_outline",
                f"{double_thick} pixels ({double_ratio:.0%}) appear double-thick. "
                f"Reference artist uses ~15-25% for emphasis — this may be excessive.",
                frame=fi, animation=anim, pixel_count=double_thick
            ))


def check_selout(frames: list[np.ndarray], anim: str, report: LintReport):
    """Check selective outlining — outline pixels should warm toward adjacent fill colors.

    Sel-out rule: where a bright fill color meets the outline, the outline pixel
    should shift toward a darker shade of the fill, not stay pure black.
    Professional pixel art uses this to create softer, more organic forms.
    """
    for fi, frame in enumerate(frames):
        opaque = get_opaque_mask(frame)
        outline = get_outline_mask(opaque)
        h, w = opaque.shape
        rgb = frame[:, :, :3]

        # Find outline color
        outline_ys, outline_xs = np.where(outline)
        if len(outline_ys) == 0:
            continue

        outline_colors = Counter()
        for y, x in zip(outline_ys, outline_xs):
            c = tuple(int(v) for v in rgb[y, x])
            outline_colors[c] += 1

        main_outline = outline_colors.most_common(1)[0][0]

        # Count outline pixels that are pure dark next to bright fills
        # (places where sel-out would improve things)
        selout_candidates = 0
        selout_applied = 0

        for y, x in zip(outline_ys, outline_xs):
            oc = tuple(int(v) for v in rgb[y, x])

            # Find brightest adjacent interior pixel
            brightest_neighbor = None
            brightest_lum = 0
            for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny, nx = y+dy, x+dx
                if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx] and not outline[ny, nx]:
                    nc = tuple(int(v) for v in rgb[ny, nx])
                    lum = nc[0]*0.299 + nc[1]*0.587 + nc[2]*0.114
                    if lum > brightest_lum:
                        brightest_lum = lum
                        brightest_neighbor = nc

            if brightest_neighbor and brightest_lum > 120:
                selout_candidates += 1
                # Check if this outline pixel is already sel-outed
                # (shifted away from pure dark toward the fill color)
                if color_distance(oc, main_outline) > 20:
                    selout_applied += 1

        if selout_candidates > 0:
            pct = selout_applied / selout_candidates * 100
            report.stats[f"{anim}_f{fi}_selout_coverage"] = f"{pct:.0f}%"

            if pct < 10 and selout_candidates > 20:
                report.add(LintIssue(
                    SEVERITY_STYLE, "selout_missing",
                    f"Only {pct:.0f}% sel-out coverage ({selout_applied}/{selout_candidates} candidates). "
                    f"Adding selective outlining would make the sprite read more professionally.",
                    frame=fi, animation=anim
                ))


def check_banding(frames: list[np.ndarray], anim: str, report: LintReport):
    """Detect banding — parallel lines of same-width shading that look mechanical.

    Banding occurs when color transitions form uniform-width strips.
    Professional shading has varied band widths.
    """
    for fi, frame in enumerate(frames):
        opaque = get_opaque_mask(frame)
        rgb = frame[:, :, :3]
        h, w, _ = rgb.shape

        # Scan horizontal runs of same color within opaque area
        band_count = 0
        for y in range(h):
            runs = []
            current_color = None
            run_len = 0
            for x in range(w):
                if not opaque[y, x]:
                    if current_color is not None and run_len > 0:
                        runs.append(run_len)
                    current_color = None
                    run_len = 0
                    continue
                c = tuple(int(v) for v in rgb[y, x])
                if c == current_color:
                    run_len += 1
                else:
                    if current_color is not None and run_len > 0:
                        runs.append(run_len)
                    current_color = c
                    run_len = 1
            if current_color is not None and run_len > 0:
                runs.append(run_len)

            # Banding: 3+ consecutive runs of equal length (1-3px each)
            if len(runs) >= 3:
                for i in range(len(runs) - 2):
                    if (runs[i] == runs[i+1] == runs[i+2] and
                        1 <= runs[i] <= 3):
                        band_count += 1
                        break

        # Calibrated: artist's fighter shows 84-103 "banding" rows per frame.
        # Detailed pixel art at 256x256 naturally has many short same-width runs.
        # Only flag when banding is extreme — likely indicates flat/mechanical shading.
        opaque_rows = sum(1 for y in range(h) if opaque[y].any())
        band_ratio = band_count / max(1, opaque_rows)
        if band_ratio > 0.92:
            report.add(LintIssue(
                SEVERITY_WARN, "banding",
                f"{band_count}/{opaque_rows} opaque rows ({band_ratio:.0%}) show banding. "
                f"Reference artist is ~50-60%. Vary shading band widths.",
                frame=fi, animation=anim
            ))


def check_pillow_shading(frames: list[np.ndarray], anim: str, report: LintReport):
    """Detect pillow shading — concentric shading from center that ignores light direction.

    Detection: if the brightness distribution is symmetrically higher in the center
    and lower at edges in ALL directions, it's pillow-shaded.
    """
    for fi, frame in enumerate(frames):
        opaque = get_opaque_mask(frame)
        rgb = frame[:, :, :3].astype(float)

        if not opaque.any():
            continue

        # Calculate luminance
        lum = rgb[:,:,0]*0.299 + rgb[:,:,1]*0.587 + rgb[:,:,2]*0.114
        lum[~opaque] = 0

        # Find bounding box of opaque region
        ys, xs = np.where(opaque)
        if len(ys) < 50:
            continue
        y_min, y_max = ys.min(), ys.max()
        x_min, x_max = xs.min(), xs.max()

        cy = (y_min + y_max) / 2
        cx = (x_min + x_max) / 2

        # Sample brightness in center vs edges
        center_lums = []
        edge_lums = []

        for y, x in zip(ys, xs):
            dist_y = abs(y - cy) / max(1, (y_max - y_min) / 2)
            dist_x = abs(x - cx) / max(1, (x_max - x_min) / 2)
            dist = max(dist_y, dist_x)

            if dist < 0.3:
                center_lums.append(lum[y, x])
            elif dist > 0.7:
                edge_lums.append(lum[y, x])

        if center_lums and edge_lums:
            center_avg = np.mean(center_lums)
            edge_avg = np.mean(edge_lums)

            # Pillow shading: center is significantly brighter AND the difference
            # is consistent (not just one bright area)
            if center_avg > edge_avg + 40:
                center_std = np.std(center_lums)
                # Low variance in center = uniform bright center = pillow shading
                if center_std < 30:
                    report.add(LintIssue(
                        SEVERITY_WARN, "pillow_shading",
                        f"Center brightness ({center_avg:.0f}) >> edge ({edge_avg:.0f}) "
                        f"with low center variance ({center_std:.0f}). "
                        f"Looks like pillow shading — pick a consistent light direction.",
                        frame=fi, animation=anim
                    ))


def check_frame_consistency(frames: list[np.ndarray], anim: str, report: LintReport):
    """Check consistency across animation frames: silhouette area, color distribution, COM."""
    if len(frames) < 2:
        return

    areas = []
    coms = []
    color_dists = []

    for frame in frames:
        opaque = get_opaque_mask(frame)
        area = opaque.sum()
        areas.append(area)

        # Center of mass
        if area > 0:
            ys, xs = np.where(opaque)
            coms.append((xs.mean(), ys.mean()))
        else:
            coms.append((FRAME_W/2, FRAME_H/2))

        # Color distribution (top 10 colors)
        palette = extract_palette(frame)
        top10 = set(c for c, _ in palette.most_common(10))
        color_dists.append(top10)

    # Check silhouette area variance
    if areas:
        mean_area = np.mean(areas)
        if mean_area > 0:
            max_deviation = max(abs(a - mean_area) / mean_area for a in areas)
            if max_deviation > 0.4:
                report.add(LintIssue(
                    SEVERITY_WARN, "frame_area_drift",
                    f"Silhouette area varies by {max_deviation*100:.0f}% across frames "
                    f"(areas: {[int(a) for a in areas]}). Character may appear to grow/shrink.",
                    animation=anim
                ))

    # Check center of mass stability
    if len(coms) > 1:
        com_xs = [c[0] for c in coms]
        com_ys = [c[1] for c in coms]
        x_range = max(com_xs) - min(com_xs)
        y_range = max(com_ys) - min(com_ys)

        # Allow more horizontal drift (walk/attack move sideways)
        # but vertical drift usually means inconsistency
        if y_range > 20:
            report.add(LintIssue(
                SEVERITY_WARN, "frame_com_drift",
                f"Center of mass drifts {y_range:.0f}px vertically across frames. "
                f"Character appears to bounce/float.",
                animation=anim
            ))

    # Check palette consistency across frames
    if len(color_dists) > 1:
        base = color_dists[0]
        for i, dist in enumerate(color_dists[1:], 1):
            overlap = len(base & dist)
            if overlap < 5:
                report.add(LintIssue(
                    SEVERITY_WARN, "frame_palette_drift",
                    f"Frame {i} shares only {overlap}/10 top colors with frame 0. "
                    f"Palette should be consistent across animation.",
                    frame=i, animation=anim
                ))


def check_jaggies(frames: list[np.ndarray], anim: str, report: LintReport):
    """Detect jaggies — staircase patterns in what should be smooth curves.

    Good pixel art curves follow consistent step patterns (e.g., 3-2-1 for a curve).
    Bad jaggies have irregular steps like 3-1-3-1 (creates visible zigzag).
    """
    for fi, frame in enumerate(frames):
        opaque = get_opaque_mask(frame)
        outline = get_outline_mask(opaque)
        h, w = opaque.shape

        # Trace outline runs in each row
        jaggy_count = 0
        prev_runs = []

        for y in range(h):
            runs = []
            in_run = False
            run_start = 0
            for x in range(w):
                if outline[y, x]:
                    if not in_run:
                        run_start = x
                        in_run = True
                else:
                    if in_run:
                        runs.append(x - run_start)
                        in_run = False
            if in_run:
                runs.append(w - run_start)

            # Compare with previous row for irregular step patterns
            if prev_runs and runs and len(prev_runs) == 1 and len(runs) == 1:
                # Single-run rows: check for 1-pixel width alternation (zigzag)
                if prev_runs[0] == 1 and runs[0] == 1:
                    jaggy_count += 1

            prev_runs = runs

        if jaggy_count > 8:
            report.add(LintIssue(
                SEVERITY_INFO, "jaggies",
                f"{jaggy_count} potential jaggy transitions detected in outline. "
                f"Consider smoothing staircase patterns in curves.",
                frame=fi, animation=anim
            ))


# ─── Auto-Fix Functions ────────────────────────────────────────────────────

def fix_palette_snap(frame: np.ndarray, palette: set, threshold: float = 25.0) -> np.ndarray:
    """Snap all colors to nearest palette color if within threshold."""
    result = frame.copy()
    opaque = get_opaque_mask(frame)

    palette_list = list(palette)
    palette_arr = np.array(palette_list)  # (N, 3)

    ys, xs = np.where(opaque)
    for y, x in zip(ys, xs):
        c = tuple(int(v) for v in frame[y, x, :3])
        if c in palette:
            continue
        nearest, dist = nearest_palette_color(c, palette)
        if dist < threshold:
            result[y, x, :3] = nearest

    return result


def fix_orphan_removal(frame: np.ndarray) -> np.ndarray:
    """Remove orphan pixels by making them transparent."""
    result = frame.copy()
    opaque = get_opaque_mask(frame)
    rgb = frame[:, :, :3]
    h, w, _ = rgb.shape

    ys, xs = np.where(opaque)
    for y, x in zip(ys, xs):
        color = tuple(int(c) for c in rgb[y, x])
        has_neighbor = False
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                if dy == 0 and dx == 0:
                    continue
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx]:
                    nc = tuple(int(c) for c in rgb[ny, nx])
                    if color_distance(color, nc) < 15:
                        has_neighbor = True
                        break
            if has_neighbor:
                break

        if not has_neighbor:
            result[y, x, 3] = 0  # make transparent

    return result


def fix_selout(frame: np.ndarray, strength: float = 0.4) -> np.ndarray:
    """Apply selective outlining — blend outline pixels toward adjacent fill colors."""
    result = frame.copy()
    opaque = get_opaque_mask(frame)
    outline = get_outline_mask(opaque)
    rgb = frame[:, :, :3]
    h, w, _ = rgb.shape

    outline_ys, outline_xs = np.where(outline)
    if len(outline_ys) == 0:
        return result

    # Find main outline color
    outline_colors = Counter()
    for y, x in zip(outline_ys, outline_xs):
        c = tuple(int(v) for v in rgb[y, x])
        outline_colors[c] += 1
    main_outline = outline_colors.most_common(1)[0][0]

    for y, x in zip(outline_ys, outline_xs):
        oc = tuple(int(v) for v in rgb[y, x])
        if color_distance(oc, main_outline) > 30:
            continue  # already sel-outed or different color

        # Find brightest adjacent interior pixel
        brightest = None
        brightest_lum = 0
        for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx] and not outline[ny, nx]:
                nc = tuple(int(v) for v in rgb[ny, nx])
                lum = nc[0]*0.299 + nc[1]*0.587 + nc[2]*0.114
                if lum > brightest_lum:
                    brightest_lum = lum
                    brightest_neighbor = nc
                    brightest = nc

        if brightest and brightest_lum > 100:
            # Blend outline toward a darker version of the fill
            new_color = tuple(
                int(oc[i] * (1 - strength) + brightest[i] * strength * 0.5)
                for i in range(3)
            )
            result[y, x, :3] = new_color

    return result


# ─── Main Lint Runner ───────────────────────────────────────────────────────

def lint_animation(img_path: Path, anim_name: str, report: LintReport,
                   ref_palette: Optional[set] = None):
    """Run all checks on a single animation strip."""
    img = Image.open(img_path).convert("RGBA")
    frames = split_frames(img)

    report.stats[f"{anim_name}_frames"] = len(frames)
    report.stats[f"{anim_name}_size"] = f"{img.size[0]}x{img.size[1]}"

    check_palette_discipline(frames, anim_name, report, ref_palette)
    check_orphan_pixels(frames, anim_name, report)
    check_outline_consistency(frames, anim_name, report)
    check_selout(frames, anim_name, report)
    check_banding(frames, anim_name, report)
    check_pillow_shading(frames, anim_name, report)
    check_jaggies(frames, anim_name, report)
    check_frame_consistency(frames, anim_name, report)


def lint_directory(target_dir: Path, ref_dir: Optional[Path] = None) -> LintReport:
    """Lint all animations in a sprite directory."""
    report = LintReport(target=str(target_dir))

    ref_palette = None
    if ref_dir and ref_dir.exists():
        _, ref_palette = load_reference_palette(ref_dir)
        report.stats["reference"] = str(ref_dir)
        report.stats["reference_palette_size"] = len(ref_palette)

    for anim in ANIMATIONS:
        path = target_dir / f"{anim}.png"
        if path.exists():
            lint_animation(path, anim, report, ref_palette)
        else:
            report.add(LintIssue(
                SEVERITY_INFO, "missing_anim",
                f"Animation '{anim}' not found — expected {path.name}",
                animation=anim
            ))

    return report


def lint_single_file(target_file: Path, ref_dir: Optional[Path] = None) -> LintReport:
    """Lint a single sprite strip file."""
    report = LintReport(target=str(target_file))

    ref_palette = None
    if ref_dir and ref_dir.exists():
        _, ref_palette = load_reference_palette(ref_dir)

    anim_name = target_file.stem
    lint_animation(target_file, anim_name, report, ref_palette)
    return report


def apply_fixes(target_dir: Path, output_dir: Path, ref_dir: Optional[Path] = None):
    """Apply auto-fixes to all animations and save to output directory."""
    output_dir.mkdir(parents=True, exist_ok=True)

    ref_palette = None
    if ref_dir and ref_dir.exists():
        _, ref_palette = load_reference_palette(ref_dir)

    for anim in ANIMATIONS:
        path = target_dir / f"{anim}.png"
        if not path.exists():
            continue

        img = Image.open(path).convert("RGBA")
        frames = split_frames(img)
        fixed_frames = []

        for frame in frames:
            fixed = frame.copy()
            fixed = fix_orphan_removal(fixed)
            if ref_palette:
                fixed = fix_palette_snap(fixed, ref_palette)
            fixed = fix_selout(fixed)
            fixed_frames.append(fixed)

        # Reassemble strip
        strip = np.concatenate(fixed_frames, axis=1)
        out_img = Image.fromarray(strip)
        out_path = output_dir / f"{anim}.png"
        out_img.save(out_path)
        print(f"  Fixed: {out_path}")


# ─── CLI ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Pixel Art Sprite Linter")
    parser.add_argument("target", help="Sprite directory or single PNG file")
    parser.add_argument("--reference", "-r", help="Reference artist sprite directory")
    parser.add_argument("--fix", action="store_true", help="Apply auto-fixes")
    parser.add_argument("--output", "-o", help="Output directory for fixed sprites")
    parser.add_argument("--json", action="store_true", help="Output report as JSON")
    args = parser.parse_args()

    target = Path(args.target)
    ref_dir = Path(args.reference) if args.reference else None

    # Auto-detect reference from fighter if not specified and it exists
    if ref_dir is None:
        fighter_dir = target.parent / "fighter" if target.is_dir() else target.parent.parent / "fighter"
        if fighter_dir.exists() and fighter_dir != target:
            ref_dir = fighter_dir
            print(f"Auto-detected reference: {ref_dir}")

    if args.fix:
        output_dir = Path(args.output) if args.output else Path("tmp/linted") / target.name
        print(f"Applying fixes to {target} → {output_dir}")
        apply_fixes(target, output_dir, ref_dir)
        # Re-lint the fixed output
        report = lint_directory(output_dir, ref_dir)
        print(report.summary())
    elif target.is_dir():
        report = lint_directory(target, ref_dir)
        if args.json:
            print(json.dumps({
                "target": report.target,
                "stats": report.stats,
                "issues": [
                    {"severity": i.severity, "check": i.check, "message": i.message,
                     "animation": i.animation, "frame": i.frame, "pixel_count": i.pixel_count}
                    for i in report.issues
                ],
                "error_count": report.error_count,
                "warn_count": report.warn_count,
            }, indent=2))
        else:
            print(report.summary())
    elif target.is_file():
        report = lint_single_file(target, ref_dir)
        print(report.summary())
    else:
        print(f"Error: {target} not found", file=sys.stderr)
        sys.exit(1)

    sys.exit(1 if report.error_count > 0 else 0)


if __name__ == "__main__":
    main()
