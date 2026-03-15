JOB_PROMPTS = {
    "fighter": {
        "desc": "medieval warrior in red and steel armor, broadsword, sturdy stance, brown hair",
        "palette_hint": "warm reds, steel grays, brown leather, orange accents",
    },
    "mage": {
        "desc": "mysterious mage in deep blue robes, tall pointed wizard hat, crystal-tipped staff, glowing cyan eyes",
        "palette_hint": "deep blues, cyan glow, silver trim, dark shadows",
    },
    "cleric": {
        "desc": "cute JRPG cleric priestess girl, ornate ceremonial staff with decorative head, hooded layered robes with belt, braided hair, crown tiara headpiece, determined kind expression, classic Final Fantasy white mage style",
        "palette_hint": "white, soft pink, pale gold, cream, light blue, warm pastel tones",
    },
    "rogue": {
        "desc": "mysterious gender-ambiguous rogue, face hidden by deep hood and wrapped scarf, only eyes visible in shadow, lean asymmetrical silhouette, torn cloak over light armor, belts wraps pouches, empty hands at sides, unreadable presence, coiled evasive stance, JRPG battle sprite",
        "palette_hint": "deep muted green, dark brown leather, dusty purple scarf, shadow tones, weathered",
    },
    "bard": {
        "desc": "charming bard in gold-olive doublet with half-cape, feathered beret with red feather, lute on back, rapier at hip",
        "palette_hint": "gold, olive green, red feather, warm browns, cream shirt",
    },
    "guardian": {
        "desc": "heavily armored guardian knight, massive tower shield, full plate armor, stoic protector, visor helmet",
        "palette_hint": "steel blue, silver, dark iron, gold trim, cape blue",
    },
    "ninja": {
        "desc": "swift ninja in dark wrappings, face mask, kunai daggers, crouched ready pose, minimal armor",
        "palette_hint": "blacks, dark purple, steel gray, red sash accent",
    },
    "summoner": {
        "desc": "ethereal summoner in flowing robes with arcane symbols, horned circlet, floating grimoire, mystical aura",
        "palette_hint": "deep purple, gold arcane symbols, teal energy, dark cloth",
    },
    "speculator": {
        "desc": "90s wall street speculator in pinstripe suit, round spectacles, pocket watch chain, confident smirk, briefcase",
        "palette_hint": "navy pinstripe, white shirt, gold accents, black shoes",
    },
}

ANIMATION_POSES = {
    "idle": "standing neutral ready pose, slight breathing motion",
    "walk": "walking forward mid-stride",
    "attack": "swinging weapon in aggressive strike",
    "hit": "recoiling from being hit, pained expression",
    "dead": "collapsed on ground, defeated",
    "cast": "channeling magic with raised hand, energy gathering",
    "defend": "blocking with shield or defensive stance",
    "item": "holding up a potion or item",
    "victory": "triumphant celebration pose, weapon raised",
}

JOB_POSE_OVERRIDES = {
    "rogue": {
        "idle": "weight shifted, ready to pivot, hands relaxed but ready, restrained ambiguous stance",
        "walk": "light quick stride, almost gliding, scarf trailing",
        "attack": "quick lunging feint from unexpected angle, open hand strike",
        "hit": "twisting away, already half-dodging, barely grazed",
        "dead": "crumpled in heap, face still obscured even in death",
        "cast": "flicking a trick item or smoke bomb, misdirection gesture",
        "defend": "vanishing sidestep, afterimage blur, not blocking but absent",
        "item": "pulling something from hidden pouch, sleight of hand",
        "victory": "back turned, glancing over shoulder, already leaving",
    },
}

NEGATIVE_PROMPT = (
    "multiple characters, multiple views, sprite sheet, reference sheet, "
    "turnaround, model sheet, concept art, collage, grid, tiled, pattern, "
    "background scenery, landscape, room, floor, wall, "
    "blurry, photorealistic, 3D, text, watermark, deformed, "
    "oversexualized, revealing armor, bikini armor, cleavage, "
    "multiple characters, multiple views, sprite sheet, reference sheet"
)

JOB_NEGATIVE_OVERRIDES = {
    "cleric": "sword, blade, knife, dagger, weapon, bow, axe, spear",
    "rogue": (
        "clearly female body shape, clearly male bodybuilder shape, "
        "visible cleavage, exaggerated hips, exaggerated jawline, hypermasculine brute, "
        "anime catgirl thief, flamboyant bishonen, edgy full-black assassin, all black outfit, "
        "sword, dagger, knife, blade, weapon, bow, staff, wand, axe, spear, "
        "knight armor, priest robes, wizard robes, "
        "noble symmetry, bright cheerful face, honest open posture, "
        "hypersexualized outfit, cyberpunk techwear, dark silhouette, pure black clothing"
    ),
}


def build_prompt(job: str, animation: str, frame_idx: int = 0) -> str:
    job_info = JOB_PROMPTS.get(job, {"desc": job, "palette_hint": "muted fantasy colors"})
    job_poses = JOB_POSE_OVERRIDES.get(job, {})
    pose = job_poses.get(animation, ANIMATION_POSES.get(animation, "neutral pose"))

    prompt = (
        f"pixel art RPG battle sprite of a {job_info['desc']}, "
        f"{pose}, "
        f"fighter_ci_pixel, 16-bit SNES style, {job_info['palette_hint']}, "
        f"black outline, white background, isolated character"
    )
    return prompt


def get_negative_prompt(job: str) -> str:
    base = NEGATIVE_PROMPT
    extra = JOB_NEGATIVE_OVERRIDES.get(job, "")
    if extra:
        return f"{base}, {extra}"
    return base
