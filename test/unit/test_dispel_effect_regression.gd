extends GutTest

## tick 353: BattleManager._execute_support_ability has a "dispel"
## arm that strips active_buffs + positive statuses from the target.
##
## Pre-fix 7 abilities used effect "dispel":
##   masterite_dispel, cardinality_zero, garbage_collect_all,
##   intersection_null, optimize_away, undefine, void_breath
##
## None had a handler arm. Every cast fell into the `_:` push_warning
## default — masterite_dispel, the player-facing W6 anti-boss tool,
## just SAID it stripped enhancements but did nothing. Same
## authored-but-unhandled class as ticks 350 (smoke_bomb), 351 (song
## routing), 352 (mp_restore_and_ap).
##
## Symptom: "the W5 boss casts barrier + buff, I dispel it, and
## nothing changes. Then they crit my party with the still-active
## attack buff."

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: dispel arm exists ───────────────────────────────────

func test_dispel_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"dispel\":"),
		"_execute_support_ability must have a 'dispel' arm")


# ── Source pin: arm clears active_buffs + positive statuses ─────────

func test_dispel_arm_clears_buffs_and_statuses() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"dispel\":")
	assert_gt(arm_idx, -1)
	var arm_body: String = src.substr(arm_idx, 2500)
	assert_true(arm_body.contains("active_buffs.clear()"),
		"dispel arm must clear active_buffs (strip all buffs)")
	assert_true(arm_body.contains("remove_status(s)"),
		"dispel arm must remove positive statuses")


# ── Behavioral: dispel strips active buffs ──────────────────────────

func test_dispel_strips_active_buffs() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.max_hp = 200
	enemy.current_hp = 200
	enemy.is_alive = true
	# Apply 2 buffs to the enemy.
	enemy.add_buff("BossEmpower", "attack", 1.5, 5)
	enemy.add_buff("BossSpeedup", "speed", 1.3, 5)
	assert_eq(enemy.active_buffs.size(), 2,
		"sanity: enemy should have 2 buffs before dispel")

	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "masterite_dispel_test",
		"type": "support",
		"effect": "dispel",
	}
	BattleManager._execute_support_ability(caster, ability, [enemy])

	assert_eq(enemy.active_buffs.size(), 0,
		"after dispel, enemy must have ZERO active buffs (pre-fix the call did nothing — 2 buffs remained)")


# ── Behavioral: dispel removes positive statuses ────────────────────

func test_dispel_removes_positive_statuses() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.max_hp = 200
	enemy.current_hp = 200
	enemy.is_alive = true
	enemy.add_status("barrier", 3)
	enemy.add_status("regen", 3)

	if BattleManager == null:
		return

	var ability: Dictionary = {"id": "dispel_test", "type": "support", "effect": "dispel"}
	BattleManager._execute_support_ability(caster, ability, [enemy])

	assert_false(enemy.has_status("barrier"),
		"dispel must remove barrier (positive status)")
	assert_false(enemy.has_status("regen"),
		"dispel must remove regen (positive status)")


# ── Behavioral: dispel leaves NEGATIVE statuses alone ───────────────

func test_dispel_does_not_remove_debuffs() -> void:
	# Defining "positive" via inclusion list means debuffs (poison, etc.)
	# are NOT removed by dispel — that's by design (would be "cleanse").
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.is_alive = true
	enemy.add_status("poison", 3)
	enemy.add_status("blind", 3)

	if BattleManager == null:
		return

	var ability: Dictionary = {"id": "dispel_test_neg", "type": "support", "effect": "dispel"}
	BattleManager._execute_support_ability(caster, ability, [enemy])

	# Negative statuses must remain — dispel ≠ cleanse.
	assert_true(enemy.has_status("poison"),
		"dispel must NOT remove poison (it's a debuff, not a positive status)")
	assert_true(enemy.has_status("blind"),
		"dispel must NOT remove blind")
