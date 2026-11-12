class_name DamageRules
extends RefCounted

## Damage rules BOTH engines read (BattleManager and HeadlessBattleResolver), so a dial moved here moves live play and a
## grind together (cowir-main 24136/24139, cowir-autogrind 24138). The static vars are the dials; the balance probes set
## them per run, and the shipped values are the defaults below.

## Each hero's share when an ENEMY ability lands on more than one of them: a breath is party-wide pressure, not five
## single-target nukes. 1.0 = every hero takes the full hit.
static var enemy_spread: float = 1.0

## How speed becomes crit chance. "shipped" is speed x 0.01 (everyone at the cap since the re-level); "comment" is what
## that line's own comment says, each 10 speed = +1%; "level" compares speed with the attacker's level, capped lower.
static var crit_mode: String = "shipped"
const CRIT_BASE := 0.05
const CRIT_CAP := 0.50
const CRIT_LEVEL_CAP := 0.25
## Speed per level a combatant of average speed has; "level" mode pays for speed above it.
const CRIT_SPEED_PER_LEVEL := 10.0

## True: a physical ability with no `crit_chance` of its own crits as its user's plain swing does (a row opts OUT with
## `"crit_chance": 0`). False is the shipped rule: an ability crits only if its row says so.
static var abilities_inherit_swing_crit: bool = false


## The multiplier on one target's damage when `caster_is_enemy` lands an ability on `target_count` targets.
static func spread_factor(target_count: int, caster_is_enemy: bool) -> float:
	return enemy_spread if caster_is_enemy and target_count > 1 else 1.0


## The share of crit chance that comes from speed, before passives, gear and buffs are added and the cap applied.
static func speed_crit_bonus(speed: float, level: int) -> float:
	match crit_mode:
		"comment":
			return speed * 0.001
		"level":
			var par: float = CRIT_SPEED_PER_LEVEL * float(maxi(1, level))
			return clampf((speed - par) / par * 0.25, 0.0, CRIT_LEVEL_CAP - CRIT_BASE)
		_:
			return speed * 0.01


## The cap total crit chance is held to in the current mode.
static func crit_cap() -> float:
	return CRIT_LEVEL_CAP if crit_mode == "level" else CRIT_CAP


## A physical ability's crit chance, given its user's plain-swing chance.
static func ability_crit_chance(ability: Dictionary, swing_chance: float) -> float:
	if ability.has("crit_chance"):
		return float(ability["crit_chance"])
	return swing_chance if abilities_inherit_swing_crit else 0.0


## Who an ability lands on: a `target_type: all_enemies` ability reaches every living member of the side its pick is on.
## The enemy ladder queued ONE target for such a move, so in live play a breath hit one hero (53 of 53 boss casts measured
## on v3.33.792, 2026-11-12). Idempotent on a list that is already the whole side; a single-target ability is unchanged.
static func landing_targets(ability: Dictionary, picked: Array, side_of_pick: Array) -> Array:
	if str(ability.get("target_type", "")) != "all_enemies" or picked.is_empty():
		return picked
	var out: Array = []
	for member in side_of_pick:
		if member != null and is_instance_valid(member) and bool(member.get("is_alive")):
			out.append(member)
	return out if not out.is_empty() else picked
