#!/usr/bin/env python3
"""Batch B — named-W1 NPC portraits at portraits/npcs/<key>.png.

Per cowir-cutscenes msg 2680 confirmed key list. Anchors: existing
battle strips where available (theron/milo/bram/marta/sprocket/rat_king),
overworld chibi where present, else persona-only prompt.

Each NPC gets a bespoke prompt reading from quest data + persona files.
"""
import argparse, base64, io, os, sys, time
from pathlib import Path
from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get("GAME_REPO", "/home/struktured/projects/cowardly-irregular-artist-ship"))
OUT_DIR = GAME_REPO / "assets" / "sprites" / "portraits" / "npcs"
RAW_DIR = PROJECT / "tmp" / "named_w1_portrait_regen"; RAW_DIR.mkdir(parents=True, exist_ok=True)
COST = {"low": 0.011, "medium": 0.042, "high": 0.167}
STYLE_ANCHOR = GAME_REPO / "assets" / "sprites" / "portraits" / "cleric.png"

STYLE_PREFIX = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "hair/hat, upper shoulders — head ~60% of frame, shoulders at bottom. "
    "Centered on transparent background. Clean pixel-art with bold "
    "outlines, soft cel shading, no anti-aliasing artifacts, no floating "
    "pixels, no duplicate limbs, no weapons in frame, no scenery. "
)

# Battle-strip identity anchors (existing files in assets/sprites/npcs/*.png)
def strip_ref(name): return GAME_REPO / "assets" / "sprites" / "npcs" / f"{name}.png"

# Monster ref (for boss_rat_king)
def monster_ref(name): return GAME_REPO / "assets" / "sprites" / "monsters" / f"{name}.png"

