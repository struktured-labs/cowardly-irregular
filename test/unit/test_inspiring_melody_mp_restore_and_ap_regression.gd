extends GutTest

## tick 352: BattleManager._execute_support_ability has an
## "mp_restore_and_ap" arm so Bard's inspiring_melody actually
## restores MP + grants AP.
##
## Pre-fix inspiring_melody (abilities.json line ~437) had:
##   "effect": "mp_restore_and_ap"
##   "mp_restore_percent": 0.05
##   "ap_gain": 1
##
## After tick 351 routed "song" abilities to _execute_support_ability,
## inspiring_melody still fell through to the `_:` push_warning
## default — no arm matched "mp_restore_and_ap". Every cast was a
## silent fizzle: 15 MP consumed, AP spent, "Inspiring Melody" log
## line printed, but no MP restored and no AP granted to anyone.
##
## Closes the Bard ability trio (lullaby/discord/inspiring_melody)
## together with ticks 350 (smoke_bomb) and 351 (song/status routing
## + offensive statuses).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: mp_restore_and_ap arm exists ────────────────────────

func test_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"mp_restore_and_ap\":"),
		"_execute_support_ability must have an 'mp_restore_and_ap' arm")


# ── Source pin: arm reads both mp_restore_percent and ap_gain ───────

func test_arm_reads_both_fields() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"mp_restore_and_ap\":")
	assert_gt(arm_idx, -1)
	var arm_body: String = src.substr(arm_idx, 1500)
	assert_true(arm_body.contains("mp_restore_percent"),
		"arm must read mp_restore_percent from ability dict")
	assert_true(arm_body.contains("ap_gain"),
		"arm must read ap_gain from ability dict")
	assert_true(arm_body.contains("restore_mp"),
		"arm must call Combatant.restore_mp")
	assert_true(arm_body.contains("gain_ap"),
		"arm must call Combatant.gain_ap")


# ── Behavioral: inspiring_melody shape grants AP + restores MP ──────

func test_inspiring_melody_grants_ap_and_restores_mp() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	caster.is_alive = true
	var ally1: Object = combatant_script.new()
	add_child_autofree(ally1)
	ally1.max_hp = 100
	ally1.current_hp = 100
	ally1.max_mp = 80
	ally1.current_mp = 0  # MP depleted — so restore is observable.
	ally1.current_ap = 0
	ally1.is_alive = true
	var ally2: Object = combatant_script.new()
	add_child_autofree(ally2)
	ally2.max_hp = 100
	ally2.current_hp = 100
	ally2.max_mp = 60
	ally2.current_mp = 0
	ally2.current_ap = 0
	ally2.is_alive = true

	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	# Mirror inspiring_melody from abilities.json.
	var ability: Dictionary = {
		"id": "inspiring_melody_test",
		"type": "song",
		"effect": "mp_restore_and_ap",
		"mp_restore_percent": 0.05,
		"ap_gain": 1,
	}
	BattleManager._execute_support_ability(caster, ability, [ally1, ally2])

	# 5% of 80 = 4 MP restored to ally1; 5% of 60 = 3 MP to ally2.
	assert_eq(ally1.current_mp, 4,
		"ally1 must have 5%% of 80 max_mp restored = 4 MP")
	assert_eq(ally2.current_mp, 3,
		"ally2 must have 5%% of 60 max_mp restored = 3 MP")
	# Both allies get +1 AP.
	assert_eq(ally1.current_ap, 1,
		"ally1 must gain +1 AP")
	assert_eq(ally2.current_ap, 1,
		"ally2 must gain +1 AP")


# ── Behavioral: dead allies skipped ─────────────────────────────────

func test_dead_allies_skipped() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var dead_ally: Object = combatant_script.new()
	add_child_autofree(dead_ally)
	dead_ally.max_hp = 100
	dead_ally.current_hp = 0
	dead_ally.max_mp = 80
	dead_ally.current_mp = 0
	dead_ally.current_ap = 0
	dead_ally.is_alive = false

	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "inspiring_melody_test_dead",
		"type": "song",
		"effect": "mp_restore_and_ap",
		"mp_restore_percent": 0.05,
		"ap_gain": 1,
	}
	BattleManager._execute_support_ability(caster, ability, [dead_ally])

	assert_eq(dead_ally.current_mp, 0,
		"dead allies must not have MP restored (the for-loop's is_alive guard)")
	assert_eq(dead_ally.current_ap, 0,
		"dead allies must not gain AP")
