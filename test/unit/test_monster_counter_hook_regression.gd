extends GutTest

## Regression test for monster counter_abilities consumption.
##
## Pre-fix: 13 boss monsters declared counter_abilities in monsters.json but
## NO src/ code ever read the field — counters never fired. This pins:
##   1. monsters.json still ships the counter_abilities for those bosses
##   2. BattleManager.gd has the _trigger_monster_counter hook
##   3. The hook is called from the attack and physical/magic ability paths

const BM_PATH := "res://src/battle/BattleManager.gd"
const MONSTERS_PATH := "res://data/monsters.json"


func _load_json(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t = f.get_as_text()
	f.close()
	var p = JSON.parse_string(t)
	return p if p is Dictionary else {}


func _src(p: String) -> String:
	var f = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func test_counter_hook_function_defined() -> void:
	var src = _src(BM_PATH)
	assert_string_contains(src, "func _trigger_monster_counter",
		"BattleManager must define _trigger_monster_counter — the previously-missing hook for counter_abilities")


func test_counter_hook_reads_counter_abilities_field() -> void:
	var src = _src(BM_PATH)
	assert_string_contains(src, "counter_abilities",
		"BattleManager must reference the counter_abilities key — pre-fix the field was dead JSON")


func test_counter_hook_called_in_attack_paths() -> void:
	var src = _src(BM_PATH)
	var n = src.count("_trigger_monster_counter(")
	# At least one definition + one call in attack + one in physical ability +
	# one in magic ability + barrier/reflect short-circuit branches.
	assert_gte(n, 5,
		"_trigger_monster_counter must fire from multiple combat paths (got %d call/def sites)" % n)


func test_cave_rat_king_keeps_counter_abilities() -> void:
	var data = _load_json(MONSTERS_PATH)
	assert_true(data.has("cave_rat_king"), "cave_rat_king missing from monsters.json")
	var rk = data.get("cave_rat_king", {})
	var counters = rk.get("counter_abilities", [])
	assert_true(counters is Array and counters.size() > 0,
		"cave_rat_king must keep at least one counter_ability — this is the hook's tutorial boss demo")
