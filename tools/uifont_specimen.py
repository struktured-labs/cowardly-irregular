#!/usr/bin/env python3
"""Draw the pixel UI face from its two glyph tables without the engine: tools/uifont_specimen.py OUT.png [scale]
Checks the tables too (every glyph 7 or 9 rows, rows of one width, only '#' and '.')."""
import re, sys
from PIL import Image

def table(path):
    src = open(path, encoding="utf-8").read()
    body = src[src.index("const GLYPHS := {"):]
    body = body[:body.index("\n}")]
    out = {}
    for m in re.finditer(r'^\t"((?:\\.|[^"\\])+)": \[(.*?)\],?$', body, re.M):
        key = m.group(1).replace('\\"', '"').replace("\\\\", "\\")
        out[key] = re.findall(r'"([#.]*)"', m.group(2))
    return out

def aliases(path):
    src = open(path, encoding="utf-8").read()
    body = src[src.index("const ALIASES := {"):]
    return dict(re.findall(r'"((?:\\.|[^"\\])+)": "((?:\\.|[^"\\])+)"', body[:body.index("\n}")]))

G = table("src/ui/PixelText.gd")
caps = len(G)
extra = table("src/ui/UiFontGlyphs.gd")
dup = sorted(set(G) & set(extra))
G.update(extra)
_src = open("src/ui/UiFontGlyphs.gd", encoding="utf-8").read()
_ov = _src[_src.index("const OVERRIDES := {"):]
for m in re.finditer(r'^\t"((?:\\.|[^"\\])+)": \[(.*?)\],?$', _ov[:_ov.index("\n}")], re.M):
    G[m.group(1)] = re.findall(r'"([#.]*)"', m.group(2))
for a, b in aliases("src/ui/UiFontGlyphs.gd").items():
    G[a] = G[b.replace('\\"', '"')]
bad = [k for k, r in G.items() if len(r) not in (7, 9) or len({len(x) for x in r}) != 1 or not r[0]]
print(f"glyphs: {caps} PixelText + {len(extra)} UiFontGlyphs, {len(G)} with aliases; duplicated keys {dup}; malformed {bad}")

def draw(lines, scale, fg=(240, 236, 220), bg=(24, 20, 40), rim=False):
    lh = 12
    w = max(sum((3 if c == " " else len(G.get(c, G["?"])[0]) + 1) for c in l) for l in lines) + 6
    img = Image.new("RGB", (w, lh * len(lines) + 4), bg)
    px = img.load()
    for li, l in enumerate(lines):
        x = 3
        for c in l:
            if c == " ":
                x += 3; continue
            rows = G.get(c, G["?"])
            ink = {(x + i, 3 + li * lh + j) for j, r in enumerate(rows) for i, v in enumerate(r) if v == "#"}
            if rim:
                for (a, b) in ink:
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            if 0 <= a + dx < img.width and 0 <= b + dy < img.height:
                                px[a + dx, b + dy] = (13, 8, 23)
            for p in ink:
                px[p] = fg
            x += len(rows[0]) + 1
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)

if __name__ == "__main__":
    lines = [
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789",
        "abcdefghijklmnopqrstuvwxyz",
        "The quick brown fox jumps over the lazy dog.",
        "Sphinx of black quartz, judge my vow! Why? 50% - \"yes\"",
        "http://localhost:11434/v1  api_key=sk-...  llama3.2:latest",
        "(Bronze Sword) [Equip] {x} <A> #1 & $20 * @ ~ ^ | ` ; : \\",
        "Attack  Magic  Item  Defend  Auto  Trust: Full",
        "→ ← ↑ ↓ ▶ ◀ ▸ ◂ ▲ ▼ ✓ ✗ ★ · • … – — ×3 ’quoted’ “so”",
        "Illegal 1lI| O0o 5S 8B 2Z rn m cl d",
        "Glacius gathers the cold. Everyone takes 142 damage!",
    ]
    out = sys.argv[1]
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    a = draw(lines, scale)
    b = draw(lines, scale, fg=(20, 20, 20), bg=(192, 192, 192))
    c = draw(lines, scale, fg=(255, 255, 255), bg=(70, 110, 80), rim=True)
    sheet = Image.new("RGB", (a.width, a.height * 3))
    for i, im in enumerate((a, b, c)):
        sheet.paste(im, (0, a.height * i))
    sheet.save(out)
    print(out, sheet.size)
