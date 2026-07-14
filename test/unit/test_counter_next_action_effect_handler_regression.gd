extends GutTest

## tick 391: counter_next_action (future_sight ability) aliases to
## the existing reflect status. Pre-fix the effect fell through to
## push_warning — 12 MP burned.

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
	var arm_idx: int = src.find("\"counter_next_action\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a counter_next_action arm")
	var window: String = src.substr(arm_idx, 600)
	assert_true(window.contains("add_status(\"reflect\""),
		"counter_next_action must alias to the existing reflect status")


func test_data_authors_counter_next_action() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("future_sight"))
	assert_eq(str(data["future_sight"].get("effect", "")), "counter_next_action")


func test_dispatch_applies_reflect() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("future_sight"):
		pending("future_sight ability required")
		return
	var c: Combatant = _make("Seer")
	var ability: Dictionary = js.abilities["future_sight"].duplicate(true)
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_true("reflect" in c.status_effects,
		"future_sight must apply the canonical reflect status (downstream consumers gate on 'reflect')")
