extends GutTest

## The W1 L12-25 gap (cowir-main 26347): after the Rat King each W1 pool gains its own species re-levelled by dragons defeated.

const ES := preload("res://src/encounters/EncounterSystem.gd")


class Flags extends RefCounted:
	var on: Array = []

	func is_story_flag_set(f: String) -> bool:
		return on.has(f)


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cfg() -> Dictionary:
	return _json(ES.W1_TIERS_PATH)


func _level(id: String) -> int:
	var row: Variant = (_json("res://data/monsters.json") as Dictionary).get(id, {})
	return int(row.get("level", 0)) if row is Dictionary else 0


func _top(pool: Array) -> int:
	var top: int = 0
	for e in pool:
		var lv: int = ES.spawn_level_of(str(e))
		top = maxi(top, lv if lv > 0 else _level(str(e)))
	return top


func _gs(dragons: int, opened: bool = true) -> Flags:
	var g := Flags.new()
	if opened:
		g.on.append(str(_cfg()["opens_with"]))
	for i in dragons:
		g.on.append(str(_cfg()["dragon_flags"][i]))
	return g


## The next fight's level after `beaten` dragons, by count: the dragons' levels in order, then Mordaine.
func _next_boss(beaten: int) -> int:
	var lv: Array = []
	for f in _cfg()["dragon_flags"]:
		lv.append(_level(str(f).trim_suffix("_defeated")))
	lv.sort()
	return lv[beaten] if beaten < lv.size() else _level("chancellor_mordaine")


func test_every_bound_comes_from_the_catalog() -> void:
	for f in _cfg()["dragon_flags"]:
		assert_gt(_level(str(f).trim_suffix("_defeated")), 0, "CONTROL: %s names a dragon in monsters.json" % f)
	assert_gt(_level("chancellor_mordaine"), 0, "CONTROL: Mordaine's level is in monsters.json")
	assert_eq((_cfg()["dragon_flags"] as Array).size(), 4, "CONTROL: four elemental dragons gate the tiers")


func test_nothing_changes_before_the_rat_king() -> void:
	var pools: Dictionary = _json("res://data/enemy_pools.json")
	for id in _cfg()["pools"]:
		assert_true(pools.has(id), "CONTROL: %s is a real pool" % id)
		var base: Array = pools.get(id, [])
		assert_eq(ES.tiered_pool(id, base, _gs(4, false)), base, "%s: changed before the Rat King fell" % id)
		assert_eq(ES.tiered_pool(id, base, null), base, "%s: changed with no save to read" % id)


func test_each_gate_reaches_the_next_boss_but_not_past_it() -> void:
	var pools: Dictionary = _json("res://data/enemy_pools.json")
	for k in 5:
		var next: int = _next_boss(k)
		for id in _cfg()["pools"]:
			var base: Array = pools.get(id, [])
			var top: int = _top(ES.tiered_pool(id, base, _gs(k)))
			assert_true(top >= next - 2 and top <= next, "%s after %d dragon(s): pool tops at L%d, the next boss is L%d (want L%d-%d)" % [id, k, top, next, next - 2, next])
		assert_lt(_top(pools.get("overworld_plains", [])), next - 2, "CONTROL: the shipped plains pool alone falls short of gate %d" % k)


func test_the_tier_counts_dragons_not_which_one() -> void:
	var base: Array = (_json("res://data/enemy_pools.json") as Dictionary).get("overworld_ice", [])
	var first := Flags.new()
	first.on = [str(_cfg()["opens_with"]), str(_cfg()["dragon_flags"][0])]
	var last := Flags.new()
	last.on = [str(_cfg()["opens_with"]), str(_cfg()["dragon_flags"][3])]
	assert_eq(ES.tiered_pool("overworld_ice", base, last), ES.tiered_pool("overworld_ice", base, first), "one dragon is one dragon, whichever fell")


func test_a_tier_re_levels_the_pools_own_species() -> void:
	var pools: Dictionary = _json("res://data/enemy_pools.json")
	var db: Dictionary = _json("res://data/monsters.json")
	for id in _cfg()["pools"]:
		var base: Array = pools.get(id, [])
		var tiered: Array = ES.tiered_pool(id, base, _gs(2))
		assert_gt(tiered.size(), base.size(), "CONTROL: %s gained a tier" % id)
		for e in tiered.slice(base.size()):
			assert_true(base.has(ES.spawn_base_id(str(e))), "%s: %s is not one of the pool's own species" % [id, e])
			assert_true(db.has(ES.spawn_base_id(str(e))), "%s: %s has no catalog row" % [id, e])
	var cave: Array = pools.get("deep_cave", [])
	assert_eq(ES.tiered_pool("deep_cave", cave, _gs(2)), cave, "a pool outside the W1 map keeps its own levels")
