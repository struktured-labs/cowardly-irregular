extends GutTest

## tick 365: EncounterSystem.use_repel stacks with any remaining repel
## instead of overwriting, and clamps negative inputs to 0.
##
## Pre-fix code was:
##   func use_repel(steps: int) -> void:
##       repel_steps_remaining = steps  # ← OVERWRITES
##
## Bug A — Overwrite: a player who buys a 50-step Repel, walks 3 steps
## (47 remaining), then uses a fresh Repel only gets 50 steps total
## instead of 97. Burning the second Repel cost them 47 effective steps.
##
## Bug B — Negative-silent-noop: a corrupted or mis-authored
## repel_steps value (e.g. -10 from a Scriptweaver edit or save drift)
## set repel_steps_remaining to -10. The `> 0` gate at the call site
## then treated it as "no repel active" and the player lost the item
## consume for zero effect.
##
## Post-fix: repel_steps_remaining = max(0, prior) + max(0, steps).

const ENCOUNTER_SYSTEM_PATH := "res://src/encounters/EncounterSystem.gd"


# ── Source pin: use_repel adds instead of replaces ──────────────────

func test_use_repel_stacks_instead_of_overwrites() -> void:
	var src: String = FileAccess.get_file_as_string(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func use_repel(")
	assert_gt(fn_idx, -1, "use_repel must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Negative pin: bare assignment `repel_steps_remaining = steps` must be GONE.
	assert_false(body.contains("repel_steps_remaining = steps\n"),
		"bare `repel_steps_remaining = steps` overwrite must be removed")
	# Positive pin: must add prior + new.
	assert_true(body.contains("prior + add"),
		"use_repel must accumulate: repel_steps_remaining = prior + add")


# ── Source pin: negative inputs clamped to 0 ────────────────────────

func test_use_repel_clamps_negative_inputs() -> void:
	var src: String = FileAccess.get_file_as_string(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func use_repel(")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("max(0, steps)"),
		"use_repel must clamp negative `steps` argument to 0")
	assert_true(body.contains("max(0, repel_steps_remaining)"),
		"use_repel must also clamp a potentially-negative prior state to 0 (defense in depth)")


# ── Behavioral: stack increments instead of replacing ───────────────

func test_use_repel_stacks_remaining_steps() -> void:
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	es.repel_steps_remaining = 47  # simulate 47 steps left from prior Repel
	es.use_repel(50)
	assert_eq(es.repel_steps_remaining, 97,
		"use_repel must STACK — 47 remaining + 50 new = 97 (not 50)")


# ── Behavioral: negative input is a no-op (clamped to +0) ───────────

func test_use_repel_negative_is_clamped_to_zero() -> void:
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	es.repel_steps_remaining = 30
	es.use_repel(-10)
	assert_eq(es.repel_steps_remaining, 30,
		"negative steps must NOT decrement an active repel — only stack non-negative values")


# ── Behavioral: negative prior state is repaired by clamp ───────────

func test_use_repel_repairs_negative_prior_state() -> void:
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	# Simulate save-state drift — prior state somehow ended up negative.
	es.repel_steps_remaining = -25
	es.use_repel(30)
	# Should be max(0, -25) + max(0, 30) = 0 + 30 = 30, NOT -25 + 30 = 5.
	assert_eq(es.repel_steps_remaining, 30,
		"negative prior state must be clamped to 0 before stacking — pre-fix would have leaked the negative offset")


# ── Behavioral: fresh repel from zero still works ───────────────────

func test_use_repel_fresh_state_still_works() -> void:
	# Sanity: the new stack logic must not regress the common case
	# (no prior repel + valid steps input).
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	es.repel_steps_remaining = 0
	es.use_repel(50)
	assert_eq(es.repel_steps_remaining, 50,
		"fresh Repel from zero must still set remaining to the new step count")
