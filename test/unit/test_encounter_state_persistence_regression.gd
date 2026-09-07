extends GutTest

## tick 417: EncounterSystem.repel_steps_remaining and
## steps_since_last_encounter survive save+quit.
##
## Pre-fix neither field was persisted — a player who used a 30-gold
## Repel, walked 3 steps, then saved and quit lost the remaining
## 47 protected steps on reload. Same for the minimum-steps gate
## (steps_since_last_encounter) which would reset, briefly allowing
## back-to-back encounters right after a load.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_create_save_data_persists_encounter_state() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_save_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"encounter_state\""),
		"_create_save_data must include encounter_state field")
	assert_true(body.contains("repel_steps_remaining"),
		"encounter_state must include repel_steps_remaining")
	assert_true(body.contains("steps_since_last_encounter"),
		"encounter_state must include steps_since_last_encounter")


func test_apply_save_data_restores_encounter_state() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("data.has(\"encounter_state\")"),
		"_apply_save_data must restore encounter_state")
	# Type guard so a malformed save doesn't crash.
	assert_true(body.contains("raw_es is Dictionary"),
		"_apply_save_data must type-guard encounter_state before reads")
	# Per-field type guard so a partial save doesn't reset the other to default.
	assert_true(body.contains("raw_es.has(\"repel_steps_remaining\")"),
		"_apply_save_data must per-field guard repel_steps_remaining")


func test_apply_save_data_clamps_negative_values() -> void:
	# Defense in depth: a corrupted save with -5 must clamp to 0
	# (the negative-repel footgun closed in tick 365).
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("max(0, int(raw_es[\"repel_steps_remaining\"]))"),
		"_apply_save_data must clamp repel_steps_remaining to >= 0 on load")


func test_round_trip_preserves_repel_steps() -> void:
	# End-to-end: set state, save, change, load, verify.
	var ss = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	var es = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	if ss == null or es == null:
		pending("SaveSystem + EncounterSystem autoloads required")
		return
	var prior_repel: int = es.repel_steps_remaining
	var prior_steps: int = es.steps_since_last_encounter
	# Set known state.
	es.repel_steps_remaining = 47
	es.steps_since_last_encounter = 3
	var save_data: Dictionary = ss._create_save_data()
	# Clear current state.
	es.repel_steps_remaining = 0
	es.steps_since_last_encounter = 0
	# Apply save.
	ss._apply_save_data(save_data)
	assert_eq(es.repel_steps_remaining, 47,
		"repel_steps_remaining must survive a save+load round-trip")
	assert_eq(es.steps_since_last_encounter, 3,
		"steps_since_last_encounter must survive the round-trip")
	# Restore.
	es.repel_steps_remaining = prior_repel
	es.steps_since_last_encounter = prior_steps
