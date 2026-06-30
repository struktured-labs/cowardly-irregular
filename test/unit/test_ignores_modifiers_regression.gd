extends GutTest

## tick 434: abilities.json `ignores_defense`, `ignores_evasion`,
## `ignores_resistance` fields now actually modify damage application.
##
## Pre-fix all three fields were authored but no code path read them:
##   - phantom_byte (magic, ignores_defense): "ghosts through armor"
##     but still got mitigated by defense
##   - glitch_strike (physical, ignores_evasion): "you can't dodge
##     a glitch" but still missed against invisible/evasion/shadow_step
##   - exploit_weakness + fourth_wall_break (magic, ignores_resistance):
##     "exploits hidden weaknesses" but still got halved by resistance
##     and zeroed by immunity

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_physical_path_reads_ignores_evasion() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_physical_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"ignores_evasion\", false)"),
		"_execute_physical_ability must read ignores_evasion")
	# The dodge check is gated.
	assert_true(body.contains("if not bool(ability.get(\"ignores_evasion\", false)):"),
		"_target_dodges_physical must be gated on ignores_evasion")


func test_magic_path_reads_ignores_defense_and_resistance() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"ignores_defense\", false)"),
		"_execute_magic_ability must read ignores_defense")
	assert_true(body.contains("ability.get(\"ignores_resistance\", false)"),
		"_execute_magic_ability must read ignores_resistance")


func test_ignores_defense_doubles_damage() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the 2x compensation.
	assert_true(src.contains("if ignores_defense:") and src.contains("damage *= 2"),
		"ignores_defense must double the damage as compensation for take_damage's defense formula")


func test_ignores_resistance_clamps_mod_up() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the < 1.0 → 1.0 clamp.
	assert_true(src.contains("if ignores_resistance and elemental_mod < 1.0:") and src.contains("elemental_mod = 1.0"),
		"ignores_resistance must clamp elemental_mod up to 1.0 when it would otherwise reduce damage")


func test_data_still_authors_fields() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("phantom_byte"))
	assert_true(bool(data["phantom_byte"].get("ignores_defense", false)))
	assert_true(data.has("glitch_strike"))
	assert_true(bool(data["glitch_strike"].get("ignores_evasion", false)))
	assert_true(data.has("exploit_weakness"))
	assert_true(bool(data["exploit_weakness"].get("ignores_resistance", false)))
	assert_true(data.has("fourth_wall_break"))
	assert_true(bool(data["fourth_wall_break"].get("ignores_resistance", false)))


func test_ignores_resistance_runtime_blocks_zero_immunity() -> void:
	# Set up: target has fire immunity. Ability has ignores_resistance.
	# Expect: take_damage path is used (not take_elemental_damage), so
	# the immunity isn't applied — actual_damage > 0.
	var c_script: GDScript = load(COMBATANT_PATH)
	var target: Combatant = c_script.new()
	target.initialize({"name": "Immune", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target)
	target.elemental_immunities = ["fire"]
	# Baseline: take_elemental_damage returns 0 for immune.
	assert_eq(target.take_elemental_damage(50, "fire"), 0,
		"baseline: immunity returns 0 damage")
	# Post-fix: take_damage (without elemental routing) ignores
	# immunity entirely. ignores_resistance is what gates which path
	# the magic-ability code takes.
	assert_gt(target.take_damage(50, true), 0,
		"non-elemental take_damage bypasses immunity — this is the path ignores_resistance routes to")
