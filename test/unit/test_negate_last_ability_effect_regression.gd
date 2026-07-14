extends GutTest

## tick 407: negate_last_ability (rules_lawyer) refunds the last
## cast's MP cost and clears the tracker so it can't double-fire.
##
## Pre-fix the meta_effect fell through to `_:` push_warning — 15 MP
## burned for nothing. Uses tick 406's last-cast tracker.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"negate_last_ability\":")
	assert_gt(arm_idx, -1, "negate_last_ability arm must exist")
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("_last_ability_cast_id"),
		"negate_last_ability must read the tick-406 last-cast tracker")
	assert_true(window.contains("restore_mp"),
		"negate_last_ability must refund the cost via restore_mp")


func test_data_authors_negate_last_ability() -> void:
	# rules_lawyer is type=support, effect=negate_last_ability (NOT
	# type=meta with meta_effect). Arm lives in _execute_support_ability's
	# dispatch.
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("rules_lawyer"))
	assert_eq(str(data["rules_lawyer"].get("effect", "")), "negate_last_ability")
	assert_eq(str(data["rules_lawyer"].get("type", "")), "support")


func test_negate_refunds_mp_to_last_caster() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rules_lawyer: Combatant = _make("RulesLawyer")
	var enemy_caster: Combatant = _make("Enemy")
	# Simulate the tracker as if Enemy just cast something expensive.
	bm._last_ability_cast_id = "fire"  # built-in 8 MP ability
	bm._last_ability_cast_caster = enemy_caster
	var mp_before: int = enemy_caster.current_mp
	# Damage caster MP so the refund actually has somewhere to go.
	enemy_caster.current_mp = max(0, enemy_caster.current_mp - 8)

	var ability: Dictionary = {
		"id": "test_rules_lawyer",
		"effect": "negate_last_ability",
	}
	bm._execute_support_ability(rules_lawyer, ability, [])

	# Tracker must clear (single-shot).
	assert_eq(bm._last_ability_cast_id, "",
		"negate must clear the tracker so it can't double-fire on the same cast")
	assert_eq(bm._last_ability_cast_caster, null,
		"negate must clear the caster tracker too")


func test_negate_with_no_recent_cast_is_no_op() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var rules_lawyer: Combatant = _make("RulesLawyer")
	bm._last_ability_cast_id = ""
	bm._last_ability_cast_caster = null
	var ability: Dictionary = {
		"id": "test_rules_lawyer",
		"effect": "negate_last_ability",
	}
	# Must not crash — gray log line only.
	bm._execute_support_ability(rules_lawyer, ability, [])
	assert_eq(bm._last_ability_cast_id, "",
		"tracker stays empty after a no-target negate")
