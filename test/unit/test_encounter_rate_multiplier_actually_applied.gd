extends GutTest

## tick 110 regression: GameState.game_constants["encounter_rate"]
## must be consumed by OverworldController._check_encounter when
## computing whether a step triggers a battle. Pre-fix, the value
## was set + persisted + serialized + audited by the RebalanceDaemon
## (one of its 3 ALLOWED_CONSTANTS), but NO code path read it. A
## daemon proposal to nudge encounter_rate from 1.0 to 1.10 went
## through every layer producing zero gameplay change. Closes the
## third dead-knob gap after tick 109 wired exp_multiplier.
##
## Composition with the user-facing encounter_rate_multiplier
## (settings slider, separate field) is multiplicative — daemon
## trims the curve, slider expresses player preference, both stack.

const OVERWORLD_CONTROLLER := "res://src/exploration/OverworldController.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _check_encounter_body() -> String:
	var src := _read(OVERWORLD_CONTROLLER)
	var idx: int = src.find("func _check_encounter")
	assert_gt(idx, -1, "_check_encounter must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_check_encounter_reads_daemon_rate_from_game_constants() -> void:
	var body := _check_encounter_body()
	assert_true(body.contains("gs.game_constants.get(\"encounter_rate\", 1.0)"),
		"_check_encounter must read game_constants['encounter_rate'] — without this the daemon's encounter_rate knob is dead code")


func test_daemon_rate_composed_with_user_setting_multiplicatively() -> void:
	# Pin the composition. Pre-fix the user setting was the only
	# multiplier; daemon nudges had no path in.
	var body := _check_encounter_body()
	assert_true(body.contains("rate_multiplier *= daemon_rate"),
		"daemon encounter_rate must multiply into rate_multiplier — composes with the user's encounter_rate_multiplier slider")


func test_daemon_rate_clamped_defensively() -> void:
	# Defensive: same band as exp_multiplier in tick 109. Daemon
	# SAFE_DELTA gates the proposals tighter; the clamp catches debug
	# paths and post-load corruption.
	var body := _check_encounter_body()
	assert_true(body.contains("clampf("),
		"daemon encounter_rate must be clampf'd before use")
	assert_true(body.contains("0.1, 10.0"),
		"daemon encounter_rate clamp must use [0.1, 10.0] — matches the tick 109 exp_multiplier band")


func test_user_setting_multiplier_path_preserved() -> void:
	# Don't regress: the existing user-facing encounter_rate_multiplier
	# (settings slider) path must still read + apply.
	var body := _check_encounter_body()
	assert_true(body.contains("rate_multiplier = gs.encounter_rate_multiplier"),
		"_check_encounter must still read gs.encounter_rate_multiplier — the user-facing settings slider")


func test_read_guarded_against_missing_game_constants() -> void:
	# Defensive: tests may instantiate GameState without the dict.
	var body := _check_encounter_body()
	assert_true(body.contains("if \"game_constants\" in gs:"),
		"daemon encounter_rate read must guard on game_constants field — keeps unit tests passing without full autoload boot")


func test_default_value_preserves_vanilla_play() -> void:
	# Sanity: when game_constants.encounter_rate is unset (or 1.0),
	# the composed rate_multiplier == user setting only. Vanilla
	# play unchanged.
	var src := _read("res://src/meta/GameState.gd")
	assert_true(src.contains("\"encounter_rate\": 1.0"),
		"GameState.game_constants['encounter_rate'] must default to 1.0 — multiplicative identity, vanilla unchanged")


func test_rebalance_daemon_still_lists_encounter_rate_as_allowed() -> void:
	var src := _read("res://src/llm/RebalanceDaemon.gd")
	assert_true(src.contains("\"encounter_rate\""),
		"RebalanceDaemon ALLOWED_CONSTANTS must still include encounter_rate — the knob the new OverworldController read consumes")


func test_zero_short_circuit_still_present() -> void:
	# Pin: rate_multiplier <= 0.0 short-circuits to false. Daemon
	# can't bring the rate to 0 (clamp floor is 0.1) but the user
	# slider can. If a future refactor drops the short-circuit, the
	# encounter loop can churn pointlessly on every step.
	var body := _check_encounter_body()
	assert_true(body.contains("if rate_multiplier <= 0.0:"),
		"_check_encounter must keep the rate <= 0 short-circuit — user slider can hit zero")
