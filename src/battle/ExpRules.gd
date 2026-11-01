class_name ExpRules
extends RefCounted

## Over-levelling (struktured 2026-10-31): EXP halves for every HALVING_LEVELS a member stands above the fight's level.
const HALVING_LEVELS := 3.0


## The share of a battle's EXP a member keeps: 1.0 at or below the fight's level, halved per HALVING_LEVELS above it.
static func over_level_factor(member_level: int, area_level: int) -> float:
	if area_level <= 0:
		return 1.0
	return pow(0.5, maxf(0.0, float(member_level - area_level)) / HALVING_LEVELS)


## The one-shot and autobattle bonuses pay only in a fight at or above the member's own level.
static func stomp_bonus_applies(member_level: int, area_level: int) -> bool:
	return area_level <= 0 or member_level <= area_level


## The party's highest job level among the living, for rewards paid to the party as a whole.
static func party_top_level(party: Array) -> int:
	var best := 0
	for c in party:
		if c != null and is_instance_valid(c) and "job_level" in c and bool(c.get("is_alive")):
			best = maxi(best, int(c.job_level))
	return best


## The fight's level: the highest authored level among the enemies, or 0 when none is known.
static func area_level_of(enemies: Array) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var es: Node = tree.root.get_node_or_null("EncounterSystem") if tree != null else null
	var best := 0
	for e in enemies:
		if e == null or not is_instance_valid(e) or not (e is Object) or not e.has_meta("monster_type"):
			continue
		if es != null:
			var row: Variant = es.monster_database.get(str(e.get_meta("monster_type", "")), null)
			if row is Dictionary:
				best = maxi(best, int((row as Dictionary).get("level", 0)))
	return best
