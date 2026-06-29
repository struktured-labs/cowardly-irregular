extends GutTest

## tick 432: abilities.json damage_to_self_pct (stack_overflow) now
## applies real recoil damage to the caster on cast — the magic
## ability dealt 3.0x to all enemies for free pre-fix.
##
## recoil_pct (leverage_position) is already wired via the existing
## volatility_up_self arm — not part of this tick's scope. The
## audit count was misleading.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 200, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_magic_path_reads_damage_to_self_pct() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"damage_to_self_pct\", 0.0)"),
		"_execute_magic_ability must read damage_to_self_pct")
	# Recoil scales with total dealt across all targets.
	assert_true(body.contains("total_dealt_for_recoil += actual_damage"),
		"magic-ability path must accumulate total damage dealt for recoil scaling")


func test_data_still_authors_damage_to_self_pct() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("stack_overflow"))
	assert_gt(float(data["stack_overflow"].get("damage_to_self_pct", 0.0)), 0.0,
		"stack_overflow must still author damage_to_self_pct")


func test_runtime_recoil_block_pin() -> void:
	# Pin that the magic-ability recoil block sits AFTER the for-target
	# loop and uses total_dealt_for_recoil (not a single hit). The
	# stack_overflow ability targets all_enemies so the recoil
	# integrates damage across the entire spell.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("total_dealt_for_recoil * dmg_to_self_pct"),
		"recoil must scale with total_dealt_for_recoil (not single hit)")
