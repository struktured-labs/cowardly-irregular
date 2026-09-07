extends GutTest

## tick 355: BattleManager._execute_support_ability has a "dispel_one"
## arm — weaker variant of dispel (tick 353) that removes ONE random
## buff or positive status.
##
## Pre-fix remove_element (abilities.json) used effect: "dispel_one"
## but no arm matched. Every cast fell into the `_:` push_warning
## default and silently fizzled — the JSON described "Removes a
## random buff or positive effect from the target" but no such
## effect was implemented.
##
## Same authored-but-unhandled class as ticks 350 (smoke_bomb),
## 351 (song routing), 352 (mp_restore_and_ap), 353 (dispel), and
## 354 (random_debuff).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: dispel_one arm exists ───────────────────────────────

func test_dispel_one_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"dispel_one\":"),
		"_execute_support_ability must have a 'dispel_one' arm")


# ── Source pin: arm builds a candidates pool ────────────────────────

func test_arm_builds_candidate_pool() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"dispel_one\":")
	assert_gt(arm_idx, -1)
	var arm_body: String = src.substr(arm_idx, 2500)
	assert_true(arm_body.contains("var candidates"),
		"dispel_one arm must build a candidates pool covering both buffs and positive statuses")
	# Must pick randomly from the pool (not always the first).
	assert_true(arm_body.contains("randi() % candidates.size()"),
		"dispel_one arm must pick a random candidate")


# ── Behavioral: removes exactly one of two buffs ────────────────────

func test_removes_exactly_one_of_two_buffs() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.max_hp = 200
	enemy.current_hp = 200
	enemy.is_alive = true
	enemy.add_buff("BossAttack", "attack", 1.5, 5)
	enemy.add_buff("BossSpeed", "speed", 1.3, 5)
	assert_eq(enemy.active_buffs.size(), 2,
		"sanity: 2 buffs before dispel_one")

	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "remove_element_test",
		"type": "support",
		"effect": "dispel_one",
	}
	BattleManager._execute_support_ability(caster, ability, [enemy])

	assert_eq(enemy.active_buffs.size(), 1,
		"dispel_one must remove exactly ONE buff (was 2, must be 1)")


# ── Behavioral: empty target → no crash, log "nothing to dispel" ────

func test_empty_target_handles_gracefully() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.is_alive = true
	# No buffs, no positive statuses.
	assert_eq(enemy.active_buffs.size(), 0,
		"sanity: no buffs at start")

	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "remove_element_empty",
		"type": "support",
		"effect": "dispel_one",
	}
	BattleManager._execute_support_ability(caster, ability, [enemy])
	# If we got here, no crash. Source-pin the log behavior:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"dispel_one\":")
	var arm_body: String = src.substr(arm_idx, 2500)
	assert_true(arm_body.contains("nothing to dispel"),
		"dispel_one arm must surface 'nothing to dispel' when the target has nothing dispellable")
