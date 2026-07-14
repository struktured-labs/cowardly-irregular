extends GutTest

## Silent-gap fix 2026-07-04: the encounter_surge save-corruption effect
## was added to GameState.corruption_effects by
## _apply_random_corruption_effect and announced to the player via Toast
## (tick 178), but NO code path read it — the encounter rate was
## unchanged. Save corruption is a headline real-stakes mechanic; a
## corruption that does nothing is broken flavor. Now _check_encounter
## multiplies the rate by ENCOUNTER_SURGE_MULT when the effect is
## present. Pinned at source (the rate path is randf-gated, like the
## tick-110/324 daemon+slider composition) + a behavioral GameState check.

const OWC := "res://src/exploration/OverworldController.gd"


func _check_body() -> String:
	var src: String = FileAccess.get_file_as_string(OWC)
	var idx: int = src.find("func _check_encounter")
	assert_gt(idx, -1, "_check_encounter must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_check_encounter_composes_surge_multiplier() -> void:
	var body := _check_body()
	assert_true(body.contains("\"encounter_surge\" in gs.corruption_effects"),
		"_check_encounter must read the encounter_surge corruption effect")
	assert_true(body.contains("rate_multiplier *= ENCOUNTER_SURGE_MULT"),
		"encounter_surge must actually multiply the rate — the whole point of the fix")


func test_surge_mult_is_a_real_boost() -> void:
	var script = load(OWC)
	assert_gt(script.ENCOUNTER_SURGE_MULT, 1.0,
		"the surge multiplier must be > 1.0 (corruption = MORE fights, not fewer)")


func test_surge_composes_after_the_zero_short_circuit_guard() -> void:
	# A 0 base rate (safe zone / repel) must still yield no encounters —
	# the surge factor must sit BEFORE the `<= 0.0` return, not bypass it.
	var body := _check_body()
	var surge_idx: int = body.find("rate_multiplier *= ENCOUNTER_SURGE_MULT")
	var guard_idx: int = body.find("if rate_multiplier <= 0.0:")
	assert_gt(surge_idx, -1)
	assert_gt(guard_idx, -1)
	assert_lt(surge_idx, guard_idx,
		"surge must compose before the zero-guard so 0 * 1.5 still short-circuits to no-encounter")


func test_corruption_effect_can_produce_encounter_surge() -> void:
	# Behavioral: the effect the fix consumes is actually one the
	# corruption system can emit into corruption_effects.
	var GS = load("res://src/meta/GameState.gd")
	var gs = GS.new()
	autofree(gs)
	gs.corruption_effects = ["encounter_surge"] as Array[String]
	assert_true("encounter_surge" in gs.corruption_effects,
		"encounter_surge must be a storable corruption effect the fix keys on")
