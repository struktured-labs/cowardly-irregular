#!/usr/bin/env python3
"""Re-derive Chancellor Mordaine's cutscene portrait from the ARTIST battle sheet.

Work order: struktured, twice — "we need a face for mordaine too its cursed
right now" (relayed via cowir-main msg 6743, raised again msg 6776).

THE DEFECT: her portrait is a DIFFERENT CHARACTER from her artist battle
sheet. Measured on 7cc20d01:

    portrait  npcs/chancellor_mordaine.png  young woman, long straight BLACK
              hair, black veil/hood, GOLD CROSS headpiece, huge pale lavender
              eyes, black robe
    battle    monsters/chancellor_mordaine.png  tier T2 (ARTIST)  mature woman,
              SILVER hair in an updo, dark gemmed headpiece, dark eyes,
              PURPLE sash over a TEAL-BLUE robe
    overworld npcs/chancellor_mordaine/overworld.png  agrees with battle

Two of three surfaces agree, so the portrait is the outlier and the ARTIST
sheet is the source of truth. We derive FROM it; we never touch it (T2).

⚠️ docs/character-profiles/mordaine.md is STALE — it says "Status: Spec only,
no sprite work shipped yet" and specifies near-black unadorned robes, which
the artist's shipped sheet supersedes. It is still corroborating on the point
that matters: its "what NOT to draw" list bans ceremonial headdresses and
glittering ornament, i.e. the portrait's gold cross. Doc and art agree the
portrait is wrong; they differ only on robe colour, where shipped art wins.

Pipeline: same as tools/regen_masterite_portraits.py — one gpt-image-1 edit
call with TWO references:
    ref 1  FRAMING   npcs/marta.png — a known-good mature-woman bust in this
                     exact family. Chosen because she has NO hood and NO
                     headpiece, so no cursed feature exists anywhere in the
                     reference set to bleed back in.
    ref 2  IDENTITY  the artist battle strip, frame 0.
Output 256x256 transparent bust, matching the npcs/ convention (measured
opaque fraction 0.39-0.58 across that directory).

Cost: 1 x $0.167 (high).
"""
import argparse
import base64
import io
import os
import sys
import time
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get("GAME_REPO", ""))
if not GAME_REPO or not GAME_REPO.exists():
    sys.exit("set GAME_REPO to the target checkout — the old default pointed at "
             "a superseded do-not-fold branch")

RAW_DIR = PROJECT / "tmp" / "mordaine_portrait_regen"
RAW_DIR.mkdir(parents=True, exist_ok=True)

COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

FRAMING_ANCHOR = GAME_REPO / "assets/sprites/portraits/npcs/marta.png"
IDENTITY_REF = GAME_REPO / "assets/sprites/monsters/chancellor_mordaine.png"
OUT_PATH = GAME_REPO / "assets/sprites/portraits/npcs/chancellor_mordaine.png"

PROMPT = (
    "16-bit JRPG pixel-art character portrait bust, in the style of Final "
    "Fantasy VI and Chrono Trigger: bold clean outlines, soft cel shading, "
    "limited palette, no anti-aliasing mush, no floating pixels. "
    "FRAMING — copy the framing of the FIRST reference image exactly: "
    "head and upper shoulders, head filling roughly 60% of the frame, "
    "centered, on a FULLY TRANSPARENT background. No scenery, no props, "
    "no weapons, no text. "
    "IDENTITY — the character is the woman in the SECOND reference image, "
    "and her design must match it: CHANCELLOR MORDAINE, a mature woman in "
    "late middle age, hair SILVER-GREY and pinned up in a neat, severe UPDO "
    "with a small dark headpiece set with a single gem across the crown. "
    "A deep TEAL-BLUE high-collared robe with a VIOLET-PURPLE sash draped "
    "across one shoulder. Pale warm skin with visible age in the face — a "
    "few fine lines, a firm jaw. Eyes are DARK and small with a clearly "
    "readable iris and pupil, looking straight at the viewer, cold and "
    "evaluating. Three-quarter turn of the head. "
    "CHARACTER READ — she is a hyper-competent administrator, not a witch "
    "and not a monster. Her power is stillness. Composed, unimpressed, "
    "faintly contemptuous. She is EVALUATING you. Not snarling, not "
    "grinning, not sad. "
    "CRITICAL NEGATIVES — absolutely NO black veil, NO hood, NO cowl, NO "
    "gold cross, NO crucifix, NO crown, NO tiara, NO long flowing loose "
    "black hair, NO huge pale glowing anime eyes, NO young girl. She is "
    "grey-haired, bare-headed apart from the small gemmed band, and "
    "middle-aged. Do NOT copy the clothing, hair, headwear or face of the "
    "first reference image — take ONLY its framing and its art style."
)


