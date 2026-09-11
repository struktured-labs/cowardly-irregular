#!/usr/bin/env python3
"""Generate 4 Masterite family portraits (Warden/Tempo/Arbiter/Curator)
for cutscene dialogue display.

Work order: struktured (2026-07-16 via cowir-main msg 2657 + cowir-cutscenes
msg 2662) — the Masterites currently render with procedural `mysterious`
portrait, no visual distinction between roles. One portrait per role, not
per world variant (24→4 dedup — all "Warden of X" are the same masterite
renamed per world).

Anchor: each portrait's identity references the medieval T1 battle strip
that struktured is currently fighting (visual canon in playtest). Persona
reads from data/monsters.json descriptions + boss_dialogue.json.

Pipeline: same as tools/regen_broken_portraits.py — one gpt-image-1 call
per portrait at the party-portrait framing anchor (cleric.png), plus each
Masterite's own battle-strip frame 0 as identity reference. 256×256
face+shoulders bust, transparent bg.

Output: assets/sprites/portraits/masterites/{warden,tempo,arbiter,curator}.png
Cost: 4 × $0.167 (high quality) = ~$0.67
"""
import argparse
import base64
import io
import json
import os
import sys
import time
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
# Defaults to the checkout this script runs from. It used to hardcode a SIBLING worktree --
# another agent's tree -- which OUT_DIR then WROTE into. Same defect fixed in two other tools
# on 2026-09-11; this one had it too and it is the one that writes portraits.
GAME_REPO = Path(os.environ.get("GAME_REPO", str(PROJECT)))
OUT_DIR = GAME_REPO / "assets" / "sprites" / "portraits"
RAW_DIR = PROJECT / "tmp" / "masterite_portrait_regen"
RAW_DIR.mkdir(parents=True, exist_ok=True)

COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

# Party cleric.png = the framing anchor (the "known-good portrait" style)
STYLE_ANCHOR = GAME_REPO / "assets" / "sprites" / "portraits" / "cleric.png"

# Per-world variants: `masterite_<role>_<world>.png` output naming +
# battle-strip identity ref per (role, world). Cowir-cutscenes confirmed
# per-world IDs (msg 2665) — 4 medieval first, W2-W5 as struktured reaches.
ROLES = ("warden", "tempo", "arbiter", "curator")
# STEAMPUNK WAS MISSING HERE and that is the whole reason W3 had no masterite portraits while
# every other world had four. The game has SIX worlds (CLAUDE.md: medieval / suburban / steampunk
# / industrial / futuristic / abstract); this tuple had five. A W3 cutscene then borrowed the
# INDUSTRIAL portraits, which is how the wrong-world costume shipped.
WORLDS = ("medieval", "suburban", "steampunk", "industrial", "futuristic", "abstract")

def _identity_ref(role: str, world: str) -> Path:
    return GAME_REPO / "assets" / "sprites" / "monsters" / f"masterite_{role}_{world}.png"

STYLE_PROMPT_PREFIX = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "helm/hood, and upper shoulders — head fills roughly 60% of frame, "
    "shoulders visible at bottom. Centered composition on a fully "
    "transparent background. Same clean pixel-art style, palette, and "
    "shading discipline as classic Final Fantasy VI / Chrono Trigger "
    "villain portraits: bold outlines, soft cel shading, no anti-aliasing "
    "artifacts, no floating pixels, no duplicate limbs, no weapons in "
    "frame, no scenery. Menacing but composed — these are teacher-bosses, "
    "not raving monsters. "
)

