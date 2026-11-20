extends GutTest

## The grind reaches the W1 story tiers the field opens (cowir-main 26339), and judges a re-levelled spawn at its mark.

const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")
const ES := preload("res://src/encounters/EncounterSystem.gd")

var _ctrl: Node
var _saved_flags: Dictionary
var _saved_region: String


func before_each() -> void:
	_ctrl = ControllerScript.new()
	add_child_autofree(_ctrl)
	AutogrindSystem._test_disable_persistence = true
	_saved_region = AutogrindSystem.current_region_id
	_saved_flags = GameState.story_flags.duplicate(true)


func after_each() -> void:
	AutogrindSystem.current_region_id = _saved_region
	GameState.story_flags = _saved_flags
	AutogrindSystem._test_disable_persistence = false


func _cfg() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ES.W1_TIERS_PATH))


func _open(dragons: int) -> void:
	var cfg := _cfg()
	GameState.story_flags[str(cfg["opens_with"])] = true
	for i in dragons:
		GameState.story_flags[str(cfg["dragon_flags"][i])] = true


func _top(ids: Array) -> int:
	var top := 0
	for e in ids:
		var lv: int = ES.spawn_level_of(str(e))
		if lv <= 0:
			lv = int((EncounterSystem.monster_database.get(str(e), {}) as Dictionary).get("level", 0))
		top = maxi(top, lv)
	return top


## The field's top across the W1 zone pools at this save: what live random encounters can roll.
func _field_top() -> int:
	var top := 0
	for id in _cfg()["pools"]:
		top = maxi(top, _top(ES.tiered_pool(str(id), EncounterSystem.enemy_pools.get(id, []), GameState)))
	return top


func _grind_top() -> int:
	_ctrl._advanced_from_start = true
	AutogrindSystem.current_region_id = "overworld"
	return _top(_ctrl._region_pool_ids())


func test_the_grind_reaches_what_the_field_reaches_at_every_gate() -> void:
	assert_eq(_grind_top(), _field_top(), "CONTROL: before the Rat King the grind and the field agree")
	for k in 5:
		GameState.story_flags = _saved_flags.duplicate(true)
		_open(k)
		var field := _field_top()
		assert_gt(field, 12, "CONTROL: gate %d really opens a tier above the shipped pools" % k)
		assert_eq(_grind_top(), field, "after %d dragon(s) the grind must reach the field's L%d" % [k, field])


func test_a_relevelled_spawn_is_held_to_the_party_by_its_mark() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Low", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.job_level = 5
	_ctrl._party = [c]
	var low: Dictionary = _ctrl._base_data_for_id("goblin")
	var marked: Dictionary = _ctrl._base_data_for_id("goblin@L15")
	assert_false(low.is_empty(), "CONTROL: goblin has a catalog row")
	assert_eq(int(marked.get("spawn_level", 0)), 15, "CONTROL: the mark carries its level")
	var kept: Array = _ctrl._within_party_reach([low, marked])
	assert_true(kept.has(low), "CONTROL: the catalog goblin is within a L5 party's reach")
	assert_false(kept.has(marked), "a L15 goblin is ten levels past a L5 party; judged by its catalog row it slipped through")