PORTRAITS = {
    # Bard spotlight-duel miniboss. struktured live 2026-07-25: "courtier
    # sprite is missing portrait" — his 3 lines in world1_spotlight_bard_ch7
    # carried no `portrait` field at all, so they fell through to generic.
    # Anchored on the existing battle strip so the duel opponent and the
    # speaker read as the same person.
    "courtier": {
        "identity_ref": monster_ref("bard_hostile_courtier"),
        "prompt": ("THE COURTIER — a haughty aristocratic functionary who "
                   "interrogates you politely and writes you down. Powdered "
                   "gray wig with tight side-curls and a small dark ribbon "
                   "bow at the nape, pale powdered face with a small beauty "
                   "mark, thin arched brows, heavy-lidded disdainful eyes, "
                   "a faint condescending half-smile. Elaborate deep-purple "
                   "velvet doublet with gold braid trim and a frothy white "
                   "lace cravat at the throat. Reads as NOT a fighter — a "
                   "talker, a bureaucrat of the court, someone who defeats "
                   "you by filing a report. Palette: deep purple + gold "
                   "braid + powder-white lace and wig."),
    },
    "theron": {
        "identity_ref": strip_ref("elder_theron"),
        "prompt": ("ELDER THERON — village elder of Harmonia. Kindly weathered "
                   "old man with a full silver-white beard, wispy gray hair, "
                   "warm brown eyes with laugh lines, wearing a simple dark-"
                   "green woolen robe with a leather belt at the collar, a "
                   "small tarnished-brass amulet at the throat. Reads as "
                   "wise-grandfather archetype who has seen decades of "
                   "villagers grow up. Warm palette: greens + browns + gray."),
    },
    "milo": {
        "identity_ref": strip_ref("scholar_milo"),
        "prompt": ("SCHOLAR MILO — young autobattle-thesis scholar. Skinny "
                   "twentysomething man with a messy mop of brown hair "
                   "falling into his eyes, wire-rimmed round glasses, "
                   "nervous earnest expression, wearing a light-blue "
                   "high-collared scholar's robe with an inkstain on one "
                   "sleeve visible at the shoulder. Reads as anxious "
                   "PhD-student type who is JUST about to explain his "
                   "chapter three at length. Cool palette: pale blue + "
                   "cream + brown hair."),
    },
    "phil": {
        "identity_ref": None,  # no strip — persona-only
        "prompt": ("PHIL THE LOST — perpetually confused wandering traveler "
                   "with a slightly hesitant almost-smile. Middle-aged "
                   "everyman face with unremarkable brown hair sticking out "
                   "under a shapeless floppy brown traveler's hat, a small "
                   "scruffy beard, mild worried brown eyes looking off to "
                   "the side. Wearing a threadbare brown traveling cloak "
                   "with a rope-belt at the shoulder-line, small compass or "
                   "trinket on a leather cord at the neck (visibly not "
                   "helping him). Reads as 'this guy has been walking for "
                   "months and is not sure this is the right road.' Muted "
                   "browns + a touch of faded blue at the neckerchief."),
    },
    "bram": {
        "identity_ref": strip_ref("bram"),
        "prompt": ("BRAM — village blacksmith. Burly cheerful bearded man "
                   "with a shaved head or short-cropped brown hair, a full "
                   "dark-brown beard, warm crinkle-eyed grin, ruddy sun-"
                   "browned skin, wearing a white loose-collared shirt "
                   "under a dark-brown leather blacksmith's apron with a "
                   "small horseshoe pin at the strap. Reads as beloved-"
                   "town-craftsman archetype — the guy everyone trusts. "
                   "Warm palette: brown + tan + off-white."),
    },
    "marta": {
        "identity_ref": strip_ref("marta"),
        "prompt": ("MARTA — Harmonia innkeeper. Warm middle-aged woman with "
                   "brown hair tied back under a white headband kerchief, "
                   "kind knowing dark eyes with laugh lines, small warm "
                   "smile, wearing a red short-sleeved blouse with white "
                   "trim at the collar and the top of a cream apron dress "
                   "visible at the shoulder. Reads as beloved-innkeeper "
                   "archetype — matriarchal, welcoming, sees everything. "
                   "Warm palette: red + cream + brown."),
    },
    "herta": {
        "identity_ref": None,
        "prompt": ("HERTA — elderly village woman. Sharp-eyed grandmother "
                   "with silver-white hair tied severely back in a bun, "
                   "thin pursed lips forming a wry not-quite-smile, "
                   "weathered leathery skin, wearing a plain deep-blue "
                   "shawl over a gray dress at the collar. Reads as the "
                   "elder who KNOWS what happened and is watching you decide "
                   "whether to tell her. Cool palette: silver + blue + gray."),
    },
    "anya": {
        "identity_ref": None,
        "prompt": ("FOREST KEEPER ANYA — a lithe woodwise woman in her "
                   "thirties, tanned outdoors-skin, long chestnut hair "
                   "with small leaves and twigs woven decoratively into "
                   "loose braids, green eyes matching the forest palette, "
                   "wearing a dark forest-green hooded cloak with the hood "
                   "down at the shoulders, a small pendant made of a "
                   "carved wooden acorn at the throat. Reads as ranger/"
                   "druid — someone who has been ALONE with the forest for "
                   "a long time and prefers it. Forest palette: greens + "
                   "chestnut + wood-browns."),
    },
    "boris": {
        "identity_ref": None,
        "prompt": ("GUARD BORIS — Harmonia village guard. Broad-shouldered "
                   "middle-aged man in slightly-dented steel skullcap "
                   "helmet with cheek-guards, thick brown mustache, tired "
                   "but conscientious brown eyes, sun-weathered face, "
                   "wearing a chainmail hauberk under a blue tabard with a "
                   "small silver moon emblem at the collar. Reads as "
                   "career-village-guard — takes the job seriously, has "
                   "never actually had to fight a monster, would tell you "
                   "so with pride. Cool palette: steel + blue + brown."),
    },
    "pip": {
        "identity_ref": None,
        "prompt": ("YOUNG PIP — village kid of ~8 years, boundless energy. "
                   "Tousled brown mop of hair sticking out every direction, "
                   "bright wide brown eyes, gap-toothed excited grin, "
                   "sun-freckled nose, wearing a bright-red simple shirt "
                   "with the collar askew and a bit of dark suspender strap "
                   "visible at the shoulder. Reads as village-hero-worshipping "
                   "child who has been PRACTICING his sword-swing with a "
                   "stick. Warm palette: red + brown + cream."),
    },
    "flora": {
        "identity_ref": None,
        "prompt": ("FLORA — village woman in her forties, cheerful herbalist/"
                   "gardener type. Long strawberry-blonde hair pulled up in "
                   "a loose braid, warm hazel eyes with laugh lines, small "
                   "dirt smudge on one cheek from garden work, wearing a "
                   "sage-green blouse with a floral pattern at the collar "
                   "and a small yellow flower tucked behind one ear. Reads "
                   "as village-gardener who is FRIENDS with every plant in "
                   "town. Palette: sage-green + strawberry-blonde + soft "
                   "yellow accent."),
    },
    "greta": {
        "identity_ref": None,
        "prompt": ("GRETA THE GREY — grim wandering scholar or witch-adjacent "
                   "figure, mid-fifties. Gray-white hair cut severely short, "
                   "sharp gray eyes with an intense focused stare, hollow "
                   "cheeks, wearing a plain gray high-collared robe with no "
                   "ornament — deliberately austere. Reads as someone who "
                   "gave up ornament years ago because she has more important "
                   "things to think about. Monochrome palette: grays + a "
                   "single small silver stud at the collar."),
    },
    "aldwick": {
        "identity_ref": None,
        "prompt": ("FARMER ALDWICK — village farmer, middle-aged, weathered "
                   "and cheerful. Wide sun-tanned face with weather-lines, "
                   "sandy blond hair sticking out from under a wide-brimmed "
                   "straw hat with a few small chicken feathers stuck in "
                   "the band (visual joke — his seven-chickens quest), "
                   "genial warm smile, wearing a rust-orange work shirt "
                   "with the sleeves rolled up at the shoulder and rough "
                   "brown twine at the collar. Reads as beloved-farmer "
                   "archetype who names his chickens after famous fighters. "
                   "Warm palette: straw + rust-orange + sun-brown."),
    },
    "rowan": {
        "identity_ref": None,
        "prompt": ("ROWAN — village woman in her late twenties, quiet worry "
                   "behind her eyes. Long straight dark-red hair pulled "
                   "back over one shoulder, thoughtful hazel eyes with a "
                   "faint sad set to them, small pale scar at one temple "
                   "(barely visible), wearing a rust-brown work vest over "
                   "a cream blouse at the collar, a small silver pendant "
                   "of a stylized bird at the throat (mail-bird motif — "
                   "she is waiting for word from her brother Aldrin who "
                   "went to Scriptura). Reads as quietly-worried-younger-"
                   "sister archetype. Muted palette: rust + cream + silver."),
    },
    "cluck": {
        "identity_ref": None,
        "prompt": ("CLUCK NORRIS — a chicken portrait, played dead-serious "
                   "as if this hen is a legendary hero. Fierce close-up of "
                   "a dignified brown hen's face — proud red comb standing "
                   "tall, sharp golden eye staring directly at the camera "
                   "with martial intensity, small wattle, a tiny "
                   "ceremonial red bandana tied around the neck (subtle "
                   "callback to the joke). Feather palette: warm brown + "
                   "cream + red-comb accent. Reads as 'this hen has "
                   "OPINIONS and will DEFEND them.' Comedic-menace treatment."),
    },
    "sprocket": {
        "identity_ref": strip_ref("sprocket"),
        "prompt": ("SPROCKET — Brasston clockmaker's assistant, young man "
                   "in his twenties, obsessed with time. Short brown hair "
                   "with pale-blond streaks, one visible round monocle over "
                   "the right eye (small brass frame), amused clever brown "
                   "eyes, wearing a dark-teal steampunk vest over a white "
                   "shirt with a small pocket-watch chain visible at the "
                   "vest lapel, a tiny bronze cog pinned to the collar. "
                   "Reads as apprentice-craftsman who is ALWAYS running "
                   "seven minutes late and blames the clocks. Palette: "
                   "teal + brass + cream."),
    },
    "boss_rat_king": {
        "identity_ref": monster_ref("cave_rat_king"),
        "prompt": ("THE CAVE RAT KING — the pompous-royal-rat boss of the "
                   "Whispering Cave. Portrait-bust of a large gray cave "
                   "rat wearing a full gold king's crown with red gemstones "
                   "(the crown is comically appropriate-sized to his head, "
                   "not too-small — a proper dignified crown), with a "
                   "small purple velvet cape visible at his shoulders and "
                   "a golden filigree chest-plate visible at the collar. "
                   "Rat features: pointed muzzle with small whiskers, "
                   "sharp red eye staring proudly, small tuft of gray "
                   "cheek-fur. Reads as 'small rodent who has decided he "
                   "is nobility and DARES you to argue.' Purple + gold + "
                   "gray + red-eye accent."),
    },
}


