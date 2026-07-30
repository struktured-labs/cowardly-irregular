#!/usr/bin/env python3
"""Structural QA for sprite sheets — severed limbs, garble, silent failures.

struktured 2026-07-28: "make sure cowir-sprites has metrics to know if his
sprites are broken or not before shipping (severed limbs, garbled, etc)."

The existing sprite_linter.py covers STYLE (palette, banding, sel-out,
pillow shading). It does not catch STRUCTURE, and structure is what
actually shipped broken tonight:

  * chromakey silently failed  -> two sheets 100% opaque (the_coordinator,
    the_regulator). Every style check passed; the background was solid.
  * detached blob              -> the_regulator carried an 881px orphan
    beside her in all 8 frames.

Both were caught by eye. That does not scale to a 29-sheet batch, which is
the whole reason this exists.

CHECKS (each is derived from a real failure, not invented):
  ALPHA_OPAQUE   frame has almost no transparent pixels -> chromakey failed
  ALPHA_EMPTY    frame is (near-)entirely transparent   -> lost frame
  DETACHED       a secondary connected component        -> blob / severed limb
  AREA_DROP      silhouette collapses vs its neighbour  -> limb vanished
  EDGE_BLEED     content touches the cell's top/bottom  -> row bleed (grid sheets)

Every threshold is tuned against the SHIPPED corpus and its false-positive
rate is reported by --calibrate, because a checker whose FP rate you have
not measured is worse than no checker (this tool's own first sibling ran at
74% FP).

Usage:
    uv run python tools/sprite_structural_qa.py --calibrate
    uv run python tools/sprite_structural_qa.py --all
    uv run python tools/sprite_structural_qa.py --file assets/sprites/monsters/goblin.png --frame-w 128
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

GAME = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
MANIFEST = GAME / "data" / "sprite_manifest.json"

# ── MEASURED against all 242 shipped sheets, 2026-07-28. Tier by FP rate,
# ── because an unmeasured checker is worse than none (a sibling tool of mine
# ── ran at 74% FP earlier the same night).
#
#   GATE-WORTHY — near-zero false positives, ship-blocking:
#     ALPHA_OPAQUE   0 hits corpus-wide. Would have caught tonight's
#                    chromakey failure (2 sheets shipped fully opaque).
#     ALPHA_EMPTY    4 hits, ALL REAL — masterite_tempo_abstract idles on
#                    7 opaque pixels vs 30933 in its attack, and
#                    masterite_curator_abstract on 204 vs 7760. Both are
#                    invisible until they swing.
#     EDGE_BLEED    18 hits across ~8 sheets, matching the independent
#                    row-bleed audit. Real.
#
#   ADVISORY ONLY — too noisy to gate on this corpus:
#     DETACHED     301 hits / 108 sheets. Held weapons, wings, FX and spell
#                  effects are legitimately disconnected, so the signal does
#                  not separate "severed limb" from "sword". Useful on a
#                  NEW sheet you are eyeballing anyway; useless as a gate.
#     AREA_DROP     11 hits, untriaged. Do not gate until each is judged.
#
# Thresholds stay deliberately permissive: a false positive costs a correct
# sheet being "repaired", which is worse than a miss, and the eye is still
# the final check.
MIN_TRANSPARENT_PCT = 2.0    # below this, the background never keyed
MAX_TRANSPARENT_PCT = 99.5   # above this, the frame is empty
# ALPHA_EMPTY above is ABSOLUTE and was fitted to the two instances that
# motivated it (7 opaque px, 140 opaque px). A mutation run 2026-07-29
# specifically hoping it would survive DID: an idle reduced to 600 opaque
# pixels is 99.08% transparent, clears the absolute gate, and is 0.023 of
# its own attack pose — invisible in battle by any honest reading.
#
# So the absolute floor answers "is this frame empty" and cannot answer
# "is this frame invisible NEXT TO THE SAME MONSTER'S other poses", which
# is the shape both real defects actually had. Proportional floor added
# beside it rather than replacing it: the two catch different things, and
# swapping to the ratio alone flags 8 sheets whose attack legitimately
# covers 3-4x their idle (measured; median ratio across 106 sheets = 0.95).
#
# 0.10 is chosen as a RELATIONSHIP, not fitted: the lowest legitimate sheet
# in the corpus sits at 0.25 (2.5x clear) and the two real defects at
# 0.0002 and 0.018 (5-500x clear). Nothing in the corpus is near it.
MIN_IDLE_PEAK_RATIO = 0.10
DETACHED_MIN_PCT = 1.0       # ignore antialias specks
DETACHED_MAX_PCT = 40.0      # above this it's a real second subject (FX, weapon)
AREA_DROP_PCT = 55.0         # frame loses >55% silhouette vs the previous


def frames_of(img: Image.Image, fw: int, fh: int):
    W, H = img.size
    for row in range(max(1, H // fh)):
        for col in range(W // fw):
            yield row, col, img.crop((col * fw, row * fh,
                                      (col + 1) * fw, (row + 1) * fh))


def check_sheet(path: Path, fw: int, fh: int, is_grid: bool,
                idle_frames: tuple | None = None) -> list[str]:
    out = []
    img = Image.open(path).convert("RGBA")
    # This tool slices frames using frame_width/frame_height FROM THE
    # MANIFEST — a label describing the artifact. If the label is wrong the
    # slicing is wrong, and every check below then reports confidently about
    # frames that do not exist. That is the shape cowir-music found in their
    # own guard (a short-render check reading the manifest's `duration`
    # instead of the audio): an instrument trusting a pointer to measure the
    # thing the pointer describes. Verify the geometry against the actual
    # pixels before believing any result derived from it.
    W, H = img.size
    if fw <= 0 or fh <= 0 or W % fw or H % fh:
        return [f"GEOMETRY {path.name}: manifest says {fw}x{fh} frames but "
                f"the PNG is {W}x{H} — not evenly divisible, so every check "
                f"below would slice garbage. Fix the manifest first."]
    # Proportional invisibility: a frame that is present but tiny beside the
    # same sheet's biggest pose. Strip sheets only — a grid sheet's rows are
    # different characters, so cross-row comparison is meaningless.
    if not is_grid:
        areas = [int((np.array(f)[:, :, 3] > 8).sum())
                 for _, _, f in frames_of(img, fw, fh)]
        if areas and max(areas) > 0:
            peak = max(areas)
            # Idle span from the manifest when known, else the conventional
            # first two frames of an 8-frame strip.
            idle_end = idle_frames[1] if idle_frames else 1
            # IDLE FRAMES ONLY. Scoping to every frame flagged ghost's DEAD
            # pose at 8% — a dissolving ghost is correct art, and dead frames
            # legitimately collapse (AREA_DROP already covers a pose losing
            # its body). The invariant is about the resting pose: it is what
            # BattleScene shows until the monster acts and what BestiaryMenu
            # renders, which is exactly how both real defects presented as
            # "invisible until it swings".
            for i, a_ in enumerate(areas[:idle_end + 1]):
                if a_ > 0 and a_ / peak < MIN_IDLE_PEAK_RATIO:
                    out.append(
                        f"ALPHA_TINY f{i}: {a_}px is {100.0 * a_ / peak:.1f}% "
                        f"of this sheet's largest pose ({peak}px) — present but "
                        f"invisible beside its own animation")

    prev_area = None
    for row, col, fr in frames_of(img, fw, fh):
        a = np.array(fr)[:, :, 3]
        opaque = a > 8
        total = a.size
        trans_pct = 100.0 * (total - opaque.sum()) / total
        tag = f"r{row}c{col}"

        if trans_pct < MIN_TRANSPARENT_PCT:
            out.append(f"ALPHA_OPAQUE {tag}: only {trans_pct:.1f}% transparent "
                       f"— background never keyed")
            continue
        if trans_pct > MAX_TRANSPARENT_PCT:
            out.append(f"ALPHA_EMPTY {tag}: {trans_pct:.1f}% transparent")
            prev_area = None
            continue

        lab, n = ndimage.label(opaque)
        if n > 1:
            sizes = np.sort(ndimage.sum(opaque, lab, range(1, n + 1)))[::-1]
            big = sizes[0]
            for s in sizes[1:]:
                pct = 100.0 * s / big
                if DETACHED_MIN_PCT <= pct <= DETACHED_MAX_PCT:
                    out.append(f"DETACHED {tag}: component {int(s)}px is "
                               f"{pct:.0f}% of the figure — blob or severed limb")
                    break

        area = int(opaque.sum())
        if prev_area and area < prev_area * (1 - AREA_DROP_PCT / 100.0):
            out.append(f"AREA_DROP {tag}: silhouette {area}px vs {prev_area}px "
                       f"previous — limb or body lost")
        prev_area = area

    # EDGE_BLEED is a SHEET-level check, not a per-frame one, and getting
    # that wrong cost a 55%-flagged calibration run. Content at the top of a
    # cell is only "bleed" if it belongs to the row ABOVE — which row 0 has
    # none of, and which a legitimately tall sprite filling its own cell also
    # produces. The honest signal is a contiguous opaque band that CROSSES a
    # cell boundary: one band per row, each contained. (Same discriminator as
    # fix_overworld_row_bleed.py, which this reuses rather than re-derives.)
    if is_grid:
        arr = np.array(img)[:, :, 3] > 8
        rows_any = arr.any(axis=1)
        bands, cur = [], None
        for y, on in enumerate(list(rows_any) + [False]):
            if on and cur is None:
                cur = y
            elif not on and cur is not None:
                bands.append((cur, y - 1))
                cur = None
        for i, (top, bot) in enumerate(bands):
            if top // fh != bot // fh:
                out.append(f"EDGE_BLEED band y={top}..{bot} crosses the cell "
                           f"boundary at y={((top // fh) + 1) * fh} — this "
                           f"row's sprite overflows into the next")
    return out


def manifest_sheets():
    m = json.loads(MANIFEST.read_text())
    for section in ("monster_sheets", "sheets", "overworld_npc_sheets"):
        for key, val in sorted(m.get(section, {}).items()):
            if not isinstance(val, dict):
                continue
            rel = str(val.get("path", "")).replace("res://", "")
            p = GAME / rel
            if not p.exists():
                continue
            anims = val.get("animations", {})
            fw = val.get("frame_width", 256)
            fh = val.get("frame_height", 256)
            # THREE schemas, and each mis-handling cost a false-positive run:
            #  strip  monster_sheets      one PNG, animations {start,end}
            #  grid   overworld_npc_*     one PNG, animations {row,frames}
            #  dir    sheets (jobs)       path is a DIRECTORY, animations is a
            #                             LIST of names -> <dir>/<name>.png
            if p.is_dir():
                for anim in (anims if isinstance(anims, list) else []):
                    ap_ = p / f"{anim}.png"
                    if ap_.exists():
                        yield section, f"{key}/{anim}", ap_, fw, fh, False, None
                continue
            is_grid = bool(isinstance(anims, dict) and anims and all(
                isinstance(v, dict) and "row" in v for v in anims.values()))
            # Derive the idle span from the manifest rather than assuming
            # frames 0-1 — the convention holds today across every strip,
            # but a sheet that declares otherwise should be believed.
            idle = anims.get("idle") if isinstance(anims, dict) else None
            span = ((idle["start"], idle["end"])
                    if isinstance(idle, dict) and "start" in idle else None)
            yield section, key, p, fw, fh, is_grid, span


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--file")
    ap.add_argument("--frame-w", type=int, default=256)
    ap.add_argument("--frame-h", type=int, default=0)
    ap.add_argument("--grid", action="store_true")
    args = ap.parse_args()

    if args.file:
        fh = args.frame_h or args.frame_w
        for line in check_sheet(Path(args.file), args.frame_w, fh, args.grid):
            print(f"  {line}")
        return 0

    flagged, clean = {}, 0
    for section, key, p, fw, fh, is_grid, span in manifest_sheets():
        issues = check_sheet(p, fw, fh, is_grid, span)
        if issues:
            flagged[f"{section}/{key}"] = issues
        else:
            clean += 1

    for name, issues in flagged.items():
        print(f"\n{name}")
        for i in issues[:4]:
            print(f"  {i}")
        if len(issues) > 4:
            print(f"  … +{len(issues)-4} more")

    total = clean + len(flagged)
    print(f"\n{len(flagged)} flagged / {total} sheets")
    if args.calibrate:
        print("\nCALIBRATION: every sheet above is SHIPPED. Each is either a "
              "real defect or a false positive — triage by eye before trusting "
              "the thresholds. An unmeasured FP rate makes this worse than "
              "nothing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
