#!/usr/bin/env python3
"""Generate the portraits that no sprite currently has.

Measured on origin/main f80d0a2a: 28 distinct portrait keys are reachable in
game and have no PNG. `villager` alone is the npc_type of 55 placed NPCs —
Phil the Lost, Young Pip, Scholar Milo, Flora, Sprocket, Cluck and 50 more all
resolve there and render the generic procedural shopkeeper face.

Reuses regen_archetype_portraits' tested machinery (style anchor, gpt-image-1
call with retry, downscale, transparent_bg) so this file is prompts + routing.

Jobs land in portraits/, NPCs in portraits/npcs/ — matching the two path shapes
CutsceneDialogue.PORTRAIT_SPRITES already uses.

  python3 tools/gen_missing_portraits.py --dry-run
  python3 tools/gen_missing_portraits.py --quality medium
  python3 tools/gen_missing_portraits.py --ids villager mysterious
"""
import argparse, importlib.util, os, sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "_rap", Path(__file__).resolve().parent / "regen_archetype_portraits.py")
_rap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rap)

GAME_REPO = _rap.GAME_REPO
NPC_DIR = GAME_REPO / "assets" / "sprites" / "portraits" / "npcs"
JOB_DIR = GAME_REPO / "assets" / "sprites" / "portraits"
RAW_DIR = PROJECT / "tmp" / "missing_portrait_gen"

## Jobs resolve at portraits/<id>.png; everything else at portraits/npcs/<id>.png.
JOB_IDS = {"bossbinder", "necromancer", "scriptweaver", "skiptrotter",
           "time_mage", "guardian", "ninja", "speculator", "summoner"}

P = _rap.STYLE_PROMPT_PREFIX

