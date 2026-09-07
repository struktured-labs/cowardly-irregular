extends GutTest

## tick 356: BattleManager._execute_support_ability has a
## "default_stance" arm for the Bravely Default-style `default`
## ability.
##
## Pre-fix the `default` ability (abilities.json) used effect:
## "default_stance" but no arm matched. Every cast fizzled — the
## ability has 0 MP cost so the player wasn't punished for it, but
## clicking Default did nothing: no damage reduction, no defending
## flag, no log line.
##
## Combatant.is_defending (line ~42) is already read by take_damage
## (line ~212) for 50% damage reduction. The fix just sets the flag
## on the caster. The bp_gain field (Bravely Default's brave-points
## bank) is unimplemented — separate Combat System Mutation feature
## per CLAUDE.md — so we don't read it here.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: default_stance arm exists ───────────────────────────

func test_default_stance_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"default_stance\":"),
		"_execute_support_ability must have a 'default_stance' arm")


# ── Source pin: arm sets is_defending = true ────────────────────────

func test_arm_sets_is_defending() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"default_stance\":")
	assert_gt(arm_idx, -1)
	var arm_body: String = src.substr(arm_idx, 1500)
	assert_true(arm_body.contains("target.is_defending = true"),
		"default_stance arm must set is_defending = true — that's what take_damage reads for the 50% damage reduction")


# ── Behavioral: applying default_stance flips is_defending ──────────

func test_apply_default_stance_flips_flag() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	caster.max_hp = 100
	caster.current_hp = 100
	caster.is_alive = true
	caster.is_defending = false  # Pre-state

	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "default_test",
		"type": "support",
		"effect": "default_stance",
	}
	BattleManager._execute_support_ability(caster, ability, [caster])

	assert_true(caster.is_defending,
		"is_defending must be true after default_stance — pre-fix the call did nothing")


# ── Behavioral: dead targets skipped ────────────────────────────────

func test_dead_target_skipped() -> void:
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var dead: Object = combatant_script.new()
	add_child_autofree(dead)
	dead.is_alive = false
	dead.is_defending = false

	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "default_test_dead",
		"type": "support",
		"effect": "default_stance",
	}
	BattleManager._execute_support_ability(caster, ability, [dead])

	assert_false(dead.is_defending,
		"dead targets must not get is_defending — the is_alive guard in the for-loop must skip them")


# ── Behavioral: damage reduction actually applies after stance ──────

func test_damage_reduction_after_stance() -> void:
	# End-to-end: set the stance via the arm, then take damage and
	# verify the 50% reduction fires (via take_damage line ~212).
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var defender: Object = combatant_script.new()
	add_child_autofree(defender)
	defender.max_hp = 100
	defender.current_hp = 100
	defender.is_alive = true
	defender.defense = 0
	defender.is_defending = false

	if BattleManager == null:
		return

	# Snapshot damage WITHOUT stance.
	var damage_no_stance: int = defender.take_damage(20, false)
	# Reset.
	defender.current_hp = 100

	# Apply default_stance.
	var ability: Dictionary = {
		"id": "default_dmg_test",
		"type": "support",
		"effect": "default_stance",
	}
	BattleManager._execute_support_ability(defender, ability, [defender])
	assert_true(defender.is_defending, "sanity: stance applied")

	# Same damage WITH stance — should be ~50% less.
	var damage_with_stance: int = defender.take_damage(20, false)
	assert_lt(damage_with_stance, damage_no_stance,
		"damage taken WITH default_stance must be less than without — the take_damage 50% reduction fires")
