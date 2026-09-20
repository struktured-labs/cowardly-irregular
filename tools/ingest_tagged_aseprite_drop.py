#!/usr/bin/env python3
"""Ingest artist .aseprite drops into game sheets, driven by the artist's TAGS.

Supersedes tools/ingest_bard_aseprite.py, which hardcodes frame ranges from a
12-frame untagged bard file. The artist's 2026-08-26 rework is 18 frames with
three tags, so those ranges now slice "cast" out of the WEAK frames and straddle
the Weak/ATK boundary. Ranges come from the file itself here.

Orientation (struktured 2026-08-27): monsters face RIGHT, party members face LEFT.
The pipeline PRESERVES the artist's direction, it does not correct it, so a source
drawn the wrong way needs --flip. The 2026-08-20 rat is drawn facing left.

Usage:
    uv run python tools/ingest_tagged_aseprite_drop.py --target rat  --dry-run
    uv run python tools/ingest_tagged_aseprite_drop.py --target bard --dry-run
    uv run python tools/ingest_tagged_aseprite_drop.py --target all
    uv run python tools/ingest_tagged_aseprite_drop.py --selftest
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
ASEPRITE = os.environ.get("ASEPRITE_BIN", str(Path.home() / ".local/bin/aseprite"))
DROP = Path(os.environ.get("DROP_DIR", REPO / "tmp/drop_20260827"))
SRC_FRAME = 128
TARGET_FRAME = 256


# Every .png this run wrote. Checked at the end -- see report_missing_sidecars().
WROTE: list[Path] = []


def sidecar_for(png: Path) -> Path:
    """The Godot .import sidecar for a png: APPEND the suffix, never replace it.

    ⛔ `Path.with_suffix(".import")` is the obvious call and it is WRONG here --
    it replaces the last suffix, so victory.pre_artist.png becomes
    victory.pre_artist.import. Godot's name is <full filename>.import.
    """
    return png.with_name(png.name + ".import")


def save_png(img: Image.Image, out: Path) -> None:
    """Write a sheet and remember it, so the sidecar check at the end sees it."""
    img.save(out)
    WROTE.append(out)


def report_missing_sidecars() -> None:
    """Name every png this run wrote that Godot has no .import for.

    ⛔ WHY THIS EXISTS: on 2026-09-18 this tool wrote victory.pre_artist.png and
    weak.pre_artist.png, both TRACKED art, and neither got a sidecar. All 11
    *.pre_artist.png that already shipped have one; .gitignore:86 says the
    exclusion list deliberately omits them because they are tracked. The cost is
    the one .gitignore:120 already records -- Godot imports an unsidecar'd png
    anyway and mints a fresh uid per worktree ("measured: 4 worktrees, 4 uids"),
    so every tree carries its own churn until someone notices. Nobody noticed for
    two days, because nothing in this tool ever mentioned the sidecar.
    """
    missing = [q for q in WROTE if not sidecar_for(q).exists()]
    if not missing:
        if WROTE:
            print(f"\n  sidecars: all {len(WROTE)} written sheet(s) have a .import")
        return
    print(f"\n  ⛔ {len(missing)} of {len(WROTE)} written sheet(s) have NO .import sidecar:")
    for q in missing:
        try:
            print(f"       {q.relative_to(REPO)}")
        except ValueError:
            print(f"       {q}")
    print("  These are TRACKED art. Without a sidecar every worktree mints its own uid.")
    print("  Generate and commit them:")
    print("       XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy \\")
    print("            --import --quit")
    print("       git add assets/sprites/**/*.png.import")


def selftest() -> int:
    """sidecar_for() only. Pure: builds paths, opens nothing, runs nothing."""
    cases = [
        ("assets/sprites/jobs/bard/victory.png",
         "assets/sprites/jobs/bard/victory.png.import",
         "an ordinary sheet"),
        ("assets/sprites/jobs/bard/victory.pre_artist.png",
         "assets/sprites/jobs/bard/victory.pre_artist.png.import",
         "TWO suffixes -- with_suffix() would eat .png and produce .pre_artist.import"),
        ("assets/sprites/monsters/cave_rat.idle.strip.png",
         "assets/sprites/monsters/cave_rat.idle.strip.png.import",
         "three suffixes; append is still the rule"),
    ]
    bad = 0
    for src, want, note in cases:
        got = str(sidecar_for(Path(src)))
        ok = got == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {Path(src).name:34} -> {Path(got).name:42} {note}")
    # CONTROL: prove with_suffix() -- the wrong call -- actually differs on the
    # dotted name. If it ever agreed, these cases would pass either way.
    dotted = Path("a/b/victory.pre_artist.png")
    if str(sidecar_for(dotted)) == str(dotted.with_suffix(".import")):
        print("FAIL the control is vacuous: append and with_suffix agree here, so "
              "these cases cannot tell the right call from the wrong one")
        bad += 1
    print(f"\n{len(cases)} cases, {bad} failed")
    return 1 if bad else 0


def export_frames(src: Path, out_dir: Path, ignore_layers: list[str] | None = None) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    cmd = [ASEPRITE, "-b", str(src)]
    # an artist BG layer left visible bakes an opaque background into every frame
    for name in (ignore_layers or []):
        cmd += ["--ignore-layer", name]
    cmd += ["--save-as", str(out_dir / "frame_{frame}.png")]
    subprocess.run(cmd, check=True, capture_output=True)
    frames = sorted(out_dir.glob("frame_*.png"), key=lambda p: int(p.stem.split("_")[1]))
    if frames and ignore_layers:
        from PIL import Image as _I
        a = _I.open(frames[0]).convert("RGBA").split()[3]
        px = list(a.getdata())
        clear = sum(1 for v in px if v < 5) / max(1, len(px))
        if clear < 0.10:
            raise RuntimeError(
                "%s: %.1f%% transparent after excluding %s — a background layer is still rendering"
                % (src.name, clear * 100, ignore_layers))
    return frames


def read_tags(src: Path) -> dict[str, tuple[int, int]]:
    """Frame ranges per tag, straight from the .aseprite via a JSON data export."""
    with tempfile.TemporaryDirectory() as td:
        data = Path(td) / "d.json"
        # --list-tags is what puts frameTags in the JSON; without it the export
        # succeeds and silently reports zero tags
        subprocess.run([ASEPRITE, "-b", str(src), "--sheet", str(Path(td) / "s.png"),
                        "--sheet-type", "horizontal", "--data", str(data),
                        "--format", "json-array", "--list-tags"],
                       check=True, capture_output=True)
        meta = json.loads(data.read_text())["meta"]
    tags = {t["name"]: (t["from"], t["to"]) for t in meta.get("frameTags", [])}
    if not tags:
        raise RuntimeError(f"{src.name}: no tags read — ranges would be guesswork")
    return tags


def content_bottom(img: Image.Image) -> int | None:
    bb = img.split()[3].point(lambda p: 255 if p > 10 else 0).getbbox()
    return bb[3] if bb else None


def build_strip(frames: list[Path], rng: tuple[int, int], flip: bool,
                scale: float = 2.0, dx: int = 0, dy: int = 0) -> Image.Image:
    """One global transform for every frame — the artist's inter-frame registration
    is only preserved if no frame gets its own scale or offset."""
    sel = frames[rng[0]:rng[1] + 1]
    side = int(round(SRC_FRAME * scale))
    strip = Image.new("RGBA", (TARGET_FRAME * len(sel), TARGET_FRAME), (0, 0, 0, 0))
    for i, p in enumerate(sel):
        f = Image.open(p).convert("RGBA")
        if f.size != (SRC_FRAME, SRC_FRAME):
            raise RuntimeError(f"{p}: expected {SRC_FRAME}px frame, got {f.size}")
        if flip:
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        up = f.resize((side, side), Image.NEAREST)
        cell = Image.new("RGBA", (TARGET_FRAME, TARGET_FRAME), (0, 0, 0, 0))
        cell.paste(up, (dx, dy), up)
        strip.paste(cell, (i * TARGET_FRAME, 0))
    return strip


def fit_transform(frames: list[Path], flip: bool, reference: Path) -> tuple[float, int, int]:
    """Scale/offset per the skeleton precedent: min(match-reference-height, fit-widest-frame),
    then centre horizontally and seat the feet on the reference's baseline."""
    imgs = [Image.open(p).convert("RGBA") for p in frames]
    if flip:
        imgs = [im.transpose(Image.FLIP_LEFT_RIGHT) for im in imgs]
    boxes = [im.split()[3].point(lambda q: 255 if q > 10 else 0).getbbox() for im in imgs]
    boxes = [b for b in boxes if b]
    if not boxes:
        return 2.0, 0, 0
    src_w = max(b[2] - b[0] for b in boxes)
    src_h = max(b[3] - b[1] for b in boxes)
    margin = 4
    fit_w = (TARGET_FRAME - margin) / src_w
    ref_scale = fit_w
    if reference.exists():
        ref = Image.open(reference).convert("RGBA")
        rb = [ref.crop((i * TARGET_FRAME, 0, (i + 1) * TARGET_FRAME, TARGET_FRAME))
              .split()[3].point(lambda q: 255 if q > 10 else 0).getbbox()
              for i in range(ref.width // TARGET_FRAME)]
        rb = [b for b in rb if b]
        if rb:
            ref_scale = max(b[3] - b[1] for b in rb) / src_h
            ref_baseline = max(b[3] for b in rb)
        else:
            ref_baseline = TARGET_FRAME - 18
    else:
        ref_baseline = TARGET_FRAME - 18
    scale = min(ref_scale, fit_w)
    # aggregate bbox under the chosen scale, so every frame shares one offset
    lo_x = min(b[0] for b in boxes) * scale
    hi_x = max(b[2] for b in boxes) * scale
    bot = max(b[3] for b in boxes) * scale
    dx = int(round((TARGET_FRAME - (hi_x - lo_x)) / 2 - lo_x))
    dy = int(round(ref_baseline - bot))
    return scale, dx, dy


def backup(path: Path) -> None:
    """Never overwrite an existing .pre_artist — it holds the ORIGINAL AI art."""
    bak = path.with_suffix(".pre_artist.png")
    if path.exists() and not bak.exists():
        shutil.copy2(path, bak)
        WROTE.append(bak)
        print(f"    backup {path.name} -> {bak.name}")
    elif bak.exists():
        print(f"    backup {bak.name} already exists — left untouched (holds pre-artist art)")


def baseline_shift(frames: list[Path], reference: Path) -> int:
    """Align the drop's feet to the sheet it replaces, using ONE offset for all frames."""
    if not reference.exists():
        return 0
    ref = Image.open(reference).convert("RGBA")
    ref_bots = [b for b in (content_bottom(ref.crop((i * TARGET_FRAME, 0, (i + 1) * TARGET_FRAME, TARGET_FRAME)))
                            for i in range(ref.width // TARGET_FRAME)) if b]
    src_bots = [b for b in (content_bottom(Image.open(p).convert("RGBA")) for p in frames) if b]
    if not ref_bots or not src_bots:
        return 0
    return max(ref_bots) - max(src_bots) * (TARGET_FRAME // SRC_FRAME)


def ingest_rat(dry: bool) -> None:
    src = DROP / "Rat animations.aseprite"
    tags = read_tags(src)
    print(f"  rat tags: {tags}")
    missing = [t for t in ("Idle", "Atk") if t not in tags]
    if missing:
        raise RuntimeError(f"rat drop missing expected tags {missing} — manifest ranges depend on them")
    out = REPO / "assets/sprites/monsters/cave_rat.png"
    ref = out.with_suffix(".pre_artist.png") if out.with_suffix(".pre_artist.png").exists() else out
    with tempfile.TemporaryDirectory() as td:
        frames = export_frames(src, Path(td))
        scale, dx, dy = fit_transform(frames, True, ref)
        print(f"    frames={len(frames)} flip=True scale={scale:.2f}x dx={dx} dy={dy} (ref {ref.name})")
        if dry:
            return
        backup(out)
        full = build_strip(frames, (0, len(frames) - 1), True, scale, dx, dy)
        save_png(full, out)
        print(f"    -> {out.name}: {full.width}x{full.height} ({len(frames)} frames @{TARGET_FRAME})")


BARD_MAP = {
    "idle": "Idle",
    "dead": "Weak",      # artist's label; engine has no "weak" slot, this is the KO state
}


def ingest_bard(dry: bool) -> None:
    src = DROP / "Bard Base sprite.aseprite"
    tags = read_tags(src)
    print(f"  bard tags: {tags}")
    atk = tags.get("ATK")
    if not atk:
        raise RuntimeError("bard drop has no ATK tag")
    # ATK holds wind-up then swing; split matches the shipped cast/attack it replaces
    mid = atk[0] + 4
    ranges = {"idle": tags["Idle"], "dead": tags["Weak"],
              "cast": (atk[0], mid - 1), "attack": (mid, atk[1])}
    bard_dir = REPO / "assets/sprites/jobs/bard"
    with tempfile.TemporaryDirectory() as td:
        frames = export_frames(src, Path(td))
        print(f"    frames={len(frames)} flip=False (party faces left — source is correct)")
        for anim, rng in ranges.items():
            n = rng[1] - rng[0] + 1
            print(f"    {anim:<7} <- frames {rng[0]}-{rng[1]} ({n})")
            if dry:
                continue
            out = bard_dir / f"{anim}.png"
            backup(out)
            strip = build_strip(frames, rng, False, 2.0, 0, 0)
            save_png(strip, out)
            print(f"      -> {out.name}: {strip.width}x{strip.height}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=["rat", "bard", "mage", "fighter", "rogue", "cleric", "drop30", "drop03", "all"], default="all")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true",
                    help="check sidecar_for() and exit; opens nothing, needs no aseprite")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not Path(ASEPRITE).exists():
        print(f"ERROR: aseprite not at {ASEPRITE}", file=sys.stderr)
        return 1
    if a.target == "rat":
        ingest_rat(a.dry_run)
    elif a.target in DROPS_20260903:
        ingest_drop3(a.target, a.dry_run)
    elif a.target == "drop03":
        for k in DROPS_20260903:
            ingest_drop3(k, a.dry_run)
    elif a.target in DROPS_20260902:
        ingest_drop2(a.target, a.dry_run)
    elif a.target in DROPS_20260830:
        ingest_drop(a.target, a.dry_run)
    else:
        for k in DROPS_20260830:
            ingest_drop(k, a.dry_run)
    if not a.dry_run:
        report_missing_sidecars()
    return 0




# 2026-08-30 drop: the artist split Weak from Dead and added both to mage and bard
DROPS_20260830 = {
    "bard": {
        "src": "Bard Base sprite.aseprite",
        "dir": "assets/sprites/jobs/bard",
        "backup": True,
        # "Celebration" is the ARTIST's label for the victory pose; the engine's
        # animation slot is "victory". Their word is kept in the manifest source note,
        # the same way "Dead"/"Weak" were when they split the downed state.
        "map": {"idle": ("Idle", 0, 0), "dead": ("Dead", 0, 0), "weak": ("Weak", 0, 0),
                "victory": ("Celebration", 0, 0),
                "cast": ("ATK", 0, 3), "attack": ("ATK", 4, 99)},
    },
    "mage": {
        "src": "Mage Main design.aseprite",
        "dir": "assets/sprites/jobs/mage",
        # current mage sheets are ALREADY artist art from this same source; a .pre_artist
        # backup would file artist pixels under a pre-artist name. git history holds the prior.
        "backup": False,
        "map": {"idle": ("IDLE", 0, 0), "weak": ("Weak", 0, 0), "dead": ("Dead", 0, 0),
                "cast": ("Atk 1", 0, 0), "attack": ("Atk 1", 0, 0)},
    },
}


def ingest_drop(name: str, dry: bool) -> None:
    cfg = DROPS_20260830[name]
    src = DROP / cfg["src"]
    tags = read_tags(src)
    print(f"  {name} tags: {tags}")
    out_dir = REPO / cfg["dir"]
    with tempfile.TemporaryDirectory() as td:
        frames = export_frames(src, Path(td))
        print(f"    frames={len(frames)}")
        for anim, (tag, lo, hi) in cfg["map"].items():
            if tag not in tags:
                raise RuntimeError(f"{name}: source has no tag {tag!r}; got {list(tags)}")
            t0, t1 = tags[tag]
            a = t0 + lo
            b = t1 if hi >= 99 or hi == 0 else min(t1, t0 + hi)
            n = b - a + 1
            print(f"    {anim:<7} <- {tag} {a}-{b} ({n})")
            if dry:
                continue
            out = out_dir / f"{anim}.png"
            if cfg["backup"]:
                backup(out)
            save_png(build_strip(frames, (a, b), False, 2.0, 0, 0), out)
            print(f"      -> {out.name}")


# 2026-09-02 drop: fighter gains Weak + a real Dead (6 frames -> 21, 3 tags -> 5)
DROPS_20260902 = {
    "fighter": {
        "src": "Main Fighter animations.aseprite",
        "dir": "assets/sprites/jobs/fighter",
        # per-ANIM, not per-job: only `dead` is a non-artist fill (68b049d0 v3 LoRA sweep, and
        # the source carried no Dead tag until today). Backing up the rest would file artist
        # pixels under a pre_artist name; git history holds them.
        "backup_anims": {"dead"},
        "map": {"idle": ("IDLE", 0, 0), "weak": ("Weak", 0, 0), "dead": ("Dead", 0, 0),
                "dash": ("Dash", 0, 0), "attack": ("ATK", 0, 0), "slash": ("ATK", 0, 0)},
    },
}


def ingest_drop2(name: str, dry: bool) -> None:
    cfg = DROPS_20260902[name]
    src = DROP / cfg["src"]
    tags = read_tags(src)
    print(f"  {name} tags: {tags}")
    out_dir = REPO / cfg["dir"]
    with tempfile.TemporaryDirectory() as td:
        frames = export_frames(src, Path(td))
        print(f"    frames={len(frames)}")
        for anim, (tag, lo, hi) in cfg["map"].items():
            if tag not in tags:
                raise RuntimeError(f"{name}: source has no tag {tag!r}; got {list(tags)}")
            t0, t1 = tags[tag]
            a = t0 + lo
            b = t1 if hi == 0 else min(t1, t0 + hi)
            mark = " [backup]" if anim in cfg["backup_anims"] else ""
            print(f"    {anim:<7} <- {tag} {a}-{b} ({b - a + 1}){mark}")
            if dry:
                continue
            out = out_dir / f"{anim}.png"
            if anim in cfg["backup_anims"]:
                backup(out)
            save_png(build_strip(frames, (a, b), False, 2.0, 0, 0), out)
            print(f"      -> {out.name}")


# 2026-09-03 drop: rogue and cleric complete the Weak/Dead set across all 5 starters
DROPS_20260903 = {
    "rogue": {
        "src": "Rogue Main design.aseprite",
        "dir": "assets/sprites/jobs/rogue",
        # dead only: the prior source carried NO tags at all, so dead.png was never artist-authored
        "backup_anims": {"dead"},
        # the artist left an opaque "Layer 1" background visible in this drop
        "ignore_layers": ["Layer 1"],
        "map": {"idle": ("Idle", 0, 0), "weak": ("Weak", 0, 0), "dead": ("Dead", 0, 0),
                "attack": ("ATK", 0, 0), "stab": ("ATK", 0, 0)},
    },
    "cleric": {
        "src": "Cleric Main design.aseprite",
        "dir": "assets/sprites/jobs/cleric",
        "backup_anims": {"dead"},
        "map": {"idle": ("Idle", 0, 0), "weak": ("Weak", 0, 0), "dead": ("Dead", 0, 0),
                "cast": ("Cast", 0, 0), "attack": ("Cast", 0, 0)},
    },
}


def ingest_drop3(name: str, dry: bool) -> None:
    cfg = DROPS_20260903[name]
    src = DROP / cfg["src"]
    tags = read_tags(src)
    print(f"  {name} tags: {tags}")
    out_dir = REPO / cfg["dir"]
    with tempfile.TemporaryDirectory() as td:
        frames = export_frames(src, Path(td), cfg.get("ignore_layers"))
        print(f"    frames={len(frames)} ignore_layers={cfg.get('ignore_layers') or 'none'}")
        for anim, (tag, lo, hi) in cfg["map"].items():
            if tag not in tags:
                raise RuntimeError(f"{name}: source has no tag {tag!r}; got {list(tags)}")
            t0, t1 = tags[tag]
            a, b = t0 + lo, (t1 if hi == 0 else min(t1, t0 + hi))
            mark = " [backup]" if anim in cfg["backup_anims"] else ""
            print(f"    {anim:<7} <- {tag} {a}-{b} ({b - a + 1}){mark}")
            if dry:
                continue
            out = out_dir / f"{anim}.png"
            if anim in cfg["backup_anims"]:
                backup(out)
            save_png(build_strip(frames, (a, b), False, 2.0, 0, 0), out)
            print(f"      -> {out.name}")


if __name__ == "__main__":
    sys.exit(main())
