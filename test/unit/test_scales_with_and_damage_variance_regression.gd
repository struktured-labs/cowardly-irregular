extends GutTest

## tick 437: abilities.json scales_with (3 wired) + damage_variance
## (1 wired) now actually affect damage computation.
##
## Pre-fix none of the fields were read:
##   - guard_strike (scales_with=defense): used attack as base
##   - throw_shuriken (scales_with=speed): used attack as base
##   - last_stand_ability (scales_with=missing_hp, max_multiplier=5.0):
##     flat 1.0x regardless of HP — "more damage the lower your HP"
##     never fired
##   - type_error (damage_variance=2.0): rolled at the default narrow
##     variance instead of [0, 2x] — "causes random damage" was just
##     normal damage

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_physical_path_reads_scales_with() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_physical_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"scales_with\", \"\")"),
		"_execute_physical_ability must read scales_with")
	# Pin all three stat arms.
	for stat in ["defense", "speed"]:
		assert_true(body.contains("\"%s\":" % stat),
			"scales_with match must handle '%s'" % stat)
	# missing_hp uses a multiplier scaling, not base_damage swap.
	assert_true(body.contains("scales_with == \"missing_hp\""),
		"scales_with must handle 'missing_hp' as a multiplier scaling")


func test_missing_hp_uses_max_multiplier() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the max_multiplier read for missing_hp.
	assert_true(src.contains("ability.get(\"max_multiplier\", 5.0)"),
		"missing_hp scaling must read max_multiplier")


func test_magic_path_reads_damage_variance() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"damage_variance\", 0.0)"),
		"_execute_magic_ability must read damage_variance")
	# Roll range is [0, variance].
	assert_true(body.contains("randf_range(0.0, dmg_variance)"),
		"damage_variance must extend the roll to [0, variance]")


func test_data_still_authors_fields() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_eq(str(data["guard_strike"].get("scales_with", "")), "defense")
	assert_eq(str(data["throw_shuriken"].get("scales_with", "")), "speed")
	assert_eq(str(data["last_stand_ability"].get("scales_with", "")), "missing_hp")
	assert_gt(float(data["last_stand_ability"].get("max_multiplier", 0.0)), 1.0)
	assert_gt(float(data["type_error"].get("damage_variance", 0.0)), 0.0)


func test_runtime_guard_strike_uses_defense_not_attack() -> void:
	# Behavioral: a high-defense + low-attack combatant should deal
	# MORE damage with guard_strike than a basic attack ability would.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load(COMBATANT_PATH)
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Tank", "max_hp": 100, "max_mp": 50,
		"attack": 5, "defense": 50, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var target: Combatant = c_script.new()
	target.initialize({"name": "Target", "max_hp": 500, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target)
	var hp_before: int = target.current_hp
	var ability: Dictionary = {
		"id": "guard_strike",
		"damage_multiplier": 1.3,
		"scales_with": "defense",
	}
	var typed_targets: Array[Combatant] = [target]
	bm._execute_physical_ability(caster, ability, typed_targets)
	var dealt: int = hp_before - target.current_hp
	# With defense=50 as base (vs attack=5), the damage should be
	# noticeably higher than a 5-attack baseline.
	assert_gt(dealt, 5,
		"guard_strike must deal > 5 damage when scaling with defense=50, not attack=5")


func test_runtime_last_stand_scales_with_missing_hp() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load(COMBATANT_PATH)
	var caster_full: Combatant = c_script.new()
	caster_full.initialize({"name": "Full", "max_hp": 100, "max_mp": 50,
		"attack": 20, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster_full)
	var caster_low: Combatant = c_script.new()
	caster_low.initialize({"name": "Low", "max_hp": 100, "max_mp": 50,
		"attack": 20, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster_low)
	caster_low.current_hp = 1  # 99% missing hp
	var target1: Combatant = c_script.new()
	target1.initialize({"name": "T1", "max_hp": 1000, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target1)
	var target2: Combatant = c_script.new()
	target2.initialize({"name": "T2", "max_hp": 1000, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target2)
	var ability: Dictionary = {
		"id": "last_stand_ability",
		"damage_multiplier": 1.0,
		"scales_with": "missing_hp",
		"max_multiplier": 5.0,
	}
	var typed_t1: Array[Combatant] = [target1]
	bm._execute_physical_ability(caster_full, ability, typed_t1)
	var dealt_full: int = 1000 - target1.current_hp
	var typed_t2: Array[Combatant] = [target2]
	bm._execute_physical_ability(caster_low, ability, typed_t2)
	var dealt_low: int = 1000 - target2.current_hp
	assert_gt(dealt_low, dealt_full,
		"last_stand_ability must deal MORE damage at 1 HP than at full HP — pre-fix the missing_hp scaling never fired")
