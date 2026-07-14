extends GutTest

## tick 387: brave_actions (brave ability) grants the caster +2 AP.
##
## Pre-fix the effect fell through to `_:` push_warning default. The
## Bravely-Default-derived BP system doesn't exist in this engine;
## the closest mechanical fit is "extra actions this turn" = grant
## AP. gain_ap(2) is the documented interpretation. Override via
## ap_grant field on the ability.

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
	var arm_idx: int = src.find("\"brave_actions\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a brave_actions arm")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("gain_ap"),
		"brave_actions must call gain_ap on the target")


func test_brave_grants_ap() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("brave"):
		pending("brave ability required")
		return
	var c: Combatant = _make("Brave")
	c.current_ap = 0
	var ability: Dictionary = js.abilities["brave"].duplicate(true)
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_gt(c.current_ap, 0,
		"brave must grant the caster AP — pre-fix the effect silently fizzled")


func test_brave_at_max_ap_is_no_op() -> void:
	# gain_ap clamps at +4; if caster is already at max, brave is a
	# no-op (no error, just no benefit). Pin so this doesn't crash.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c: Combatant = _make("Maxed")
	c.current_ap = 4
	var ability: Dictionary = {
		"name": "Custom",
		"effect": "brave_actions",
	}
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_eq(c.current_ap, 4,
		"brave at max AP must not raise above the cap (still 4)")


func test_data_authors_brave_actions() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("brave"))
	assert_eq(str(data["brave"].get("effect", "")), "brave_actions")
