#!/usr/bin/env python3
"""Review every NPC's dialogue face against the body that walks under it, and write the ledger.

struktured 2026-10-30: "Willow ... portrait is cute but npc looks like mario with the mustache. we need
like a test that asserts that portrait is somewhat related to the character… all sorts of broken matches."

The PAIRS come from the running game, never from this file: test_a_face_belongs_to_the_body_it_rides.gd
crawls every village and interior plus ShopScene.PICTURED_KEEPERS and prints one line per pair:
    [face-body] <face_key>|<body_sheet_id>|<who @ scene, ...>
Run that test, point --log at its output, and this tool:
  1. renders each pair side by side (portrait | body front, left and back frames at 4x),
  2. asks a vision model whether they are the same person (sex, age, facial hair, hair colour, outfit/role),
  3. writes data/npc_face_body_ledger.json rows with the SHA-256 of BOTH files it judged,
  4. writes a contact sheet of every pair, mismatches first, for a human to eyeball.

A side with no artwork (a procedural face or body) gets verdict "procedural", never "match": the guard
accepts it only while that side really has no art.

Usage:
    set -a; . ./setenv.sh; set +a
    XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_face_belongs_to_the_body_it_rides > tmp/face_body.log 2>&1
    uv run python tools/review_npc_face_body.py --log tmp/face_body.log            # review pending pairs only
    uv run python tools/review_npc_face_body.py --log tmp/face_body.log --all      # re-review everything
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
LEDGER = REPO / "data/npc_face_body_ledger.json"
MANIFEST = REPO / "data/sprite_manifest.json"
DIALOGUE = REPO / "src/cutscene/CutsceneDialogue.gd"
WORK = REPO / "tmp/face_body_review"
MODEL = "gpt-4.1"
LINE = re.compile(r"\[face-body\] ([a-z0-9_:]+)\|([a-z0-9_:]+)\|(.*)$")

QUESTION = """Image 1 is a character's dialogue PORTRAIT. Image 2 is the small overworld WALKING SPRITE the
game draws for that same character (front, left, back). Pixel art; the sprite is tiny, so judge broad traits
only. Is the sprite plausibly the SAME PERSON as the portrait? Compare: apparent sex, age band (child/young/
adult/elderly), facial hair (a beard or mustache on one and not the other is a mismatch), hair colour and
length, and outfit/role. Ignore art style, detail level and pose. Reply with JSON only:
{"sex":true|false,"age":true|false,"facial_hair":true|false,"hair":true|false,"outfit":true|false,
 "verdict":"match"|"mismatch","reason":"<one short sentence naming the decisive difference, or what matches>"}"""


def sha256(path: Path | None) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path and path.is_file() else ""


def portrait_paths() -> dict[str, Path]:
    """CutsceneDialogue.PORTRAIT_SPRITES, read from the source the game ships."""
    src = DIALOGUE.read_text()
    i = src.find("const PORTRAIT_SPRITES")
    block = src[i: src.find("\n}", i)]
    return {k: REPO / v.replace("res://", "") for k, v in re.findall(r'"([a-z0-9_]+)"\s*:\s*"(res://[^"]+)"', block)}


def body_path(body: str, sheets: dict) -> Path | None:
    e = sheets.get(body)
    return REPO / e["path"].replace("res://", "") if e else None


def pairs_from_log(log: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in log.read_bytes().decode("utf-8", "replace").splitlines():
        m = LINE.search(raw)
        if m:
            out[f"{m.group(1)}|{m.group(2)}"] = m.group(3).strip()
    return out


def body_frames(path: Path, frame: int) -> Image.Image:
    """Front, left and back standing frames side by side (rows 0, 1, 3 of the walk sheet)."""
    sheet = Image.open(path).convert("RGBA")
    cells = [sheet.crop((0, r * frame, frame, (r + 1) * frame)) for r in (0, 1, 3)]
    out = Image.new("RGBA", (frame * 3 + 8, frame), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        out.paste(c, (i * (frame + 4), 0), c)
    return out


def panel(face: Path | None, body: Path | None, frame: int, label: str) -> Image.Image:
    T = 224
    W = Image.new("RGB", (T + (frame * 3 + 8) * 4 + 30, T + 22), (54, 54, 64))
    if face and face.is_file():
        f = Image.open(face).convert("RGBA")
        f.thumbnail((T, T), Image.NEAREST)
        W.paste(f, (6, 0), f)
    if body and body.is_file():
        b = body_frames(body, frame)
        b = b.resize((b.width * 4, b.height * 4), Image.NEAREST)
        W.paste(b, (T + 20, T - b.height), b)
    ImageDraw.Draw(W).text((6, T + 5), label[:150], fill=(255, 225, 120))
    return W


def png_b64(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def judge(client, face: Path, body: Path, frame: int) -> dict:
    f = Image.open(face).convert("RGBA")
    f.thumbnail((512, 512), Image.NEAREST)
    b = body_frames(body, frame)
    b = b.resize((b.width * 6, b.height * 6), Image.NEAREST)
    resp = client.chat.completions.create(
        model=MODEL, temperature=0, response_format={"type": "json_object"},
        messages=[{"role": "user", "content": [
            {"type": "text", "text": QUESTION},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64," + png_b64(f)}},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64," + png_b64(b)}},
        ]}])
    return json.loads(resp.choices[0].message.content)


def main() -> int:
    global MODEL
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True, type=Path, help="output of the guard's run")
    ap.add_argument("--all", action="store_true", help="re-review every pair, not only new or changed ones")
    ap.add_argument("--model", default=MODEL)
    args = ap.parse_args()
    MODEL = args.model
    pairs = pairs_from_log(args.log)
    if not pairs:
        raise SystemExit(f"no [face-body] lines in {args.log}: did the guard run, and did it reach its crawl?")
    sheets = json.loads(MANIFEST.read_text())["overworld_npc_sheets"]
    faces = portrait_paths()
    ledger = json.loads(LEDGER.read_text()) if LEDGER.exists() else {}
    WORK.mkdir(parents=True, exist_ok=True)
    client = None
    panels: list[tuple[str, Image.Image]] = []
    for key, who in sorted(pairs.items()):
        face_key, body = key.split("|", 1)
        fpath, bpath = faces.get(face_key), body_path(body, sheets)
        fsha = sha256(fpath) or "procedural"
        bsha = "procedural" if body.startswith("procedural:") else (sha256(bpath) or "missing")
        frame = int(sheets.get(body, {}).get("frame_height", 32))
        row = ledger.get(key, {})
        fresh = row.get("face_sha256") == fsha and row.get("body_sha256") == bsha and row.get("verdict")
        if not args.all and fresh:
            verdict, reason = row["verdict"], row.get("reason", "")
        elif fsha == "procedural" or bsha in ("procedural", "missing"):
            verdict = "procedural"
            reason = "no artwork on the %s side to compare" % ("face" if fsha == "procedural" else "body")
            row = {}
        else:
            if client is None:
                from openai import OpenAI
                client = OpenAI()
            j = judge(client, fpath, bpath, frame)
            verdict = "match" if j.get("verdict") == "match" else "mismatch"
            failed = [t for t in ("sex", "age", "facial_hair", "hair", "outfit") if j.get(t) is False]
            reason = j.get("reason", "") + (f" [differs: {', '.join(failed)}]" if failed else "")
            print(f"  {verdict:<9} {key:<44} {reason[:90]}", flush=True)
        ledger[key] = {"face_sha256": fsha, "body_sha256": bsha, "verdict": verdict, "reason": reason, "who": who}
        panels.append((verdict, panel(fpath, bpath, frame, f"[{verdict}] {key}  -- {who}")))
    LEDGER.write_text(json.dumps(dict(sorted(ledger.items())), indent=2) + "\n")
    order = {"mismatch": 0, "procedural": 1, "match": 2}
    panels.sort(key=lambda p: order.get(p[0], 0))
    sheet = Image.new("RGB", (max(p.width for _, p in panels), sum(p.height + 4 for _, p in panels)), (30, 30, 36))
    y = 0
    for _, p in panels:
        sheet.paste(p, (0, y))
        y += p.height + 4
    out = WORK / "contact_sheet.png"
    sheet.save(out)
    counts = {v: sum(1 for x, _ in panels if x == v) for v in order}
    print(f"{len(panels)} pairs: {counts}. Ledger -> {LEDGER}; contact sheet -> {out}")
    return 1 if counts["mismatch"] else 0


if __name__ == "__main__":
    sys.exit(main())