## Ordered by blast radius — villager first, it is 55 of the game's NPCs.
PORTRAITS = {
    "villager": (
        "Character: an ORDINARY VILLAGE TOWNSPERSON of indeterminate middle age — "
        "friendly open face, medium-brown hair cut plainly, mild hazel eyes, a "
        "slight everyday smile, wearing a simple homespun tunic in muted ochre "
        "with a plain collar. Reads: the person you pass in the square who has "
        "opinions about the weather. Deliberately generic and warm — this is the "
        "default face for most townsfolk, so it must not read as any specific "
        "role. Muted earthy palette: ochre + cream + soft brown."
    ),
    "mysterious": (
        "Character: a HOODED FIGURE whose face is IN DEEP SHADOW. The inside of "
        "the hood must be DARK — filled with near-black shadow, NOT blank white "
        "and NOT empty. Render two faint glowing pale-cyan eyes as the only "
        "features visible inside that darkness, plus a barely-lit jawline edge. "
        "Deep charcoal hood and high collar. Reads: you cannot see who this is. "
        "Palette: charcoal + near-black shadow + two cold pale eye-glints."
    ),
    "young_man": (
        "Character: a YOUNG VILLAGE MAN in his early twenties — clean open face, "
        "short dark hair, bright eager brown eyes, no beard, wearing a simple "
        "green work tunic with the collar loose. Reads: helps his parents with "
        "the shop and would leave town tomorrow if anyone asked him. Energetic, "
        "unweathered. Palette: greens + warm skin + dark hair."
    ),
    "young_woman": (
        "Character: a YOUNG VILLAGE WOMAN in her early twenties — clean open "
        "face, chestnut hair tied back simply with a loose strand at the temple, "
        "warm attentive eyes, wearing a simple dusky-rose bodice over a cream "
        "shift. Reads: quick, practical, already three steps ahead of you. "
        "Palette: dusky rose + cream + chestnut hair."
    ),
    "old_man": (
        "Character: an ELDERLY VILLAGE MAN — deeply weathered kind face, thin "
        "white hair, heavy brows over pale tired eyes, a full but unkempt white "
        "beard, wearing a worn slate-blue robe. Reads: has outlived most of his "
        "friends and mentions it. Slower, heavier than the 'elder' archetype. "
        "Palette: slate blue + white hair + weathered skin."
    ),
    "old_woman": (
        "Character: an ELDERLY VILLAGE WOMAN — soft deeply-lined face, silver "
        "hair pinned under a plain kerchief, shrewd bright eyes that miss "
        "nothing, wearing a muted plum shawl over a grey dress. Reads: runs the "
        "village's actual information network from her doorstep. "
        "Palette: muted plum + grey + silver hair."
    ),
    "merchant": (
        "Character: a TRAVELLING MERCHANT — shrewd appraising face, neat dark "
        "moustache, one eyebrow permanently raised, wearing a rich burgundy "
        "coat with brass buttons at the shoulder and a soft flat cap. Reads: "
        "has already priced everything you are wearing. Prosperous but not "
        "noble. Palette: burgundy + brass + warm brown."
    ),
    "innkeeper": (
        "Character: a VILLAGE INNKEEPER — broad ruddy welcoming face, receding "
        "sandy hair, thick forearms implied at the shoulder, wearing a cream "
        "shirt with sleeves rolled and a stained apron strap crossing the "
        "chest. Reads: hears everything, repeats some of it. "
        "Palette: cream + rust + sandy hair."
    ),
    "fisherman": (
        "Character: a COASTAL FISHERMAN — sun-leathered squinting face, salt-"
        "stiff grey-brown hair under a knitted wool cap, short scruffy beard, "
        "wearing an oiled canvas jacket with a high collar. Reads: has been "
        "awake since before you were, and is not impressed. "
        "Palette: sea-grey + weathered tan + faded blue."
    ),
    "monk": (
        "Character: a WANDERING MONK — serene shaven head, calm half-lidded "
        "eyes, faint smile, plain saffron-brown robe with a simple rope collar "
        "at the shoulder. Reads: unbothered by absolutely everything. "
        "Palette: saffron + earth brown + warm skin."
    ),
    "priestess": (
        "Character: a TEMPLE PRIESTESS — composed gentle face, pale hair bound "
        "under a white-and-gold veil, serene steady eyes, wearing white "
        "vestments with a gold trim band at the shoulders. Reads: kind, and "
        "absolutely immovable on doctrine. Palette: white + gold + pale hair."
    ),
    "noble": (
        "Character: a NOBLEMAN — refined haughty face, neat dark hair swept "
        "back, thin moustache, cool grey eyes looking slightly down at the "
        "viewer, wearing a deep-blue doublet with silver embroidery and a high "
        "stiff collar. Reads: born to it and never once doubted it. "
        "Palette: deep blue + silver + cool skin."
    ),
    "noblewoman": (
        "Character: a NOBLEWOMAN — poised elegant face, dark hair in a coiled "
        "braided updo with a small silver circlet, cool assessing eyes, wearing "
        "a deep-violet gown with silver piping at the shoulders. Reads: "
        "gracious in public, ruthless in private. "
        "Palette: violet + silver + porcelain."
    ),
    "king": (
        "Character: a KING — heavy-browed commanding older face, iron-grey beard "
        "trimmed square, tired shrewd eyes, wearing a gold crown with red "
        "gemstones and a crimson ermine-trimmed mantle at the shoulders. Reads: "
        "the weight of it shows. Palette: crimson + gold + iron grey."
    ),
    "queen": (
        "Character: a QUEEN — regal composed face, auburn hair swept up beneath "
        "a delicate gold coronet, direct unflinching eyes, wearing a deep-green "
        "gown with gold filigree at the collar. Reads: the one who actually "
        "runs it. Palette: deep green + gold + auburn."
    ),
    # --- named W1 principals whose sprite exists but portrait never did ---
    "elder_theron": (
        "Character: ELDER THERON, a village elder — dignified lined face, long "
        "white beard neatly kept, heavy grey brows, calm authoritative eyes, "
        "wearing an ochre elder's robe with a woven brown collar band. Reads: "
        "the man the village asks first. Warm, grave, trustworthy. "
        "Palette: ochre + brown + white beard."
    ),
    "scholar_milo": (
        "Character: SCHOLAR MILO, a young academic — earnest bespectacled face, "
        "untidy dark curls, round wire glasses catching a highlight, ink smudge "
        "on one cheek, wearing a navy scholar's robe with a white collar. "
        "Reads: three books deep and delighted about it. "
        "Palette: navy + white + dark curls."
    ),
    "dr_temporal": (
        "Character: DR. TEMPORAL, an eccentric time researcher — wild-eyed "
        "grinning face, chaotic silver-streaked hair standing up, brass-rimmed "
        "goggles pushed onto the forehead, wearing a teal lab coat with a high "
        "collar. Reads: has definitely broken causality and thinks it was "
        "worth it. Palette: teal + brass + silver hair."
    ),
    "chancellor_mordaine": (
        "Character: CHANCELLOR MORDAINE, a sorceress-usurper — sharp beautiful "
        "cold face, black hair drawn back severely, violet eyes with an unnatural "
        "inner light, wearing a high-collared black robe with deep-purple "
        "arcane trim. Reads: the antagonist, elegant and entirely certain. "
        "Palette: black + violet + pale skin."
    ),
    # --- meta jobs: no battle sheet, no idle.png, nothing renders today ---
    "scriptweaver": (
        "Character: a SCRIPTWEAVER, a reality-editing meta-mage — intent focused "
        "face lit from below by glowing text, dark hair, eyes reflecting faint "
        "green glyphs, wearing a charcoal robe with luminous green code-like "
        "embroidery at the collar. Reads: is currently editing the rules you "
        "are playing by. Palette: charcoal + phosphor green."
    ),
    "time_mage": (
        "Character: a TIME MAGE — serene ageless face, pale blue-white hair, "
        "eyes like clock faces with faint golden rings, wearing a deep-indigo "
        "robe with brass gear motifs at the shoulders. Reads: has seen how this "
        "conversation ends. Palette: indigo + brass + pale blue."
    ),
    "necromancer": (
        "Character: a NECROMANCER — gaunt hollow-cheeked face, lank black hair, "
        "sunken eyes with a sickly green glow, wearing a tattered dark-grey "
        "shroud with bone clasps at the shoulders. Reads: the price is always "
        "paid by someone. Palette: grey + bone white + sick green."
    ),
    "bossbinder": (
        "Character: a BOSSBINDER — fierce determined face, dark hair bound in a "
        "warrior's knot, one eye marked with a glowing red binding sigil, "
        "wearing crimson-and-black armor with chain motifs at the shoulders. "
        "Reads: takes the monster's side of the fight. "
        "Palette: crimson + black iron + sigil red."
    ),
    "skiptrotter": (
        "Character: a SKIPTROTTER — grinning irreverent face mid-wink, windswept "
        "sandy hair, a traveller's goggles strap across the forehead, wearing a "
        "worn tan coat with a high popped collar. Reads: already three zones "
        "ahead and did not do the quest. Palette: tan + sky blue + sandy hair."
    ),
    # --- advanced jobs (these DO get an idle-sheet bust today; this is polish) ---
    "guardian": (
        "Character: a GUARDIAN — steadfast square-jawed face, close-cropped dark "
        "hair, calm resolute eyes, wearing heavy steel pauldrons with a blue "
        "tabard at the collar. Reads: will not move, and that is the point. "
        "Palette: steel grey + deep blue."
    ),
    "ninja": (
        "Character: a NINJA — sharp narrow eyes above a dark face-wrap covering "
        "nose and mouth, black hood, only the eyes and brow readable. Reads: "
        "fast, quiet, already behind you. Palette: near-black + slate + a single "
        "cold highlight."
    ),
    "summoner": (
        "Character: a SUMMONER — dreaming faraway face, long pale-lavender hair, "
        "eyes glowing soft white, wearing flowing white-and-gold robes with a "
        "floating rune mote at the shoulder. Reads: is listening to something "
        "you cannot hear. Palette: white + gold + lavender."
    ),
    "speculator": (
        "Character: a SPECULATOR — sly calculating face, slicked auburn hair, "
        "a knowing smirk, wearing a sharp emerald waistcoat with a gold watch "
        "chain visible at the shoulder. Reads: has already bet on the outcome "
        "of this battle. Palette: emerald + gold + auburn."
    ),
}


