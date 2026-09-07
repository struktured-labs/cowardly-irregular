extends GutTest

## tick 350: BattleManager._execute_support_ability has an
## "evasion_up" arm so Rogue's smoke_bomb actually grants evasion.
##
## Pre-fix smoke_bomb (jobs.json line 409) had:
##   "effect": "evasion_up"
##
## But _execute_support_ability's match statement had NO arm for
## "evasion_up". The string list at line ~3291 includes "evasion"
## (no _up), so smoke_bomb's "evasion_up" fell through to the `_:`
## push_warning default ("unhandled support effect 'evasion_up'") —
## the Rogue's signature crowd-control did NOTHING.
##
## Every smoke_bomb cast was a silent fizzle: caster spent AP,
## MP cost (8) was consumed, the cooldown was triggered, but no
## evasion was actually applied to any ally. Combat continued as
## if the ability was never used.
##
## Same authored-but-unimplemented class as the unhandled effects
## tick 173 surfaced. Fix adds the dedicated arm mapping
## "evasion_up" → canonical "evasion" status name so
## _target_dodges_physical's 60% dodge roll actually fires.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: "evasion_up" arm exists ─────────────────────────────

func test_evasion_up_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Find _execute_support_ability function.
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"evasion_up\":"),
		"_execute_support_ability must have a dedicated 'evasion_up' arm for Rogue's smoke_bomb")


# ── Source pin: arm maps to canonical "evasion" status ──────────────

func test_evasion_up_maps_to_evasion_status() -> void:
	# The status NAME is "evasion" (no _up) — that's what
	# _target_dodges_physical (line ~5017) checks for. The effect
	# string is "evasion_up" because that's what jobs.json wrote.
	# The arm must translate the effect to the canonical status name.
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"evasion_up\":")
	assert_gt(arm_idx, -1)
	# Generous slice — the new arm has an 8-line comment block before
	# the actual add_status call, so 600 chars is too tight to capture.
	var arm_body: String = src.substr(arm_idx, 1500)
	assert_true(arm_body.contains("target.add_status(\"evasion\""),
		"evasion_up arm must apply the 'evasion' status (no _up suffix) so _target_dodges_physical's has_status check fires")


# ── Behavioral: applying evasion_up grants evasion status ───────────

func test_apply_evasion_up_grants_evasion_status() -> void:
	# Drive the support arm directly. _execute_support_ability is
	# called with caster, ability dict, and targets array.
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var ally: Object = combatant_script.new()
	add_child_autofree(ally)
	ally.max_hp = 100
	ally.current_hp = 100
	ally.is_alive = true

	# We need a BattleManager. Use the autoload.
	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	# Snapshot — the BattleManager autoload is shared across tests.
	var prior_targets: Array = []
	# Drive smoke_bomb-like ability through _execute_support_ability.
	var ability: Dictionary = {
		"id": "smoke_bomb_test",
		"effect": "evasion_up",
		"duration": 3,
		"success_rate": 1.0,  # Deterministic — always succeeds.
	}
	BattleManager._execute_support_ability(caster, ability, [ally])

	assert_true(ally.has_status("evasion"),
		"after evasion_up support arm, ally must have 'evasion' status — pre-fix the unhandled fallback did nothing")


# ── Sanity: success_rate guard still works ──────────────────────────

func test_evasion_up_respects_success_rate_zero() -> void:
	# success_rate = 0.0 → randf() < 0.0 is always false → no apply.
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var ally: Object = combatant_script.new()
	add_child_autofree(ally)
	ally.max_hp = 100
	ally.current_hp = 100
	ally.is_alive = true

	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "smoke_bomb_zero_chance",
		"effect": "evasion_up",
		"duration": 3,
		"success_rate": 0.0,
	}
	BattleManager._execute_support_ability(caster, ability, [ally])

	assert_false(ally.has_status("evasion"),
		"success_rate=0.0 must skip the apply — regression guard against the new arm ignoring success_rate")
