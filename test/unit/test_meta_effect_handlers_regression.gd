extends GutTest

## tick 396: BattleManager._execute_meta_ability now handles three
## previously-unhandled meta_effects:
##   - rewind_turn (aliased to existing time_rewind path)
##   - force_weak_attack (attack debuff on target)
##   - time_stop (stun status on target)
##
## Pre-fix all three fell through to `_:` push_warning default —
## advanced Time Mage / Scriptweaver abilities consumed MP+AP and
## produced no mechanical effect. Player got nothing for these casts.
##
## 19 of 25 authored meta_effects still lack handlers; this tick
## closes the 3 with the clearest existing-mechanic fits. Remaining
## meta_effects (create_save, dungeon_skip, ng_plus_warp, etc.)
## require new save/world-skip subsystems and stay deferred.

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


func test_rewind_turn_aliased_to_time_rewind() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the combined case label.
	assert_true(src.contains("\"time_rewind\", \"rewind_turn\":"),
		"rewind_turn must alias time_rewind in the same case label")


func test_force_weak_attack_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"force_weak_attack\":")
	assert_gt(arm_idx, -1, "force_weak_attack arm must exist")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("Forced Weak"),
		"force_weak_attack must apply a 'Forced Weak' attack debuff")


func test_time_stop_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"time_stop\":")
	assert_gt(arm_idx, -1, "time_stop arm must exist")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("add_status(\"stun\""),
		"time_stop must apply the existing stun status to targets")


func test_force_weak_attack_applies_debuff() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Necromancer")
	var target: Combatant = _make("Boss")
	var ability: Dictionary = {
		"id": "test_boss_puppet",
		"meta_effect": "force_weak_attack",
		"stat_modifier": 0.5,
		"duration": 3,
	}
	bm._execute_meta_ability(caster, ability, [target])
	var found: bool = false
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Forced Weak":
			found = true
			break
	assert_true(found, "Forced Weak debuff must be present after force_weak_attack")


func test_time_stop_stuns_targets() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("TimeMage")
	var target: Combatant = _make("Enemy")
	var ability: Dictionary = {
		"id": "test_time_stop",
		"meta_effect": "time_stop",
		"duration": 1,
	}
	bm._execute_meta_ability(caster, ability, [target])
	assert_true("stun" in target.status_effects,
		"stun status must be applied to target after time_stop")
