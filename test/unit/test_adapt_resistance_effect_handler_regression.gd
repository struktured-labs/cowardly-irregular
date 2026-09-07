extends GutTest

## tick 389: adapt_resistance (adapt ability) applies a defense buff.
## Pre-fix the effect fell through to push_warning default.

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
	var arm_idx: int = src.find("\"adapt_resistance\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have an adapt_resistance arm")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("\"Adapted\""),
		"adapt_resistance must apply a buff with the 'Adapted' label")


func test_data_authors_adapt_resistance() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("adapt"))
	assert_eq(str(data["adapt"].get("effect", "")), "adapt_resistance")


func test_dispatch_applies_defense_buff() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("adapt"):
		pending("adapt ability required")
		return
	var c: Combatant = _make("Boss")
	var ability: Dictionary = js.abilities["adapt"].duplicate(true)
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	# At least one buff on defense.
	var found: bool = false
	for b in c.active_buffs:
		if str(b.get("stat", "")) == "defense" and str(b.get("effect", "")) == "Adapted":
			found = true
			break
	assert_true(found,
		"Adapted defense buff must be present after the cast")
