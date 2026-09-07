extends GutTest

## tick 404: batch-wire 5 meta_effects that previously fell through
## to `_:` push_warning.
##
##   - auto_rewind_on_death (temporal_shield)
##   - auto_solve_puzzle (bypass_puzzle)
##   - boss_control_swap (mind_swap) — applies mind_swap status
##   - create_restore_point (restore_point)
##   - full_boss_control (control_override) — applies controlled status
##   - ng_plus_warp (NG+ Warp)
##
## Each writes its canonical flag + battle_log so the cast stops
## silently fizzling. Actual downstream implementations land in
## future ticks that read these flags.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_all_six_arms_exist() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	for arm in ["auto_rewind_on_death", "auto_solve_puzzle", "boss_control_swap",
				"create_restore_point", "full_boss_control", "ng_plus_warp"]:
		assert_true(src.contains("\"%s\":" % arm),
			"BattleManager.match meta_effect must have a %s arm" % arm)


func test_data_authors_all_six() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var pairs := [
		["temporal_shield", "auto_rewind_on_death"],
		["bypass_puzzle", "auto_solve_puzzle"],
		["mind_swap", "boss_control_swap"],
		["restore_point", "create_restore_point"],
		["control_override", "full_boss_control"],
		["new_game_plus_warp", "ng_plus_warp"],
	]
	for pair in pairs:
		var ability_id: String = pair[0]
		var expected_effect: String = pair[1]
		assert_true(data.has(ability_id),
			"%s ability must exist in data" % ability_id)
		assert_eq(str(data[ability_id].get("meta_effect", "")), expected_effect,
			"%s must still author meta_effect=%s" % [ability_id, expected_effect])


func test_mind_swap_applies_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Bossbinder")
	var target: Combatant = _make("Boss")
	var ability: Dictionary = {
		"id": "test_mind_swap",
		"meta_effect": "boss_control_swap",
		"duration": 5,
		"corruption_risk": 0.0,
	}
	bm._execute_meta_ability(caster, ability, [target])
	assert_true("mind_swap" in target.status_effects,
		"mind_swap status must be on target after boss_control_swap")


func test_control_override_applies_controlled_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Bossbinder")
	var target: Combatant = _make("Boss")
	var ability: Dictionary = {
		"id": "test_control_override",
		"meta_effect": "full_boss_control",
		"duration": 1,
		"corruption_risk": 0.0,
	}
	bm._execute_meta_ability(caster, ability, [target])
	assert_true("controlled" in target.status_effects,
		"controlled status must be on target after full_boss_control")


func test_flag_meta_effects_write_flags() -> void:
	# auto_rewind_on_death, auto_solve_puzzle, create_restore_point,
	# ng_plus_warp all write canonical flags. Pin them in a single test.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null or not GameState:
		pending("BattleManager + GameState required")
		return
	var caster: Combatant = _make("Meta")
	var flag_pairs := [
		["auto_rewind_on_death", "meta_auto_rewind_pending"],
		["auto_solve_puzzle", "meta_auto_solve_puzzle_pending"],
		["create_restore_point", "meta_restore_point_pending"],
		["ng_plus_warp", "meta_ng_plus_warp_pending"],
	]
	for pair in flag_pairs:
		var effect: String = pair[0]
		var flag: String = pair[1]
		GameState.game_constants[flag] = false
		var ability: Dictionary = {"id": "test", "meta_effect": effect}
		bm._execute_meta_ability(caster, ability, [])
		assert_true(bool(GameState.game_constants.get(flag, false)),
			"%s must set %s flag" % [effect, flag])
		GameState.game_constants[flag] = false