PERSONAS = {
    "warden": (
        "Character: the WARDEN OF THE OLD GUARD — an ancient armored knight "
        "who has guarded the world's balance since its creation, armor scarred "
        "from a thousand tests of strength. Golden pauldrons and helm crown "
        "with red gem, gold-inlaid battered plate mail at the shoulders, cool "
        "gray eyes glinting under the helm-shadow, gray beard or heavy jaw. "
        "Authority-figure read: patient, uncompromising, respected. NOT feral, "
        "NOT snarling — a knight who has SEEN every possible strike. Deep "
        "blue-and-gold heraldic palette matching the medieval Warden battle "
        "strip. Weathered, powerful, still."
    ),
    "tempo": (
        "Character: TEMPO OF THE HUNT — a swift ranger-scout who appears and "
        "vanishes like the wind, testing whether you can match its relentless "
        "pace. Anthropomorphic fox-like features (pointed ears, sharp amber "
        "eyes, angular muzzle), dark forest-green hood pulled up over the head, "
        "sharp intense focused gaze, tattered leather scout armor at the "
        "shoulders. Restless-clockwork energy — reads like a predator mid-tempo "
        "already deciding on the next strike. Matches the medieval Tempo of "
        "the Hunt battle strip: fox-warrior scout with bow and shield. Ears "
        "and hood dominate the silhouette top."
    ),
    "arbiter": (
        "Character: ARBITER OF STEEL — a dual-wielding swordmaster who measures "
        "every blow with mathematical precision, seeks the perfect strike. "
        "Deep-red judicial robes with high collar, silver-white hair pulled "
        "severely back, cold pale piercing eyes (blue or gray), a small silver "
        "circlet or judge's band across the forehead, ascetic thin face. "
        "Cold-judicial read: uninterested in mercy, interested in whether your "
        "form was CORRECT. No visible weapons in the bust framing but the "
        "posture reads swordmaster-at-rest. Matches the medieval Arbiter of "
        "Steel battle strip: robed judge palette (dark red + gold accents)."
    ),
    "curator": (
        "Character: CURATOR OF THE FLAME — a robed figure wreathed in "
        "controlled flame, judges how wisely you spend your power. Deep-red "
        "ceremonial priest's robes with a tall crown or ornate hood, half the "
        "face wreathed in soft orange-gold flame that curls upward past the "
        "cheek (flame is CONTAINED, doesn't burn — a symbol of control not "
        "chaos), calm dark eyes visible through the flame's veil. Warm "
        "gold-and-crimson palette matching the medieval Curator of the Flame "
        "battle strip (fire-torch priest). Obsessive-archivist calm — "
        "cataloging your every move as they burn."
    ),
}


