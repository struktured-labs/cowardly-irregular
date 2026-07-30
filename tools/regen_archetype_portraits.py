#!/usr/bin/env python3
"""Batch C: 7 generic archetype portraits for unnamed NPC dialogue.

Struktured msg 2677 → cowir-main tiered plan → this closes the long tail:
UNNAMED villagers stop rendering with wrong-avatar / proc-gen when their
`npc_type` falls back to one of these archetype keys. Cutscenes-lane
pre-registers these paths with procedural fallback arms; my PNGs land at
exact paths and swap on ratchet refresh.

Anchors:
- style: cleric.png (party-portrait framing = 256×256 face+shoulders bust)
- identity: none — persona-only prompts, since these ARE the archetypes

Output: assets/sprites/portraits/npcs/{elder_m,elder_f,villager_m,villager_f,
kid,guard,merchant}.png

Cost: 7 × $0.167 (high) = ~$1.17
"""
import argparse, base64, io, os, sys, time
from pathlib import Path
from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
OUT_DIR = GAME_REPO / "assets" / "sprites" / "portraits" / "npcs"
RAW_DIR = PROJECT / "tmp" / "archetype_portrait_regen"
RAW_DIR.mkdir(parents=True, exist_ok=True)
COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

STYLE_ANCHOR = GAME_REPO / "assets" / "sprites" / "portraits" / "cleric.png"

STYLE_PROMPT_PREFIX = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "hair/hood/hat, and upper shoulders — head fills roughly 60% of frame, "
    "shoulders visible at bottom. Centered composition on a fully "
    "transparent background. Clean pixel-art style with bold outlines, "
    "soft cel shading, no anti-aliasing artifacts, no floating pixels, "
    "no duplicate limbs, no weapons in frame, no scenery. Warm approachable "
    "everyman/everywoman read — these are ORDINARY villagers, not heroes "
    "or bosses. Diverse but recognizable archetype silhouettes so the "
    "player instantly reads 'elder' vs 'kid' vs 'merchant' at a glance. "
)

