extends GutTest

## The daemon bounded ONE application and nothing bounded the TOTAL.
##
## SAFE_DELTA_MIN/MAX (0.85 .. 1.15) clamp a single multiplier. Applies compound,
## and measured at the band edge:
##
##     10 applies at 1.15  ->    4.05x the authored value
##     20 applies          ->   16.37x
##     50 applies          -> 1083.66x
##     50 applies at 0.85  ->   0.0003x   (grinding becomes impossible)
##
## The three dials are exp_multiplier / gold_multiplier / encounter_rate — the
## whole economy — and game_constants persists to the save. Triggers are
## area-entered, party-wipe, boss-defeat and level-up, so twenty applications is
## an ordinary playthrough rather than an adversarial case.
##
## ⚠️ BOTH writers needed it. try_auto_apply and force_apply carry the identical
## apply loop; I predicted one site, the assert found two, and bounding only the
## auto path would have left the manual Apply button unbounded. The band is about
## what is safe for the game, not about who asked.
##
## The bound reuses the SAME authored pair against the AUTHORED DEFAULT, so no new
## number is invented and widening the daemon's reach is one edit.

const RD := preload("res://src/llm/RebalanceDaemon.gd")


## Has game_constants but NO authored defaults — the reachable "no baseline" case.
## A state lacking game_constants entirely is guarded upstream by the apply loop,
## so testing that would pin an unreachable path.
class NoDefaults:
	extends Node
	var game_constants: Dictionary = {"exp_multiplier": 1.0}


class FakeState:
	extends Node
	const DEFAULT_GAME_CONSTANTS: Dictionary = {
		"exp_multiplier": 1.0, "gold_multiplier": 1.0, "encounter_rate": 1.0,
	}
	var game_constants: Dictionary = {}


var _gs: FakeState = null
var _d = null


func before_each() -> void:
	_gs = FakeState.new()
	_gs.game_constants = FakeState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	add_child_autofree(_gs)
	_d = RD.new()  # RefCounted — NOT a Node, so no add_child


## Drive the real clamp the apply loop calls, n times, as repeated applications.
func _drift(constant: String, multiplier: float, times: int) -> float:
	for _i in range(times):
		var requested: float = float(_gs.game_constants[constant]) * multiplier
		_gs.game_constants[constant] = _d._clamp_to_authored_band(_gs, constant, requested)
	return float(_gs.game_constants[constant])


# ── the defect ────────────────────────────────────────────────────────────────

func test_repeated_applies_cannot_run_the_economy_away() -> void:
	var after: float = _drift("exp_multiplier", RD.SAFE_DELTA_MAX, 50)
	gut.p("  50 applies at %.2f -> %.4fx (unbounded would be 1083.66x)" % [RD.SAFE_DELTA_MAX, after])
	assert_lte(after, 1.0 * RD.CUMULATIVE_DELTA_MAX + 0.0001,
		"fifty applications must not exceed the authored band — unbounded this reaches 1083x")


func test_repeated_applies_cannot_zero_the_economy() -> void:
	var after: float = _drift("encounter_rate", RD.SAFE_DELTA_MIN, 50)
	gut.p("  50 applies at %.2f -> %.4fx (unbounded would be 0.0003x)" % [RD.SAFE_DELTA_MIN, after])
	assert_gte(after, 1.0 * RD.CUMULATIVE_DELTA_MIN - 0.0001,
		"the downward direction needs the bound too — unbounded this reaches 0.0003x and grinding stops")


func test_the_bound_is_relative_to_the_AUTHORED_default_not_the_current_value() -> void:
	## The discriminator, and the reason a per-step clamp was not enough: a bound
	## measured against the CURRENT value can be walked outward one application at
	## a time, which is exactly what the old code did.
	_gs.game_constants["gold_multiplier"] = 1.15  # already at the ceiling
	var requested: float = 1.15 * RD.SAFE_DELTA_MAX  # a legal single step from here
	var got: float = _d._clamp_to_authored_band(_gs, "gold_multiplier", requested)
	assert_lte(got, 1.0 * RD.CUMULATIVE_DELTA_MAX + 0.0001,
		"a legal step from the ceiling must still be refused — otherwise the ceiling is a step, not a bound")


# ── it must still be a working feature ────────────────────────────────────────

func test_a_single_ordinary_nudge_still_lands_unchanged() -> void:
	## CONTROL: the bound must not turn the daemon off. One 1.05x from default is
	## well inside the band and must pass through untouched.
	var got: float = _d._clamp_to_authored_band(_gs, "exp_multiplier", 1.05)
	assert_almost_eq(got, 1.05, 0.0001,
		"an ordinary in-band nudge must be unaffected — this bounds runaway, it does not disable tuning")


func test_movement_in_both_directions_is_still_possible() -> void:
	assert_almost_eq(_d._clamp_to_authored_band(_gs, "gold_multiplier", 0.92), 0.92, 0.0001,
		"downward tuning inside the band must still work")
	assert_almost_eq(_d._clamp_to_authored_band(_gs, "gold_multiplier", 1.08), 1.08, 0.0001,
		"upward tuning inside the band must still work")


# ── the unknown-baseline direction ────────────────────────────────────────────

func test_an_unknown_constant_refuses_rather_than_permits() -> void:
	## This writes state that PERSISTS. An unknown baseline that allows the change
	## is the runaway direction of the same false zero the reward backstop had.
	_gs.game_constants["not_in_defaults"] = 2.0
	var got: float = _d._clamp_to_authored_band(_gs, "not_in_defaults", 99.0)
	assert_almost_eq(got, 2.0, 0.0001,
		"a constant with no authored default must keep its current value, not take the requested one")


func test_a_state_without_defaults_refuses_too() -> void:
	var bare := NoDefaults.new()
	add_child_autofree(bare)
	var got: float = _d._clamp_to_authored_band(bare, "exp_multiplier", 99.0)
	assert_almost_eq(got, 1.0, 0.0001,
		"no DEFAULT_GAME_CONSTANTS at all must refuse the change rather than apply it unbounded")


func test_both_apply_paths_route_through_the_bound() -> void:
	## try_auto_apply and force_apply carry the identical loop. I predicted one
	## site and the assert found two; this pins that neither drifts back.
	var src: String = FileAccess.get_file_as_string("res://src/llm/RebalanceDaemon.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_eq(src.count("_clamp_to_authored_band("), 3,
		"expected one definition plus BOTH writers (try_auto_apply and force_apply)")
	assert_eq(src.count("gs.game_constants[constant_name] = after"), 2,
		"CONTROL: there are exactly two sites that write a constant, so 2 callers covers them")
