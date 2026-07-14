extends GutTest

## tick 421: monsters.json `can_cause_permadeath` flag now actually
## permadeaths PCs killed by flagged enemies, AND the `permakilled`
## status blocks revive() from bringing them back.
##
## Pre-fix the flag was authored on permadeath_reaper but no code
## path read it; players who lost a PC to the reaper revived them
## normally with Phoenix Down, defeating the "HIGH RISK" design.
##
## Two-piece fix:
##   1. BattleManager._maybe_apply_permadeath_on_kill applies the
##      permakilled status when an attacker with the flag kills a PC
##      (wired into the basic-attack + physical-ability + magic-
##      ability damage paths).
##   2. Combatant.revive refuses when permakilled is present.

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


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _maybe_apply_permadeath_on_kill"),
		"BattleManager must declare _maybe_apply_permadeath_on_kill helper")
	# Pin the flag read.
	assert_true(src.contains("data.get(\"can_cause_permadeath\", false)"),
		"helper must read can_cause_permadeath from monsters.json")


func test_helper_wired_into_attack_path() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# The attack path's call.
	assert_true(src.contains("_maybe_apply_permadeath_on_kill(attacker, actual_target)"),
		"basic-attack damage path must call the helper")
	# Ability paths use caster/target naming.
	assert_true(src.contains("_maybe_apply_permadeath_on_kill(caster, target)"),
		"ability damage paths must call the helper")


func test_revive_blocked_when_permakilled() -> void:
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func revive(hp_amount")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"permakilled\" in status_effects"),
		"revive must check for permakilled status")


func test_data_still_authors_can_cause_permadeath() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("permadeath_reaper"))
	assert_true(bool(data["permadeath_reaper"].get("can_cause_permadeath", false)),
		"permadeath_reaper must still author can_cause_permadeath=true")


func test_revive_refuses_permakilled_combatant() -> void:
	var c: Combatant = _make("Hero")
	c.die()
	c.add_status("permakilled")
	assert_false(c.is_alive)
	# revive should be a no-op.
	c.revive(50)
	assert_false(c.is_alive,
		"permakilled PC must NOT come back from revive — the entire point of the design")
	assert_eq(c.current_hp, 0,
		"current_hp must stay 0 — revive was refused")


func test_revive_works_on_non_permakilled_combatant() -> void:
	# Regression guard: don't accidentally break normal revival.
	var c: Combatant = _make("Hero")
	c.die()
	assert_false(c.is_alive)
	assert_false("permakilled" in c.status_effects)
	c.revive(50)
	assert_true(c.is_alive,
		"non-permakilled PC must revive normally")
	assert_gt(c.current_hp, 0,
		"normal revive must restore HP")