def load_ref_bytes(path: Path, is_battle_strip: bool = False) -> bytes:
    img = Image.open(path).convert("RGBA")
    if is_battle_strip:
        H = img.size[1]
        img = img.crop((0, 0, H, H))
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
    target = 1024
    scale = target / max(img.size)
    new_w, new_h = max(1, int(img.size[0] * scale)), max(1, int(img.size[1] * scale))
    img = img.resize((new_w, new_h), Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)
    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def downscale_to_portrait(img_1024: Image.Image, target: int = 256) -> Image.Image:
    img = img_1024.convert("RGBA")
    img = img.resize((target * 4, target * 4), Image.LANCZOS)
    return img.resize((target, target), Image.BOX)


def remove_flat_background(img: Image.Image, threshold: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def call_gpt_image(client, prompt, ref_files, quality, max_retries=3):
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(model="gpt-image-1", image=ref_files,
                                      prompt=prompt, size="1024x1024",
                                      quality=quality, n=1)
            return Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg:
                wait = 30 * (attempt + 1)
                print(f"    rate limited; backing off {wait}s")
                time.sleep(wait)
            elif any(k in msg for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"    error: {e}; retry {attempt+1}/{max_retries}")
                time.sleep(5)
    raise RuntimeError("failed after retries")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--variants", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for p in (FRAMING_ANCHOR, IDENTITY_REF):
        if not p.exists():
            sys.exit(f"missing reference: {p}")

    if args.dry_run:
        print(f"DRY RUN — {args.variants} variant(s) at {args.quality} "
              f"(~${COST[args.quality]*args.variants:.3f})")
        print(f"  framing  {FRAMING_ANCHOR}")
        print(f"  identity {IDENTITY_REF}  (battle strip, frame 0, alpha-cropped)")
        print(f"  out      {OUT_PATH}")
        return 0

    client = OpenAI()
    framing = load_ref_bytes(FRAMING_ANCHOR)
    identity = load_ref_bytes(IDENTITY_REF, is_battle_strip=True)
    (RAW_DIR / "ref_identity.png").write_bytes(identity)
    (RAW_DIR / "ref_framing.png").write_bytes(framing)

    for v in range(args.variants):
        print(f"[{v+1}/{args.variants}] generating at {args.quality}...")
        refs = [("framing.png", io.BytesIO(framing), "image/png"),
                ("identity.png", io.BytesIO(identity), "image/png")]
        img = call_gpt_image(client, PROMPT, refs, args.quality)
        raw = RAW_DIR / f"mordaine_v{v+1}_raw.png"
        img.save(raw)
        out = remove_flat_background(downscale_to_portrait(img))
        cand = RAW_DIR / f"mordaine_v{v+1}.png"
        out.save(cand)
        a = out.split()[3]
        opaque = sum(1 for px in a.get_flattened_data() if px > 250)
        print(f"    raw={raw.name}  candidate={cand.name}  "
              f"opaque_frac={opaque/(out.size[0]*out.size[1]):.2f} "
              f"(npcs/ convention 0.39-0.58)")

    print(f"\ncandidates in {RAW_DIR} — review, then copy the chosen one to")
    print(f"  {OUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
