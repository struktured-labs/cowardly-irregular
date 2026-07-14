extends GutTest

## Defensive regression: VolatilitySystem._get_macro_volatility() must
## clamp the returned value to [0.0, 1.0] so the documented soft cap on
## GameState.macro_volatility is enforced at the consumer boundary.
##
## Without the clamp, a corrupted save, buggy Speculator effect, or
## hand-edited save could push macro_volatility to e.g. 5.0 or -1.0;
## downstream consumers then produce:
##   • get_variance_range — final_width = base * (1 + macro * 0.5),
##     yielding 3.5x base instead of the design's 1.5x ceiling.
##   • check_tail_event — final_pct = tail_pct * (1 + macro), pushed
##     past 100% before clampf rescues it (silent guarantee, not the
##     probabilistic roll the system promises).
##   • reset_battle — band threshold cascade lands in FRACTURED for any
##     macro >= 0.9, including pathological 100.0.
##
## The test_override path is exempt from the clamp so unit tests can
## probe boundary math directly.
##
## Tests cover:
##   • Above-1.0 GameState value is clamped to 1.0 on read.
##   • Negative GameState value is clamped to 0.0 on read.
##   • In-range values pass through unchanged (idempotent).
##   • Test override path is NOT clamped (lets tests inject out-of-range
##     values when probing the boundary math).
##   • reset_battle on a pathological macro lands in FRACTURED (clamped
##     to 1.0 puts it in the >=0.9 branch — expected, not pathological).

const VolatilitySystemScript := preload("res://src/battle/VolatilitySystem.gd")


func _gs() -> Node:
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload must be reachable")
	return gs


func _snapshot_macro() -> float:
	return float(_gs().macro_volatility)


func _restore_macro(v: float) -> void:
	_gs().macro_volatility = v


# ── Clamp behaviour through GameState ─────────────────────────────────────────

func test_macro_volatility_clamped_to_1_when_gs_above_range() -> void:
	var snap := _snapshot_macro()
	_gs().macro_volatility = 5.0
	var vs := VolatilitySystemScript.new()
	assert_almost_eq(vs._get_macro_volatility(), 1.0, 0.0001,
		"_get_macro_volatility must clamp values >1.0 down to 1.0")
	_restore_macro(snap)


func test_macro_volatility_clamped_to_0_when_gs_below_range() -> void:
	var snap := _snapshot_macro()
	_gs().macro_volatility = -2.5
	var vs := VolatilitySystemScript.new()
	assert_almost_eq(vs._get_macro_volatility(), 0.0, 0.0001,
		"_get_macro_volatility must clamp negative values up to 0.0")
	_restore_macro(snap)


func test_macro_volatility_in_range_passes_through() -> void:
	var snap := _snapshot_macro()
	var vs := VolatilitySystemScript.new()
	for v in [0.0, 0.15, 0.4, 0.7, 0.99, 1.0]:
		_gs().macro_volatility = v
		assert_almost_eq(vs._get_macro_volatility(), v, 0.0001,
			"in-range macro %.2f must pass through unchanged" % v)
	_restore_macro(snap)


# ── Test override path is exempt ─────────────────────────────────────────────

func test_test_override_bypasses_clamp() -> void:
	# Unit tests must be able to probe boundary math by injecting out-of-range
	# values directly. The override path takes precedence over the GameState
	# read AND is intentionally not clamped.
	var vs := VolatilitySystemScript.new()
	vs._macro_override = 3.14
	assert_almost_eq(vs._get_macro_volatility(), 3.14, 0.0001,
		"_macro_override must take precedence over GameState read")
	vs._macro_override = -1.5
	assert_almost_eq(vs._get_macro_volatility(), -1.5, 0.0001,
		"_macro_override must NOT be clamped (lets tests probe out-of-range math)")


# ── Downstream consumers see clamped values ──────────────────────────────────

func test_pathological_gs_macro_lands_in_fractured_band() -> void:
	# Even with macro=999.0 the band threshold cascade in reset_battle must
	# behave as if macro==1.0 — FRACTURED, the documented max chaos band.
	var snap := _snapshot_macro()
	_gs().macro_volatility = 999.0
	var vs := VolatilitySystemScript.new()
	vs.reset_battle()
	assert_eq(vs.global_band, VolatilitySystemScript.Band.FRACTURED,
		"pathological macro must clamp to FRACTURED, not crash through the cascade")
	_restore_macro(snap)


func test_pathological_negative_gs_macro_lands_in_stable_band() -> void:
	var snap := _snapshot_macro()
	_gs().macro_volatility = -10.0
	var vs := VolatilitySystemScript.new()
	vs.reset_battle()
	assert_eq(vs.global_band, VolatilitySystemScript.Band.STABLE,
		"deeply-negative macro must clamp to STABLE (0.0) not stay negative")
	_restore_macro(snap)


func test_variance_range_bounded_under_pathological_macro() -> void:
	# get_variance_range mixes macro into final_width. With macro clamped
	# to 1.0, the maximum final_width factor from macro is (1 + 1*0.5) = 1.5.
	# The downstream clampf at 0.80 caps anyway, but we also pin that no
	# silent inversion can occur for negative macro.
	var snap := _snapshot_macro()
	_gs().macro_volatility = 1000.0
	var vs := VolatilitySystemScript.new()
	var range_max := vs.get_variance_range(null)
	# Width is symmetric: range = (1 - w, 1 + w). w is clamped to 0.80.
	assert_gte(range_max.x, 0.2 - 0.01,
		"variance range lower bound must respect the 0.80 width cap")
	assert_lte(range_max.y, 1.8 + 0.01,
		"variance range upper bound must respect the 0.80 width cap")

	_gs().macro_volatility = -1000.0
	var range_neg := vs.get_variance_range(null)
	# With macro clamped to 0.0, final_width = band_variance * 1.0 * 1.0
	# = 0.15 for STABLE; range = (0.85, 1.15). No inversion.
	assert_lt(range_neg.x, range_neg.y,
		"variance range must NEVER invert (negative macro must clamp, not flip)")
	_restore_macro(snap)
