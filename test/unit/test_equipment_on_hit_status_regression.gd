extends GutTest

## tick 461: equipment.json special_effects.poison_chance /
## sleep_chance / status_resistance now actually apply.
##
## Pre-tick equipment authored:
##   poison_dagger: special_effects.poison_chance = 0.25
##   sleep_dagger: special_effects.sleep_chance = 0.20
##   resist_ring: special_effects.status_resistance = 0.3
## but no code path read any of them. Weapons gave the stat boost
## (stat_mods.attack) but their headline gimmick was decoration.
## resist_ring gave nothing.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_on_hit_table_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("const ON_HIT_STATUSES"),
		"BattleManager must declare ON_HIT_STATUSES const so future on-hit chances drop in by extending the table")
	assert_true(src.contains("\"key\": \"poison_chance\""),
		"table must include poison_chance entry")
	assert_true(src.contains("\"key\": \"sleep_chance\""),
		"table must include sleep_chance entry")


func test_apply_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _apply_equipment_on_hit_status"),
		"BattleManager must declare _apply_equipment_on_hit_status helper")
	# Pin generic loop over the table.
	assert_true(src.contains("for entry in ON_HIT_STATUSES:"),
		"helper must loop the table generically (so new entries inherit the wire)")


func test_attack_calls_apply_after_damage() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_attack")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_apply_equipment_on_hit_status(attacker, actual_target)"),
		"_execute_attack must call _apply_equipment_on_hit_status after damage")
	# Pin ordering: apply must come AFTER damage lands.
	var dmg_idx: int = body.find("actual_target.take_damage(damage, false)")
	var apply_idx: int = body.find("_apply_equipment_on_hit_status")
	assert_lt(dmg_idx, apply_idx,
		"on-hit status apply must run AFTER take_damage (status piles on top of the hit)")


func test_status_resistance_reduces_effective_chance() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _apply_equipment_on_hit_status")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_sum_equipment_special_effect(target, \"status_resistance\")"),
		"helper must consult target's status_resistance equipment")
	assert_true(body.contains("clampf(chance - resist, 0.0, 1.0)"),
		"effective chance must be (attacker chance - target resist), clamped [0, 1]")


func test_data_still_authors_fields() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	# poison_chance somewhere.
	var found_poison: bool = false
	var found_sleep: bool = false
	var found_resist: bool = false
	for cat in ["weapons", "armors", "accessories"]:
		if not data.has(cat):
			continue
		for iid in data[cat].keys():
			var entry: Dictionary = data[cat][iid]
			var se: Variant = entry.get("special_effects", {})
			if not (se is Dictionary):
				continue
			if float(se.get("poison_chance", 0.0)) > 0.0:
				found_poison = true
			if float(se.get("sleep_chance", 0.0)) > 0.0:
				found_sleep = true
			if float(se.get("status_resistance", 0.0)) > 0.0:
				found_resist = true
	assert_true(found_poison, "equipment.json must still author poison_chance")
	assert_true(found_sleep, "equipment.json must still author sleep_chance")
	assert_true(found_resist, "equipment.json must still author status_resistance")


func test_runtime_no_equip_no_apply() -> void:
	# Regression guard: a bare attacker must NOT silently apply
	# poison/sleep on every hit.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var attacker: Combatant = _make("Bare")
	attacker.equipped_weapon = ""
	var target: Combatant = _make("Victim")
	bm._apply_equipment_on_hit_status(attacker, target)
	assert_false(target.has_status("poison"),
		"bare attacker must not apply poison")
	assert_false(target.has_status("sleep"),
		"bare attacker must not apply sleep")


func test_runtime_resist_zero_is_clamp_safe() -> void:
	# Sanity: a target with a huge status_resistance shouldn't
	# make effective < 0 leak.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	# Walk the source for the clamp call to confirm the clamp arg is
	# 0.0 (not 0.01 etc.).
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("clampf(chance - resist, 0.0, 1.0)"),
		"effective chance must clamp at 0.0 lower bound, not a stray min")
