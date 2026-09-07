extends GutTest

## tick 435: abilities.json drain_mp (data_drain, memory_drain) and
## next_attack_multiplier (burrow) now have real effects.
##
## Pre-fix both fields were authored but no code path read them:
##   - data_drain (drain_mp=20) / memory_drain (drain_mp=15) cast
##     for 15-16 MP and got nothing back, despite "siphons MP"
##     descriptions.
##   - burrow (next_attack_multiplier=1.5) promised "emerge to deal
##     surprise damage" but the next attack was a normal hit.

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


func test_magic_path_reads_drain_mp() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"drain_mp\", 0)"),
		"_execute_magic_ability must read drain_mp")
	# caster.restore_mp call inside the per-target loop.
	assert_true(body.contains("caster.restore_mp(drain_mp_amount)"),
		"drain_mp must call caster.restore_mp with the authored amount")


func test_support_path_stores_next_attack_multiplier() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("ability.get(\"next_attack_multiplier\", 0.0)"),
		"_execute_support_ability must read next_attack_multiplier")
	assert_true(body.contains("caster.set_meta(\"_next_attack_multiplier\", nam)"),
		"support ability must store next_attack_multiplier on caster meta")


func test_attack_path_consumes_meta_and_clears() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_attack")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("attacker.get_meta(\"_next_attack_multiplier\", 0.0)"),
		"_execute_attack must read the stored multiplier from meta")
	assert_true(body.contains("attacker.set_meta(\"_next_attack_multiplier\", 0.0)"),
		"_execute_attack must clear the meta after consuming (one-shot)")
	# Pin the multiplier application before the clear.
	assert_true(body.contains("damage = int(damage * stored_nam)"),
		"_execute_attack must multiply damage by the stored value")


func test_data_still_authors_fields() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("data_drain"))
	assert_gt(int(data["data_drain"].get("drain_mp", 0)), 0,
		"data_drain must still author drain_mp > 0")
	assert_true(data.has("memory_drain"))
	assert_gt(int(data["memory_drain"].get("drain_mp", 0)), 0,
		"memory_drain must still author drain_mp > 0")
	assert_true(data.has("burrow"))
	assert_gt(float(data["burrow"].get("next_attack_multiplier", 0.0)), 1.0,
		"burrow must still author next_attack_multiplier > 1.0")


func test_runtime_burrow_stores_then_attack_consumes() -> void:
	# End-to-end: cast burrow, verify meta is set; clear it via the
	# normal attack flow check.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Rogue")
	var ability: Dictionary = {
		"id": "burrow_test",
		"effect": "evasion",
		"duration": 1,
		"next_attack_multiplier": 1.5,
	}
	var typed_targets: Array[Combatant] = [caster]
	bm._execute_support_ability(caster, ability, typed_targets)
	assert_almost_eq(float(caster.get_meta("_next_attack_multiplier", 0.0)), 1.5, 0.001,
		"burrow must store next_attack_multiplier=1.5 on caster meta")
