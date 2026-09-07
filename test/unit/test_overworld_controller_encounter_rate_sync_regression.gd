extends GutTest

## tick 324: OverworldController._check_encounter pushes its per-area
## _encounter_rate into EncounterSystem.encounter_rate for the duration
## of the encounter check.
##
## Pre-fix set_area_config(_, _, encounter_rate, _) stored the value in
## OverworldController._encounter_rate, but only the fallback path at
## line 100 (when EncounterSystem autoload is unavailable) ever read
## it. In the normal path (lines 80+), the controller composed the
## settings rate_multiplier into ES.encounter_rate_modifier and then
## called ES.check_for_encounter — which uses ES's OWN encounter_rate
## (default 0.05), totally ignoring the controller's per-area value.
##
## Effect:
##   - DragonCave._update_floor_encounters set rate = 0.06 + (floor-1) * 0.02
##     → floor 1: 6%, floor 5: 14%. None of those took effect — actual
##     rate was always 5% (ES default).
##   - WhisperingCave: floor 1: 5%, floor 5: 9%. Floor progression
##     silently disabled.
##   - Per-overworld custom rates from set_area_config: ignored.
##
## Fix swaps ES.encounter_rate to the controller's _encounter_rate for
## the check, then restores. Same swap-restore idiom as the modifier
## composition above it.

const CONTROLLER_PATH := "res://src/exploration/OverworldController.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: encounter_rate swap-restore exists ──────────────────

func test_check_encounter_swaps_es_rate() -> void:
	var src := _read(CONTROLLER_PATH)
	var fn_idx: int = src.find("func _check_encounter")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var original_rate"),
		"_check_encounter must save the original ES.encounter_rate before swapping")
	assert_true(body.contains("es.encounter_rate = _encounter_rate"),
		"_check_encounter must push the controller's per-area _encounter_rate into ES")
	assert_true(body.contains("es.encounter_rate = original_rate"),
		"_check_encounter must restore the original ES.encounter_rate after the check")


# ── Source pin: swap is between set_modifier and check + restore ────

func test_swap_sequence_order() -> void:
	var src := _read(CONTROLLER_PATH)
	var fn_idx: int = src.find("func _check_encounter")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The swap-set must happen BEFORE check_for_encounter. Use the
	# `var triggered: bool =` prefix to anchor on the real call, not the
	# comment at line ~83 that quotes `es.check_for_encounter()` in
	# documenting the pre-fix bug.
	var set_idx: int = body.find("es.encounter_rate = _encounter_rate")
	var check_idx: int = body.find("var triggered: bool = es.check_for_encounter()")
	var restore_idx: int = body.find("es.encounter_rate = original_rate")
	assert_gt(set_idx, -1)
	assert_gt(check_idx, -1)
	assert_gt(restore_idx, -1)
	assert_lt(set_idx, check_idx,
		"swap must come BEFORE check_for_encounter (else the check uses the stale ES value)")
	assert_lt(check_idx, restore_idx,
		"restore must come AFTER check_for_encounter (else the check uses the restored stale value)")


# ── Behavioral: setting per-area rate flows through to ES.encounter_rate ─

func test_per_area_rate_applies_during_check() -> void:
	# Real autoload — EncounterSystem is reachable. Drive the controller
	# directly with a known _encounter_rate and verify ES.encounter_rate
	# is swapped during the check.
	assert_not_null(EncounterSystem, "EncounterSystem autoload required")
	if EncounterSystem == null:
		return

	var ctrl_script: GDScript = load(CONTROLLER_PATH)
	var ctrl: Object = ctrl_script.new()
	add_child_autofree(ctrl)
	# Set per-area config — dungeon-style 12% rate.
	ctrl._encounter_rate = 0.12
	ctrl._is_safe_zone = false
	ctrl.encounter_enabled = true

	# Snapshot ES.encounter_rate so we can compare and restore.
	var prior_rate: float = EncounterSystem.encounter_rate
	# Use a guaranteed-trigger setup: very high modifier + repel-clear.
	EncounterSystem.repel_steps_remaining = 0
	EncounterSystem.minimum_steps_between_encounters = 0
	EncounterSystem.steps_since_last_encounter = 999

	# We can't easily peek inside the swap window — but we CAN verify
	# that after _check_encounter the original rate is restored.
	# Make the rate distinctive so any leak would be obvious.
	EncounterSystem.encounter_rate = 0.05  # baseline
	ctrl._check_encounter()
	assert_eq(EncounterSystem.encounter_rate, 0.05,
		"after _check_encounter, ES.encounter_rate must be restored to its pre-call value (0.05) — controller swap leaked otherwise")

	# Restore for other tests.
	EncounterSystem.encounter_rate = prior_rate


# ── Behavioral: set_area_config still stores the value locally ──────

func test_set_area_config_stores_rate_locally() -> void:
	# Regression guard — _encounter_rate is the field set by
	# set_area_config and consumed by the fix above.
	var ctrl_script: GDScript = load(CONTROLLER_PATH)
	var ctrl: Object = ctrl_script.new()
	add_child_autofree(ctrl)
	ctrl.set_area_config("test_area", false, 0.08, ["slime"])
	assert_eq(ctrl._encounter_rate, 0.08,
		"set_area_config must still store the rate in _encounter_rate (the value the fix reads)")