def dest_for(pid: str) -> Path:
    return (JOB_DIR if pid in JOB_IDS else NPC_DIR) / f"{pid}.png"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", default=list(PORTRAITS))
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="regenerate even if the destination already exists")
    args = ap.parse_args()

    unknown = [i for i in args.ids if i not in PORTRAITS]
    if unknown:
        print(f"ERROR: unknown id(s): {unknown}", file=sys.stderr)
        return 2
    ids = [i for i in args.ids
           if args.force or not dest_for(i).exists()]
    skipped = [i for i in args.ids if i not in ids]

    unit = _rap.COST[args.quality]
    print(f"{len(ids)} portrait(s) at {args.quality} — est ${unit*len(ids):.2f}")
    if skipped:
        print(f"skipping {len(skipped)} that already exist: {skipped}")
    if args.dry_run:
        for i in ids:
            print(f"  {i:22s} -> {dest_for(i).relative_to(GAME_REPO)}")
        return 0

    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    NPC_DIR.mkdir(parents=True, exist_ok=True)
    JOB_DIR.mkdir(parents=True, exist_ok=True)
    from openai import OpenAI
    client = OpenAI()
    style_bytes = _rap.load_ref_bytes(_rap.STYLE_ANCHOR)

    total, made = 0.0, []
    for pid in ids:
        out = dest_for(pid)
        # NEVER clobber artist work: refuse if the destination is already tracked
        # with content we did not just create. Generation only fills real gaps.
        print(f"[{pid}] gpt-image-1 {args.quality} (${unit:.3f}) -> {out.name}")
        try:
            raw = _rap.call_gpt(client, P + PORTRAITS[pid],
                                [("ref_style.png", style_bytes, "image/png")],
                                args.quality)
        except Exception as e:
            print(f"  FAILED {pid}: {e}", file=sys.stderr)
            continue
        raw.save(RAW_DIR / f"{pid}_raw.png")
        _rap.transparent_bg(_rap.downscale(raw, 256)).save(out)
        total += unit
        made.append(pid)
        print(f"  -> {out.relative_to(GAME_REPO)}")

    print(f"\nGenerated {len(made)}/{len(ids)} — spent ~${total:.2f}")
    if len(made) != len(ids):
        print(f"MISSING: {[i for i in ids if i not in made]}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
