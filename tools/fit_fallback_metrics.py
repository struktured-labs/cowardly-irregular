#!/usr/bin/env python3
"""Fit the Noto symbol fallbacks' line box inside the pixel face's, at every size.

Run:  uv run --no-project --with fonttools python tools/fit_fallback_metrics.py [--check]

Why: Godot takes a font CHAIN's max ascent/descent for every Label, even one drawing only Latin
text (test_the_symbol_fallbacks_keep_the_base_line_box). The pixel face (UiFont) is ASCENT 9 /
DESCENT 3 at 1x and only steps at k = round(size / 9), so a fallback whose box scales smoothly with
size outgrows it between steps: at 9/10/12/13 px the chain measured 13/14/17/18 where the face is 12
(.804 slot 1, 2026-11-14). The worst size is the top of the 1x step, 13 px, and FreeType CEILS the
ascender and descender to whole pixels, so the box must satisfy ceil(13 * a) <= 9 and
ceil(13 * d) <= 3: a <= 9/13 and d <= 3/13 of the em. At every higher step the same ratios fit with
room to spare (9k / (9k + 4) grows with k).

Only the declared line box changes (hhea + OS/2 typo); outlines, advances and the baseline do not, so
a glyph draws exactly where it did. The reading face (Open Sans, ascent 1.069 em) still has the
taller box, so its chain is unchanged in height. OFL permits modification; these fonts declare no
Reserved Font Name (the 1069/293 rewrite before this one relied on the same).
"""
import math
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = [
    "assets/fonts/fallback/NotoSansSymbols2-Regular.ttf",
    "assets/fonts/fallback/NotoSansSymbols-Regular.ttf",
    "assets/fonts/fallback/NotoSansMath-Regular.ttf",
    "assets/fonts/fallback/NotoEmoji-Regular.ttf",
    "assets/fonts/fallback/CowirLatinFallback-Regular.ttf",
]
## The Latin fallback behind the pixel face (main 25569: a model's "Éclair" must not draw as tofu) is Anonymous Pro
## from the GUT addon, which exports exclude, so it is copied here. Its OFL reserves the name "Anonymous Pro", and a
## re-boxed copy is a Modified Version, so the copy is renamed (OFL section 3) and ships with OFL-AnonymousPro.txt.
DERIVED = {
    "assets/fonts/fallback/CowirLatinFallback-Regular.ttf": ("addons/gut/fonts/AnonymousPro-Regular.ttf", "Cowir Latin Fallback"),
}
RENAMED_IDS = (1, 3, 4, 6, 16, 17)


def derive(target: Path, source: Path, family: str) -> None:
    font = TTFont(source)
    post = family.replace(" ", "") + "-Regular"
    names = {1: family, 3: f"{post};1.003;cowir", 4: f"{family} Regular", 6: post, 16: family, 17: "Regular"}
    for rec in list(font["name"].names):
        if rec.nameID in RENAMED_IDS:
            font["name"].removeNames(nameID=rec.nameID)
    for nid, text in names.items():
        if nid in (16, 17):
            continue
        font["name"].setName(text, nid, 3, 1, 0x409)
        font["name"].setName(text, nid, 1, 0, 0)
    # Anonymous Pro maps ten private-use codepoints (its own logo glyphs). They are not text, and a fallback that
    # answers for U+E000 blinds test_every_rendered_glyph_resolves_regression's tofu control. Unmapped, not deleted.
    for table in font["cmap"].tables:
        for cp in [c for c in table.cmap if is_private(c)]:
            del table.cmap[cp]
    font.save(target)


def is_private(cp: int) -> bool:
    return 0xE000 <= cp <= 0xF8FF or cp >= 0xF0000


def renamed_ok(path: Path, family: str) -> list[str]:
    bad = []
    pua = [hex(c) for c in TTFont(path).getBestCmap() if is_private(c)]
    if pua:
        bad.append(f"maps private-use {pua[:3]}")
    for rec in TTFont(path)["name"].names:
        if rec.nameID in RENAMED_IDS and "anonymous" in str(rec).lower():
            bad.append(f"name {rec.nameID} still says {rec}")
    if not any(rec.nameID == 1 and str(rec) == family for rec in TTFont(path)["name"].names):
        bad.append(f"family is not {family}")
    return bad
PIXEL_ASCENT, PIXEL_DESCENT, NOMINAL = 9, 3, 9
WORST = NOMINAL + 4  # the largest size still drawn at 1x: round(13 / 9) == 1


def target(upm: int) -> tuple[int, int]:
    return math.floor(upm * PIXEL_ASCENT / WORST), math.floor(upm * PIXEL_DESCENT / WORST)


def fits(asc: int, desc: int, upm: int) -> list[str]:
    bad = []
    for size in range(6, 97):
        k = max(1, round(size / NOMINAL))
        a, d = math.ceil(size * asc / upm), math.ceil(size * desc / upm)
        if a > PIXEL_ASCENT * k or d > PIXEL_DESCENT * k:
            bad.append(f"{size}px: {a}/{d} > {PIXEL_ASCENT * k}/{PIXEL_DESCENT * k}")
    return bad


def main() -> int:
    check = "--check" in sys.argv[1:]
    failed = 0
    for rel in FONTS:
        path = ROOT / rel
        if rel in DERIVED:
            src, family = DERIVED[rel]
            if not path.exists():
                if check:
                    print(f"{path.name}: MISSING (derive it from {src})")
                    failed += 1
                    continue
                derive(path, ROOT / src, family)
                print(f"  derived {path.name} from {src} as '{family}'")
            bad = renamed_ok(path, family)
            if bad:
                print(f"{path.name}: RESERVED NAME LEFT: {bad[:2]}")
                failed += 1
        font = TTFont(path)
        upm = font["head"].unitsPerEm
        asc, desc = target(upm)
        hhea, os2 = font["hhea"], font["OS/2"]
        now = (hhea.ascent, -hhea.descent, hhea.lineGap, os2.sTypoAscender, -os2.sTypoDescender, os2.sTypoLineGap)
        want = (asc, desc, 0, asc, desc, 0)
        bad = fits(now[0], now[1], upm)
        print(f"{path.name}: upm {upm} hhea/typo {now} want {want} misfits {len(bad)}{' e.g. ' + bad[0] if bad else ''}")
        if check:
            failed += int(now != want or bool(bad))
            continue
        if now == want:
            continue
        hhea.ascent, hhea.descent, hhea.lineGap = asc, -desc, 0
        os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = asc, -desc, 0
        assert not fits(asc, desc, upm), (path.name, fits(asc, desc, upm)[:3])
        font.save(path)
        print(f"  wrote {path.name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
