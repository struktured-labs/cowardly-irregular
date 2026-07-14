extends GutTest

## tick 390: random_stat_change (reassign ability) applies a random
## ±25% modifier to one of attack/defense/magic/speed.
##
## Pre-fix the effect fell through to push_warning default — 10 MP
## burned.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"random_stat_change\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a random_stat_change arm")
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("_RANDOM_STAT_POOL"),
		"random_stat_change must define a stat pool to roll from")
	assert_true(window.contains("Reassigned"),
		"applied buff/debuff must use the 'Reassigned' label so the UI source-of-mod is legible")


func test_data_authors_random_stat_change() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("reassign"))
	assert_eq(str(data["reassign"].get("effect", "")), "random_stat_change")


func test_dispatch_applies_some_mod() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("reassign"):
		pending("reassign ability required")
		return
	# Cast multiple times to defeat randomness — at least one must
	# apply SOMETHING (buff or debuff). Pre-fix nothing applied.
	var c: Combatant = _make("Glitch")
	var ability: Dictionary = js.abilities["reassign"].duplicate(true)
	var typed_targets: Array[Combatant] = [c]
	for _i in range(5):
		bm._execute_support_ability(null, ability, typed_targets)
	var total_mods: int = c.active_buffs.size() + c.active_debuffs.size()
	assert_gt(total_mods, 0,
		"after 5 reassign casts, at least one buff or debuff must be applied — pre-fix all 5 silently fizzled")