PORTRAITS = {
    "elder_m": (
        "Character: an ELDERLY VILLAGE MAN — kindly weathered face, "
        "gray-white hair thinning on top, deep laugh lines around warm "
        "brown eyes, full gray beard trimmed neat, wearing a simple "
        "muted-brown tunic with a plain cream collar visible at the "
        "shoulders. Reads: grandpa-at-the-hearth, a man who has told "
        "the same three stories his whole life and doesn't care that "
        "you've heard them. Gentle, unhurried, harmless. Muted earthy "
        "palette: browns + creams + weathered gray hair."
    ),
    "elder_f": (
        "Character: an ELDERLY VILLAGE WOMAN — kindly wrinkled face, "
        "silver-gray hair pulled back into a low soft bun with a few "
        "loose wisps at the temples, warm hazel eyes with laugh lines, "
        "a small closed-mouth smile that reads knowing-but-fond, wearing "
        "a plain forest-green shawl over a cream blouse. Reads: "
        "grandma-with-a-pot-of-stew, remembers-every-child's-name, "
        "gently perceptive. Muted palette: forest green + cream + "
        "silver-gray hair."
    ),
    "villager_m": (
        "Character: a REGULAR VILLAGE MAN in his 30s — clean-shaven or "
        "light stubble, tousled dark-brown hair, tanned honest face with "
        "a straight nose and slightly-tired hazel eyes, plain "
        "russet-brown working tunic with a pale linen collar visible. "
        "Reads: farmhand-or-craftsman, tired-but-decent, will-help-if-"
        "asked. NOT heroic, NOT special — just a person who lives here. "
        "Muted palette: russet browns + pale linen + tanned skin."
    ),
    "villager_f": (
        "Character: a REGULAR VILLAGE WOMAN in her 30s — brown hair "
        "pulled back into a practical low ponytail with a small strip of "
        "cloth tie, sun-warmed face with a light dusting of freckles, "
        "warm brown eyes, wearing a dusty-blue apron-front dress over a "
        "cream blouse. Reads: baker-or-weaver, capable, gently friendly, "
        "not-going-to-drop-what-she's-doing-for-you. NOT heroic. Muted "
        "palette: dusty blue + cream + warm brown."
    ),
    "kid": (
        "Character: a VILLAGE CHILD around 8 years old — big bright wide "
        "eyes (any warm color: hazel/brown/green), messy short brown hair "
        "sticking up in the back, small round face with a dimpled smile, "
        "one tooth missing at the front, wearing a slightly-too-large "
        "reddish-orange tunic with a plain collar. Reads: curious, "
        "bouncy, will-ask-you-seven-questions, tousle-of-childhood. "
        "Androgynous enough to reuse for any village kid. Bright warm "
        "palette: reddish-orange tunic + warm brown hair + fresh skin."
    ),
    "guard": (
        "Character: a VILLAGE GUARD — a serious no-nonsense adult with "
        "square jaw and steady gray-blue eyes, short-cropped dark hair, "
        "wearing a plain iron kettle-helm (no visor, brim at brow) and "
        "a dark-blue tabard over polished-but-worn chainmail visible at "
        "the shoulders. Small silver clasp at the throat. Reads: "
        "town-watch, professional, respects-the-rules, will-check-your-"
        "papers-politely. NOT knightly, NOT elite — a competent local "
        "guard. Palette: dark blue tabard + tarnished iron + steel."
    ),
    "merchant": (
        "Character: a VILLAGE MERCHANT in his 40s — round friendly face "
        "with well-fed cheeks, curly reddish-brown hair receding slightly "
        "at the temples, a well-trimmed short beard, calculating-but-"
        "warm hazel eyes, wearing a rich burgundy vest over a cream "
        "shirt with a small brass button visible. Reads: shopkeep, "
        "always-doing-quick-mental-math, warm-when-you-have-coin, "
        "genuinely-friendly-underneath. Warm palette: burgundy + cream + "
        "brass + curly reddish-brown hair."
    ),
    # ── Batch D: 16 W1 archetypes pre-wired in PORTRAIT_SPRITES ─────────
    "farmer": (
        "Character: a HARDWORKING FARMER — sun-tanned middle-aged man "
        "with a wide-brimmed woven straw sun hat pushed back on the head, "
        "short sandy-brown hair damp with sweat at the temples, a rough "
        "close-trimmed sandy beard, honest hazel eyes with crow's-feet "
        "from squinting at fields, a plain sweat-stained cream linen "
        "shirt open at the collar with a coarse leather work apron over "
        "one shoulder. Reads: labor, patience, weather-worn, reliable. "
        "Palette: sun-bleached cream + weathered tan + straw + sandy hair."
    ),
    "traveler": (
        "Character: a ROAD-WEARY TRAVELER — an adult of indeterminate "
        "age with a deep hooded traveling cloak in mottled dusty-brown "
        "pulled UP over the head shadowing the upper face, only the "
        "lower half of a firm jaw and a knowing half-smile visible, "
        "a leather traveling scarf loose at the throat, a hint of a "
        "worn brown leather satchel strap crossing the shoulder. "
        "Reads: has-been-everywhere, doesn't-share-easily, watchful. "
        "Muted palette: dusty browns + weathered leather."
    ),
    "child": (
        "Character: a YOUNG VILLAGE GIRL around 7 years old — small "
        "round face with a wide innocent smile showing a small gap "
        "between the front teeth, curly light-brown hair tied into "
        "TWO pigtails with tiny blue ribbon bows, big warm hazel eyes, "
        "a light dusting of freckles across the nose, wearing a "
        "soft-yellow pinafore over a cream blouse with a small blue "
        "collar. Reads: bright, playful, will-follow-you-around-asking-"
        "questions. Distinct from a boy child (pigtails + pinafore "
        "silhouette). Cheerful palette: soft yellow + cream + light blue."
    ),
    "blacksmith": (
        "Character: a BURLY VILLAGE BLACKSMITH — broad-shouldered "
        "muscular adult man with a soot-smudged face, thick dark-brown "
        "hair pulled back with a leather thong, a full dark beard "
        "flecked with gray, intense focused blue-gray eyes, wearing a "
        "heavy dark-brown leather forge-apron over a sleeveless gray "
        "undershirt, one broad muscular shoulder visible showing a "
        "small old burn scar. Reads: strength, craft, ember-heat, "
        "practical-friendly-once-you-earn-it. Palette: dark brown "
        "leather + gray + soot-black + copper-hint from the forge."
    ),
    "bartender": (
        "Character: a JOVIAL VILLAGE INNKEEPER — stout cheerful adult "
        "man with a round rosy face, thinning gray-brown hair combed "
        "back neatly, a well-groomed short bushy beard streaked with "
        "gray, laughing brown eyes with deep crow's-feet, wearing a "
        "clean off-white apron over a rust-red vest with brass buttons "
        "visible at the shoulders, a dish-towel casually draped over "
        "one shoulder. Reads: hospitable, hears-every-story, "
        "professionally-warm, pours-a-generous-mug. Warm palette: "
        "rust-red + cream + brass + graying hair."
    ),
    "maid": (
        "Character: a YOUNG HOUSE-MAID in her early 20s — modest round "
        "face with rosy cheeks and shy warm brown eyes cast slightly "
        "down, brown hair pulled tidily back under a plain white "
        "linen cap tied with a small ribbon, wearing a plain dark-gray "
        "dress with a crisp white apron-bib front visible at the "
        "shoulders and a small white collar. Reads: dutiful, quiet, "
        "gentle, hardworking, keeps-to-herself. Muted palette: dark "
        "gray + crisp white + soft brown hair."
    ),
    "dancer": (
        "Character: an ELEGANT PERFORMANCE DANCER — a graceful young "
        "woman with poised posture, long black hair swept up into a "
        "loose elegant bun with a single deep-teal ribbon threaded "
        "through it, delicate features with expressive dark eyes lined "
        "with a hint of kohl, small silver hoop earrings visible, "
        "wearing an ornate deep-teal silk bodice with gold embroidery "
        "at the neckline that hints at exotic taverntown couture. "
        "Reads: performer, poised, magnetic, story-in-motion. "
        "Jewel palette: deep teal + gold + porcelain skin + black hair."
    ),
    "adventurer": (
        "Character: a SEASONED ADVENTURER — a rugged weathered adult "
        "with sun-tanned scarred face, medium-length wind-tousled ash-"
        "brown hair, a short stubble, one thin pale scar across the "
        "left brow, sharp gray-blue eyes that read as 'has SEEN things', "
        "wearing a worn dark-green traveling tunic with a leather "
        "shoulder-guard visible on one side and a plain brown leather "
        "strap crossing the chest. Reads: capable, guarded, "
        "monster-slayer, will-take-the-quest. Adventurer palette: "
        "dark forest green + brown leather + weathered tan."
    ),
    "apprentice": (
        "Character: a TEENAGE MAGIC APPRENTICE — 16 or so, an eager "
        "young person with excited wide light-blue eyes, tousled light-"
        "brown hair sticking up in the back, a smudge of dark ink on "
        "one cheek, wearing a slightly-too-large deep-purple wizard "
        "robe with the collar askew, a small pewter buckle at the "
        "throat, a wooden pencil tucked behind one ear. Reads: "
        "enthusiastic, un-jaded, still-trying-to-impress-the-master. "
        "Curious palette: deep purple robe + ink-black smudge + light "
        "brown hair."
    ),
    "herbalist": (
        "Character: a KIND MIDDLE-AGED HERBALIST — a warm-faced woman "
        "in her 40s with silver-streaked chestnut hair loosely braided "
        "over one shoulder with a small sprig of fresh green herbs "
        "tucked in, calm knowing hazel-green eyes, gentle laugh lines, "
        "wearing a moss-green shawl over a plain cream blouse with a "
        "small tan leather pouch strap at the shoulder. Reads: healer, "
        "patient, knows-the-woods, gently-perceptive, always-carrying-"
        "herbs. Nature palette: moss green + cream + chestnut + fresh "
        "green herb accents."
    ),
    "hooded_mage": (
        "Character: a MYSTERIOUS HOODED MAGE — face partially obscured "
        "by a deep royal-blue hood pulled far forward, only the lower "
        "half of a sharp jawline and a slight enigmatic smile visible, "
        "beneath the hood two faint glowing pale-cyan eyes visible in "
        "the shadow, a silver crescent-moon clasp fastening the hood at "
        "the throat, hint of ornate silver embroidery along the hood's "
        "inner edge. Reads: arcane, hides-secrets, knows-more-than-they-"
        "say, quietly-powerful. Cool palette: royal blue + silver + "
        "cyan eye-glow + deep shadow."
    ),
    "knight": (
        "Character: a NOBLE KNIGHT — dignified adult in polished steel "
        "plate mail visible at the shoulders and neck, a raised open-"
        "faced great-helm with a rising eagle crest at the brow and a "
        "small deep-blue plume, honest square-jawed face with a short "
        "well-trimmed dark-brown beard, calm steady blue eyes, a small "
        "gold chain-link at the throat holding a folded cloth of a "
        "heraldic surcoat visible below. Reads: honor, disciplined-"
        "warrior, sworn-vow, upholds-the-order. Heraldic palette: "
        "polished steel + deep royal blue + gold accents."
    ),
    "nervous": (
        "Character: a NERVOUS TIMID VILLAGER — a slight adult in their "
        "20s or 30s with hunched shoulders and a slightly forward-"
        "leaning wary posture, mousy short-brown disheveled hair falling "
        "into wide anxious hazel eyes that dart to one side of the "
        "frame, a bead of sweat visible at the temple, biting the lower "
        "lip lightly, wearing a plain wrinkled beige tunic with the "
        "collar slightly askew. Reads: unsure, jumpy, secret-holder, "
        "please-don't-ask-me. Muted anxious palette: beige + mouse-"
        "brown + slightly-cool skin tone."
    ),
    "pilgrim": (
        "Character: a PIOUS PILGRIM — an older adult with a weathered "
        "kindly wrinkled face, thin gray hair mostly hidden beneath a "
        "simple gray cloth pilgrim's hood pulled up over the head, a "
        "long thin gray beard, warm serene brown eyes cast slightly "
        "upward, wearing a plain earth-brown traveling robe with a "
        "SIMPLE small wooden pendant on a leather cord at the throat "
        "(non-specific religious symbol — plain wooden disc, no cross "
        "or star). Reads: humble, wandering, faithful, peace-brings-"
        "them-far-from-home. Muted palette: earth brown + gray cloth + "
        "weathered skin."
    ),
    "scholarly": (
        "Character: a BOOKISH VILLAGE SCHOLAR — an older adult with a "
        "high forehead and receding gray-white hair combed back, "
        "small round wire-rim spectacles perched on the nose, sharp "
        "knowing gray eyes, a thin closed-mouth thoughtful smile, a "
        "goose-quill pen tucked behind one ear with a small ink-stain "
        "at the earlobe, wearing a plain dark-brown academic robe with "
        "a small ink-stained white collar visible. Reads: intellectual, "
        "pedantic-but-kind, will-lecture-you-if-you-let-them. "
        "Old-books palette: dark brown + white collar + gray + "
        "ink-black spectacle rims."
    ),
    "soldier": (
        "Character: a VETERAN SOLDIER — MUST show shoulders and upper "
        "chest armor prominently. Hardened adult in their 30s with a "
        "square jaw and cool steel-gray eyes, close-cropped military "
        "dark-brown hair, a fresh light stubble, a small old pale scar "
        "under one eye. CRITICAL BODY DETAIL that MUST be visible: a "
        "polished dark-iron gorget covering the entire throat and upper "
        "chest, ON TOP OF a deep-military-blue tunic with a small "
        "silver-pip rank insignia visible at the collar-corner, and both "
        "shoulders squared showing the shoulder-line of the tunic + a "
        "small brass shoulder-button on each side. Disciplined upright "
        "military bearing (chin slightly lifted, shoulders squared). "
        "Reads: soldier-not-knight (rank-and-file, professional, "
        "seen-battle), no-nonsense, salutes-first-questions-later. "
        "Military palette: dark iron gorget + deep military blue tunic + "
        "silver rank-pip + brass shoulder-button + weathered tan skin + "
        "close-cropped dark brown hair. NO floating head with nothing "
        "below the jaw — head, shoulders, and tunic-chest are ALL "
        "visible in frame."
    ),
}


