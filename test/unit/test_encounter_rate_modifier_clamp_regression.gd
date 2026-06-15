extends GutTest

## Defensive regression: EncounterSystem.set_encounter_rate_modifier()
## must clamp its argument to [0.0, ENCOUNTER_RATE_MODIFIER_MAX] so
## buggy callers can't lock the player into permanent no-encounters
## (negative product) or NaN math downstream.
##
## Trigger surface:
##   • A cursed-item / buggy ability with a sign bug pushes modifier
##     negative. encounter_rate * modifier < 0. roll < negative is
##     always false → no encounter triggers, ever.
##   • A corrupted save / hand-edited save pushes modifier huge. Then
##     encounter_rate * modifier > 1.0, every step triggers an
##     encounter (functional but disrespects the rate semantics) AND
##     get_steps_until_guaranteed_encounter calls log() on a negative
##     number, returning NaN.
##   • An ability writes NAN or INF. Same downstream NaN cascade.
##
## Fix: clamp at the write site. Also harden
## get_steps_until_guaranteed_encounter to short-circuit the 0.0 and
## 1.0 product boundaries (log(0) is undefined, log(1)==0 → div-by-0).
##
## Tests:
##   • Negative modifier clamps to 0.0
##   • Above-max modifier clamps to ENCOUNTER_RATE_MODIFIER_MAX
##   • In-range modifier passes through unchanged
##   • NaN modifier clamps to 0.0 (defensive)
##   • +INF and -INF modifiers clamp to 0.0
##   • get_steps_until_guaranteed_encounter returns -1 when effective
##     probability is <= 0 (modifier=0)
##   • get_steps_until_guaranteed_encounter returns 1 when effective
##     probability is >= 1 (no NaN cascade)

const EncounterSystemScript := preload("res://src/encounters/EncounterSystem.gd")


func _make_sys() -> Node:
	# Standalone instance (not the autoload) so each test gets fresh state.
	var sys: Node = EncounterSystemScript.new()
	add_child_autofree(sys)
	return sys


# ── Clamp behaviour ──────────────────────────────────────────────────────────

func test_negative_modifier_clamps_to_zero() -> void:
	var sys := _make_sys()
	sys.set_encounter_rate_modifier(-1.5)
	assert_almost_eq(sys.encounter_rate_modifier, 0.0, 0.0001,
		"Negative modifier must clamp to 0.0 — otherwise encounter_rate * modifier < 0 locks out encounters permanently")


func test_above_max_modifier_clamps_to_max() -> void:
	var sys := _make_sys()
	sys.set_encounter_rate_modifier(50.0)
	assert_almost_eq(sys.encounter_rate_modifier,
		EncounterSystemScript.ENCOUNTER_RATE_MODIFIER_MAX, 0.0001,
		"Modifier above MAX must clamp to the documented ceiling")


func test_in_range_modifier_passes_through() -> void:
	var sys := _make_sys()
	for v in [0.0, 0.25, 0.5, 1.0, 2.0, 5.0,
			EncounterSystemScript.ENCOUNTER_RATE_MODIFIER_MAX]:
		sys.set_encounter_rate_modifier(v)
		assert_almost_eq(sys.encounter_rate_modifier, v, 0.0001,
			"In-range modifier %.2f must pass through unchanged" % v)


func test_nan_modifier_clamps_to_zero() -> void:
	var sys := _make_sys()
	# Force NaN — sqrt(-1) is the most portable way without importing.
	var nan_val: float = sqrt(-1.0)
	assert_true(is_nan(nan_val), "Test setup: sqrt(-1) must produce NaN")
	sys.set_encounter_rate_modifier(nan_val)
	assert_almost_eq(sys.encounter_rate_modifier, 0.0, 0.0001,
		"NaN modifier must clamp to 0.0 (defensive) — otherwise NaN cascades into encounter math")


func test_inf_modifier_clamps_to_zero() -> void:
	var sys := _make_sys()
	var pos_inf: float = INF
	sys.set_encounter_rate_modifier(pos_inf)
	assert_almost_eq(sys.encounter_rate_modifier, 0.0, 0.0001,
		"+INF modifier must clamp to 0.0 (defensive)")
	var neg_inf: float = -INF
	sys.set_encounter_rate_modifier(neg_inf)
	assert_almost_eq(sys.encounter_rate_modifier, 0.0, 0.0001,
		"-INF modifier must clamp to 0.0 (defensive)")


# ── get_steps_until_guaranteed_encounter boundaries ─────────────────────────

func test_steps_returns_neg1_when_effective_probability_is_zero() -> void:
	var sys := _make_sys()
	sys.encounter_rate = 0.05
	sys.set_encounter_rate_modifier(0.0)
	assert_eq(sys.get_steps_until_guaranteed_encounter(), -1,
		"Effective probability == 0 must return -1 (never), not crash on log(1) = 0 divide")


func test_steps_returns_neg1_when_encounter_rate_is_zero() -> void:
	var sys := _make_sys()
	sys.encounter_rate = 0.0
	sys.set_encounter_rate_modifier(1.0)
	assert_eq(sys.get_steps_until_guaranteed_encounter(), -1,
		"Zero encounter_rate must return -1 (the pre-existing guard)")


func test_steps_returns_1_when_effective_probability_is_at_least_1() -> void:
	var sys := _make_sys()
	sys.encounter_rate = 0.5
	# Modifier 2.0 → effective = 1.0 (boundary).
	sys.set_encounter_rate_modifier(2.0)
	assert_eq(sys.get_steps_until_guaranteed_encounter(), 1,
		"Effective probability == 1 must return 1 (guaranteed every step), not NaN from log(0) = -inf")
	# Modifier well above 1.0 → effective > 1.0; same answer.
	sys.encounter_rate = 0.5
	sys.set_encounter_rate_modifier(5.0)
	assert_eq(sys.get_steps_until_guaranteed_encounter(), 1,
		"Effective probability > 1 must return 1 (guaranteed), not NaN from log(negative)")


func test_steps_returns_finite_positive_for_normal_rates() -> void:
	# Sanity: in-range product still produces a finite positive answer.
	var sys := _make_sys()
	sys.encounter_rate = 0.05
	sys.set_encounter_rate_modifier(1.0)
	var n: int = sys.get_steps_until_guaranteed_encounter()
	assert_gt(n, 0, "Default 5% rate must yield a positive estimate")
	assert_lt(n, 200, "Default 5% rate must yield a reasonable estimate (<200 steps for 99%)")
