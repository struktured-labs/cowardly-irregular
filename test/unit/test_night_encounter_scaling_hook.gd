extends GutTest

## Night encounter-rate multiplier hook (struktured directive msg 2643).
## Pins: the multiplier composes into OverworldController._check_encounter's
## existing multiplicative stack; the whole path is gated behind an ack
## toggle (game_constants["day_night_encounter_scaling"]) so the code
## ships as a no-op until struktured personally acks the numbers;
## forward-compat with cowir-main's pending GameState.is_night/is_dusk API
## via has_method (no-op if the API hasn't landed yet). Autogrind
## explicitly bypasses this path (msg 2646) — that's intended design,
## not a bug.

const OverworldControllerScript := preload("res://src/exploration/OverworldController.gd")

const NIGHT_MULT: float = 1.5
const DUSK_MULT: float = 1.25


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_day_night_helper_composes_into_check_encounter_stack() -> void:
	# The helper's call site must live inside _check_encounter, right
	# after the encounter_surge corruption multiplier — same multiplicative
	# stack the daemon and settings compose into.
	var src := _read("res://src/exploration/OverworldController.gd")
	var check_idx := src.find("func _check_encounter")
	assert_gt(check_idx, 0, "_check_encounter present")
	var next_fn := src.find("\nfunc ", check_idx + 1)
	var body: String = src.substr(check_idx, next_fn - check_idx) if next_fn > 0 else src.substr(check_idx)
	assert_true(body.contains("_day_night_encounter_multiplier"),
		"_check_encounter must call _day_night_encounter_multiplier")
	assert_true(body.contains("rate_multiplier *= _day_night_encounter_multiplier"),
		"multiplier composes multiplicatively (same shape as daemon/surge)")


func test_ack_gate_defaults_off_so_ship_is_no_op() -> void:
	# The whole path stays inert until struktured personally acks the
	# numbers by flipping game_constants["day_night_encounter_scaling"].
	# Ship-as-no-op is the design.
	var src := _read("res://src/exploration/OverworldController.gd")
	assert_true(src.contains("game_constants.get(\"day_night_encounter_scaling\", false)"),
		"ack gate reads the toggle from game_constants with default=false")


func test_uses_canonical_day_phase_api() -> void:
	# The v3.33.197 clock (msg 2683) ships get_time_of_day_name() as the
	# canonical phase-name API. Both night AND dusk arms fire against
	# the same live clock — the earlier is_dusk() pattern would have
	# been permanently inert since GameState never grew that method.
	var src := _read("res://src/exploration/OverworldController.gd")
	assert_true(src.contains("get_time_of_day_name"),
		"reads the canonical GameState.get_time_of_day_name() clock API")
	assert_true(src.contains("\"night\"") and src.contains("\"dusk\""),
		"branches on the two elevated phases (night + dusk)")
	# Belt: the has_method rollback guard should still be present so a
	# hypothetical API removal degrades gracefully instead of erroring.
	assert_true(src.contains("has_method(\"get_time_of_day_name\")"),
		"rollback guard on the canonical API name")


func test_suggested_multiplier_constants_are_flagged_ack_pending() -> void:
	# The values (1.5 night, 1.25 dusk) are proposed defaults from the
	# msg 2643 directive; final numbers land after struktured's ack.
	# Pin the constants + the comment naming them ack-pending.
	var src := _read("res://src/exploration/OverworldController.gd")
	assert_true(src.contains("DAY_NIGHT_ENCOUNTER_MULT_NIGHT: float = %s" % NIGHT_MULT),
		"night multiplier constant at suggested %s" % NIGHT_MULT)
	assert_true(src.contains("DAY_NIGHT_ENCOUNTER_MULT_DUSK: float = %s" % DUSK_MULT),
		"dusk multiplier constant at suggested %s" % DUSK_MULT)
	assert_true(src.contains("struktured-ack-pending") or src.contains("struktured's ack"),
		"suggested-defaults comment names the ack requirement")


func test_helper_returns_1_when_ack_gate_off_via_runtime_probe() -> void:
	# Runtime probe: with the default (ack off), the helper returns 1.0
	# regardless of any pending is_night mock. Belt over source-level pins.
	var ctrl := OverworldControllerScript.new()
	add_child_autofree(ctrl)
	await get_tree().process_frame
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload present")
	if gs == null:
		return
	# Ensure the ack toggle is off (default state).
	var prior = gs.game_constants.get("day_night_encounter_scaling", false)
	gs.game_constants["day_night_encounter_scaling"] = false
	var mult: float = ctrl._day_night_encounter_multiplier(gs)
	assert_eq(mult, 1.0, "ack gate off → multiplier is 1.0 (no-op ship)")
	# Restore prior state — belt vs shared-fixture leaks.
	if prior == null:
		gs.game_constants.erase("day_night_encounter_scaling")
	else:
		gs.game_constants["day_night_encounter_scaling"] = prior


func test_helper_null_gs_is_safe() -> void:
	var ctrl := OverworldControllerScript.new()
	add_child_autofree(ctrl)
	await get_tree().process_frame
	assert_eq(ctrl._day_night_encounter_multiplier(null), 1.0,
		"null gs → 1.0 (defensive)")


## Positive runtime probe against the live v3.33.197 clock: ack ON,
## day_phase manually placed in each band, verify each phase returns
## the expected multiplier. Guards against a future edit that silently
## rewires the phase mapping (which arm handles dusk vs dawn, etc).
func test_multipliers_map_to_live_phases() -> void:
	var ctrl := OverworldControllerScript.new()
	add_child_autofree(ctrl)
	await get_tree().process_frame
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_time_of_day_name"):
		gut.p("day_phase clock API absent — skipping live-phase probe")
		return
	# Snapshot + restore so we don't strand state for later tests.
	var prior_phase = gs.day_phase if "day_phase" in gs else 0.25
	var prior_ack = gs.game_constants.get("day_night_encounter_scaling", null)
	gs.game_constants["day_night_encounter_scaling"] = true
	# get_time_of_day_name bands: p<0.10 dawn, <0.50 day, <0.60 dusk, else night
	var cases: Array = [
		[0.05, 1.0],           # dawn — unchanged
		[0.30, 1.0],           # day  — unchanged
		[0.55, DUSK_MULT],     # dusk — elevated
		[0.75, NIGHT_MULT],    # night — elevated
	]
	for c in cases:
		gs.day_phase = c[0]
		var expected: float = c[1]
		var actual: float = ctrl._day_night_encounter_multiplier(gs)
		assert_almost_eq(actual, expected, 0.001,
			"day_phase=%s (%s) expected mult=%s got %s" % [
				c[0], gs.get_time_of_day_name(), expected, actual])
	# Restore
	gs.day_phase = prior_phase
	if prior_ack == null:
		gs.game_constants.erase("day_night_encounter_scaling")
	else:
		gs.game_constants["day_night_encounter_scaling"] = prior_ack