## Per-WORLD personas, because a masterite is NOT the same character across worlds -- the shipped
## names and descriptions differ completely. PERSONAS above describes the medieval set; generating
## steampunk from it would have produced four medieval knights in the wrong world, which is the
## failure this whole gap came from. Written from data/monsters.json + data/bestiary.json, never
## from the generator's own earlier copy.
WORLD_PERSONAS = {
    ("tempo", "steampunk"): (
        "Character: THE GRAND SCHEDULE — not a figure so much as a cadence given a body. "
        "A tall brass-and-iron station-master silhouette: peaked conductor's cap, a face that is "
        "a clock dial with no hands, high stiff collar over a long dark coat with brass buttons "
        "and pressure-gauge fittings at the shoulders. Steam curls from vents at the collar. "
        "Utterly still and utterly punctual — the trains arrive on time because it is standing "
        "here. Not menacing by posture; menacing by INEVITABILITY. Brass, soot-black and signal-"
        "lamp amber palette matching the steampunk Tempo battle strip."
    ),
    ("arbiter", "steampunk"): (
        "Character: THE TOLERANCE LIMIT — machining tolerance expressed as violence. A precise "
        "machinist-judge: polished steel half-mask with a caliper-jaw across the lower face, one "
        "eye replaced by a brass micrometer lens with etched graduations, close-cropped hair, "
        "high-collared grey workshop coat with steel pauldrons. Expression measured, not cruel — "
        "a caliper is not cruel. Cold steel, oiled grey and thin red-line palette matching the "
        "steampunk Arbiter battle strip."
    ),
    ("curator", "steampunk"): (
        "Character: THE REQUISITION — it does not damage you, it BILLS you. A ledger-clerk of a "
        "creature: brass pince-nez over narrow accounting eyes, green accountant's visor, a high "
        "starched collar, dark waistcoat hung with seals, stamps and a chained brass tally-counter "
        "at the shoulder. Ink-stained fingers implied at the frame edge. Bureaucratic patience, "
        "faintly pleased. Ledger-green, tarnished brass and ink-black palette matching the "
        "steampunk Curator battle strip."
    ),
    ("warden", "industrial"): (
        "Character: THE WARDEN OF THE ASSEMBLY LINE — a massive industrial enforcer built from "
        "factory parts, testing structural integrity by applying overwhelming force. A hulking "
        "head and shoulders assembled from press-brake steel and stamped plate: a welded visor "
        "slot instead of eyes, hydraulic rams flanking the neck, heavy shoulder yokes hung with "
        "chain and safety-yellow hazard striping worn to bare metal. No face — the read is "
        "MACHINE THAT TESTS, patient and absolute. You may fail safely; you may not fail "
        "creatively. Soot-grey steel, hazard yellow and oil-black palette matching the industrial "
        "Warden battle strip."
    ),
    ("arbiter", "futuristic"): (
        "Character: THE ARBITER OF THE BENCHMARK — a performance-testing intelligence that grades "
        "you against the ninetieth percentile and raises its own difficulty until you match. A "
        "sleek synthetic head: smooth matte-white faceplate with no mouth, a single horizontal "
        "scanline visor glowing cyan across where eyes would be, thin data-cable braids falling "
        "from the skull to high angular shoulders, small floating percentile glyphs at the frame "
        "edge. Utterly composed, analytical, uninterested in whether you survive — interested in "
        "your SCORE. Cold white, cyan scanline and graphite palette matching the futuristic "
        "Arbiter battle strip. Clean sci-fi, not fantasy."
    ),
    ("curator", "abstract"): (
        "Character: THE CURATOR OF ENTROPY — resource decay incarnate, the heat death of your "
        "reserves, the Master's final accountant. A robed bust: deep hood over a face that is an "
        "ABSENCE, two faint cold points where eyes were, high collar, narrow skeletal shoulders. "
        "The lower edge of the robe frays into a few loose pixels, as if the figure is coming "
        "apart at its own outline. Not menacing by aggression; menacing by INEVITABILITY. Washed "
        "bone-white, void-grey and faint violet palette matching the abstract Curator battle "
        "strip. "
        "⚠️ CRITICAL: the fraying is CONFINED TO THE SILHOUETTE'S OWN EDGE. Absolutely NO haze, "
        "fog, mist, dust, particles, glow or void filling the frame around the figure — the area "
        "outside the bust must be FULLY TRANSPARENT, zero alpha, not a dark or textured "
        "background. Three consecutive rolls returned a fully opaque image; the subject is the "
        "figure alone."
    ),
    ("warden", "suburban"): (
        "Character: THE WARDEN OF ROUTINE, the Hall Monitor Eternal — a suburban school hall "
        "monitor who, through forty years of unbroken routine, became the thing he enforced. "
        "Late-middle-aged man, thinning grey hair combed flat, thick square glasses, utterly "
        "level expression. A laminated ID badge on a lanyard at the collar, a plain windbreaker "
        "over a polo with a small crest, a whistle resting against the chest, a hall-pass clip "
        "at the shoulder. HE DOES NOT RAISE HIS VOICE — the read is bureaucratic patience that "
        "has outlasted everyone who ever argued with it. Faded suburban palette: beige, muted "
        "navy windbreaker, fluorescent-lit skin tones, matching the suburban Warden battle strip. "
        "16-bit EarthBound-adjacent, not fantasy."
    ),
    ("warden", "steampunk"): (
        "Character: THE STANDING ORDER — a pressure gauge that has never once moved off the red. "
        "A vast riveted boiler-knight: domed iron helm with a single round gauge-face set into "
        "the brow, needle pinned hard right in the red, heavy riveted shoulder plates venting "
        "thin steam, no visible eyes. It does not attack so much as OUTLAST. Immovable, patient, "
        "industrial. Riveted iron, hot-red gauge glow and soot palette matching the steampunk "
        "Warden battle strip."
    ),
}


def persona_for(role: str, world: str) -> str:
    return WORLD_PERSONAS.get((role, world), PERSONAS[role])


def load_ref_bytes(path: Path, is_battle_strip: bool = False) -> bytes:
    """Load a reference PNG, cropping to first frame if it's a battle strip."""
    img = Image.open(path).convert("RGBA")
    if is_battle_strip:
        # Battle strips are horizontal — take the first square frame
        H = img.size[1]
        img = img.crop((0, 0, H, H))
    # Upscale to 1024 for the API (nearest to preserve pixel art)
    target = 1024
    scale = target / max(img.size)
    new_w, new_h = int(img.size[0] * scale), int(img.size[1] * scale)
    img = img.resize((new_w, new_h), Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)
    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def downscale_to_portrait(img_1024: Image.Image, target: int = 256) -> Image.Image:
    img = img_1024.convert("RGBA")
    intermediate = target * 4
    img = img.resize((intermediate, intermediate), Image.LANCZOS)
    img = img.resize((target, target), Image.BOX)
    return img


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