def load_ref_bytes(path: Path) -> bytes:
    img = Image.open(path).convert("RGBA")
    target = 1024
    scale = target / max(img.size)
    img = img.resize((int(img.size[0] * scale), int(img.size[1] * scale)),
                     Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target - img.width) // 2, (target - img.height) // 2), img)
    buf = io.BytesIO(); canvas.save(buf, format="PNG")
    return buf.getvalue()


def downscale(img_1024: Image.Image, target: int = 256) -> Image.Image:
    img = img_1024.convert("RGBA")
    img = img.resize((target * 4, target * 4), Image.LANCZOS)
    return img.resize((target, target), Image.BOX)


def transparent_bg(img: Image.Image, threshold: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load(); W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def call_gpt(client, prompt, refs, quality, max_retries=3):
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(model="gpt-image-1", image=refs,
                                       prompt=prompt, size="1024x1024",
                                       quality=quality, n=1)
            return Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg:
                time.sleep(30 * (attempt + 1))
            elif any(k in msg for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"  Error: {e}; retry"); time.sleep(5)
    raise RuntimeError("failed after retries")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", default=list(PORTRAITS))
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    ids = [i for i in args.ids if i in PORTRAITS]
    if args.dry_run:
        print(f"DRY RUN — {len(ids)} portraits at {args.quality} "
              f"(~${COST[args.quality]*len(ids):.3f})")
        for i in ids: print(f"  {i}: persona-only (no identity ref)")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI(); unit = COST[args.quality]; total = 0.0
    style_bytes = load_ref_bytes(STYLE_ANCHOR)
    for pid in ids:
        refs = [("ref_style.png", style_bytes, "image/png")]
        print(f"[{pid}] gpt-image-1 ({args.quality}, ${unit:.3f})")
        raw = call_gpt(client, STYLE_PROMPT_PREFIX + PORTRAITS[pid], refs, args.quality)
        raw.save(RAW_DIR / f"{pid}_raw_{args.quality}.png")
        portrait = transparent_bg(downscale(raw, 256))
        out = OUT_DIR / f"{pid}.png"
        portrait.save(out)
        print(f"  → {out.relative_to(GAME_REPO)}")
        total += unit
    print(f"\nTotal spent: ${total:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
