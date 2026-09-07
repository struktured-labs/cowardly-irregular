extends GutTest

## tick 405: break_mind_swap (release_binding ability) removes the
## mind_swap status from the caster. Pre-fix the effect fell through
## to `_:` push_warning — the 10 MP cast did nothing.
##
## Pairs with tick 404's boss_control_swap effect which APPLIES the
## mind_swap status (mind_swap ability target=single_enemy).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"break_mind_swap\":")
	assert_gt(arm_idx, -1, "break_mind_swap arm must exist")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("remove_status(\"mind_swap\")"),
		"break_mind_swap arm must remove the mind_swap status")


func test_data_authors_break_mind_swap() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("release_binding"))
	assert_eq(str(data["release_binding"].get("effect", "")), "break_mind_swap")


func test_release_removes_mind_swap() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c: Combatant = _make("MindSwapped")
	c.add_status("mind_swap", 5)
	assert_true("mind_swap" in c.status_effects)
	var ability: Dictionary = {
		"id": "test_release_binding",
		"effect": "break_mind_swap",
	}
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_false("mind_swap" in c.status_effects,
		"mind_swap must be removed after release_binding cast")


func test_no_mind_swap_no_op() -> void:
	# A target without mind_swap is a clean no-op (no crash, no other
	# side effects on their status_effects).
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c: Combatant = _make("Vanilla")
	c.status_effects.clear()
	var ability: Dictionary = {
		"id": "test_release_binding",
		"effect": "break_mind_swap",
	}
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_eq(c.status_effects.size(), 0,
		"break_mind_swap on a target without the status must be a clean no-op")
