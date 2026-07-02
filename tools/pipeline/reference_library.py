"""Artist reference library for AI sprite regeneration.

Maps monster categories → best artist source references. Used by
regen_monster_artist_style.py (and future gen scripts) to anchor
gpt-image-1 / IP-Adapter output to the artist's actual style rather
than generic "pixel art JRPG."

Adding a new artist enemy? Extend ARTIST_ENEMY_REFS and, if it introduces
a new archetype, add a category and update MONSTER_CATEGORY_TO_REF.
"""
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
DRIVE = PROJECT / "assets/sprites/drive_archive/Game graphics - Characters"

# Full T2 artist enemy sheets — canonical style anchors for AI regen
ARTIST_ENEMY_REFS = {
    # low-lvl blob/creature — slug/dragon-like, small, soft body
    "slime":  DRIVE / "enemies/SLIME 1.aseprite",
    # flying/winged — bat with wing-flap idle + dive/bite atk
    "bat":    DRIVE / "enemies/BAT 1.aseprite",
    # humanoid melee — goblin with sword, 2-hand grip
    "goblin": DRIVE / "enemies/Goblin 1 anims.aseprite",
}

# Party artist sheets — usable as style/palette anchor for humanoid monsters
ARTIST_PARTY_REFS = {
    "fighter": DRIVE / "FIGHTER/Main Fighter animations.aseprite",
    "mage":    DRIVE / "MAGE/Mage Main design.aseprite",
    "cleric":  DRIVE / "CLERIC/Cleric Main design.aseprite",
    "rogue":   DRIVE / "ROGUE/Rogue Main design.aseprite",
    "bard":    DRIVE / "BARD/Bard Base sprite.aseprite",
}

# Monster archetype → best-matching artist reference. When regenerating
# a T1 monster, pick the reference whose silhouette + palette is closest.
# Multiple candidates in a list are blended (first is primary).
MONSTER_CATEGORY_TO_REF = {
    # Blob / gelatinous / small creature — slime canon
    "blob":       ["slime"],
    "mushroom":   ["slime"],       # elder_mushroom, fungoid (blob-like body)
    "fungoid":    ["slime"],
    # Winged / flying — bat canon
    "winged":     ["bat"],
    "ghost":      ["bat"],         # soft silhouette
    "crow":       ["bat"],
    "bird":       ["bat"],
    # Melee humanoid — goblin canon (weapon-holding, 2-armed grip)
    "humanoid":   ["goblin"],
    "skeleton":   ["goblin"],
    "rat":        ["goblin"],      # bipedal rat guards, cave_rat_king
    "imp":        ["goblin"],
    "orc":        ["goblin"],
    # Beast / four-legged — no artist canon yet; fall back to bat
    # for the darker palette + action pose, style-hint in prompt
    "beast":      ["bat"],         # wolf, dog, snake (no legs though)
    "wolf":       ["bat"],
    "dog":        ["bat"],
    "snake":      ["bat"],
    # Large / boss — combine goblin (weapon-holding) + fighter (armored plate)
    "boss":       ["goblin", "fighter"],
    "knight":     ["fighter", "goblin"],  # shadow_knight, cursed_armor
    "dragon":     ["bat", "goblin"],
}

# Explicit per-monster overrides where the archetype match isn't obvious
MONSTER_ID_TO_REF = {
    # W1 medieval — targeted for item 29 pilot regen
    "cave_rat":            ["goblin"],
    "cave_rat_king":       ["goblin"],
    "rat_guard":           ["goblin"],
    "skeleton":            ["goblin"],
    "wolf":                ["bat"],
    "cave_troll":          ["goblin", "fighter"],
    "shadow_knight":       ["fighter", "goblin"],
    "cursed_armor":        ["fighter"],
    "spider":              ["bat"],
    # W1 boss
    "fire_dragon":         ["bat", "goblin"],
    "ice_dragon":          ["bat", "goblin"],
    "lightning_dragon":    ["bat", "goblin"],
    "shadow_dragon":       ["bat", "goblin"],
    # Spotlight-duel minibosses (msg 1950 spec) — one per PC job. Each
    # designed so THAT job's kit solos it. Ref picked by miniboss silhouette.
    "fighter_skeleton_knight":  ["fighter", "goblin"],  # chivalric plate skeleton
    "cleric_survive_target":    ["goblin"],             # NPC-shape sustained-damage target
    "rogue_lockward":           ["goblin", "fighter"],  # armored treasure-guardian, high evade
    "mage_prismatic_construct": ["fighter"],            # crystal/geometric construct
    "bard_hostile_courtier":    ["goblin"],             # NPC courtier w/ dry rebuff
}


def refs_for(monster_id: str, category: str | None = None) -> list[Path]:
    """Return artist reference paths for a monster.

    Priority: explicit id override → category map → default to goblin
    (broadest-applicable humanoid archetype).
    """
    keys = (
        MONSTER_ID_TO_REF.get(monster_id)
        or (MONSTER_CATEGORY_TO_REF.get(category or "") if category else None)
        or ["goblin"]
    )
    out = []
    for k in keys:
        p = ARTIST_ENEMY_REFS.get(k) or ARTIST_PARTY_REFS.get(k)
        if p and p.exists():
            out.append(p)
    return out