## The prompt says "fully transparent background" and NOTHING checked that it came back that way.
## Measured 2026-09-11: 2 of 3 rolls in one batch returned a 100%-opaque image -- a solid
## rectangle that renders as a BLACK BOX behind the speaker in the dialogue panel. The other roll
## in the same batch was clean, so it is a bad ROLL, not a bad prompt, and re-rolling fixes it.
##
## Chroma-keying instead would be the wrong repair here: these subjects are near-black steel and
## bone-white void, so a corner-seeded key can eat the figure. That is this lane's own 2026-09-09
## defect, where a second chromakey pass wiped the subject out of 40 sheets.
class OpaqueBackdrop(RuntimeError):
    """Recoverable by RE-ROLLING. Raised inside the retry loop so a bad roll costs one more call,
    not the batch."""


def _refuse_opaque_backdrop(img: Image.Image, attempt: int, max_retries: int) -> None:
    rgba = img.convert("RGBA")
    w, h = rgba.size
    a = rgba.getchannel("A")
    corners = [a.getpixel(p) for p in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
    if max(corners) < 10:
        return
    opaque = sum(1 for v in a.getdata() if v > 10) / float(w * h)
    raise OpaqueBackdrop(
        "returned image has an OPAQUE backdrop (corner alphas %s, %.0f%% opaque) -- the contract "
        "is a transparent bust; this renders as a solid box behind the speaker" % (corners, 100 * opaque))


def call_gpt_image(client, prompt: str, ref_files: list, quality: str,
                   max_retries: int = 3) -> Image.Image:
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(
                model="gpt-image-1",
                image=ref_files,
                prompt=prompt,
                size="1024x1024",
                quality=quality,
                n=1,
            )
            b64 = resp.data[0].b64_json
            img = Image.open(io.BytesIO(base64.b64decode(b64)))
            _refuse_opaque_backdrop(img, attempt, max_retries)
            return img
        except OpaqueBackdrop as e:
            print(f"    re-roll {attempt + 1}/{max_retries}: {e}", flush=True)
            if attempt == max_retries - 1:
                raise
            continue
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg:
                wait = 30 * (attempt + 1)
                print(f"    Rate limit; backing off {wait}s...")
                time.sleep(wait)
            elif any(k in msg for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"    Error: {e}; retry {attempt+1}/{max_retries}")
                time.sleep(5)
    raise RuntimeError(f"Failed after {max_retries} retries")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--roles", nargs="+", default=list(ROLES))
    ap.add_argument("--worlds", nargs="+", default=["medieval"],
                    help="World variants to generate (default: medieval only)")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    unknown = [w for w in args.worlds if w not in WORLDS]
    if unknown:
        print(f"ERROR: unknown world(s) {unknown}; known: {list(WORLDS)}", file=sys.stderr)
        return 2
    pairs = [(r, w) for r in args.roles for w in args.worlds if r in PERSONAS]
    if args.dry_run:
        total = COST[args.quality] * len(pairs)
        print(f"DRY RUN — would generate {len(pairs)} portraits at "
              f"{args.quality} (~${total:.3f})")
        for r, w in pairs:
            ref = _identity_ref(r, w)
            print(f"  {r}/{w}: identity ref = {ref.name} (exists: {ref.exists()})")
        return 0

    if not STYLE_ANCHOR.exists():
        print(f"ERROR: style anchor missing: {STYLE_ANCHOR}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI()
    total_cost = 0.0
    unit = COST[args.quality]

    for role, world in pairs:
        ref_battle = _identity_ref(role, world)
        if not ref_battle.exists():
            print(f"SKIP {role}/{world}: battle ref missing at {ref_battle}")
            continue

        prompt = STYLE_PROMPT_PREFIX + persona_for(role, world)
        style_bytes = load_ref_bytes(STYLE_ANCHOR, is_battle_strip=False)
        identity_bytes = load_ref_bytes(ref_battle, is_battle_strip=True)
        refs = [
            ("ref_style.png", style_bytes, "image/png"),
            ("ref_identity.png", identity_bytes, "image/png"),
        ]

        print(f"[{role}/{world}] gpt-image-1 ({args.quality}, ${unit:.3f}) "
              f"identity={ref_battle.name}")
        raw = call_gpt_image(client, prompt, refs, args.quality)
        raw_path = RAW_DIR / f"masterite_{role}_{world}_raw_{args.quality}.png"
        raw.save(raw_path)

        portrait = downscale_to_portrait(raw, 256)
        portrait = remove_flat_background(portrait)
        out_path = OUT_DIR / f"masterite_{role}_{world}.png"
        portrait.save(out_path)
        print(f"  → {out_path.relative_to(GAME_REPO)}")

        total_cost += unit

    print(f"\nTotal spent: ${total_cost:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