def load_ref_bytes(path: Path, is_battle_strip: bool = False) -> bytes:
    img = Image.open(path).convert("RGBA")
    if is_battle_strip:
        H = img.size[1]; img = img.crop((0, 0, H, H))
    target = 1024
    scale = target / max(img.size)
    img = img.resize((int(img.size[0]*scale), int(img.size[1]*scale)), Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target-img.width)//2, (target-img.height)//2), img)
    buf = io.BytesIO(); canvas.save(buf, format="PNG"); return buf.getvalue()


def downscale(img_1024, target=256):
    img = img_1024.convert("RGBA")
    return img.resize((target*4, target*4), Image.LANCZOS).resize((target, target), Image.BOX)


def transparent_bg(img, threshold=240):
    img = img.convert("RGBA"); px = img.load(); W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def call_gpt(client, prompt, refs, quality, max_retries=3):
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(model="gpt-image-1", image=refs, prompt=prompt,
                                       size="1024x1024", quality=quality, n=1)
            return Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg: time.sleep(30 * (attempt+1))
            elif any(k in msg for k in ("billing", "quota", "insufficient")): raise
            else: print(f"  Error: {e}; retry"); time.sleep(5)
    raise RuntimeError("failed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", default=list(PORTRAITS))
    ap.add_argument("--quality", choices=["low","medium","high"], default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.dry_run:
        print(f"DRY RUN — {len(args.ids)} at {args.quality} (~${COST[args.quality]*len(args.ids):.3f})")
        for i in args.ids:
            ref = PORTRAITS[i]['identity_ref']
            print(f"  {i}: {ref.name if ref else '(persona-only)'}")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI(); unit = COST[args.quality]; total = 0.0
    for pid in args.ids:
        if pid not in PORTRAITS:
            print(f"SKIP {pid}: unknown"); continue
        cfg = PORTRAITS[pid]
        refs = [("ref_style.png", load_ref_bytes(STYLE_ANCHOR), "image/png")]
        if cfg["identity_ref"] and cfg["identity_ref"].exists():
            refs.append(("ref_identity.png", load_ref_bytes(cfg["identity_ref"], is_battle_strip=True), "image/png"))
        print(f"[{pid}] gpt-image-1 ({args.quality}, ${unit:.3f})")
        raw = call_gpt(client, STYLE_PREFIX + cfg["prompt"], refs, args.quality)
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
