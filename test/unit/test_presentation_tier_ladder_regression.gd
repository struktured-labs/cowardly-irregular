extends GutTest

## Phase D foundation: BattleJuice.presentation_tier() had ZERO consumers when Phase D began
## (declared in BattleJuice.gd, called nowhere in src/). Phase D's hardest requirement is
## "OFF reproduces current behaviour exactly", which is a claim about a path nothing had run.
## This pins the tier the RUNTIME can actually produce, driven by BattleScene's real ladder —
## not by invented time_scale values, which would pin the test's own arithmetic instead.

const BattleJuiceClass = preload("res://src/battle/BattleJuice.gd")
const BattleSceneClass = preload("res://src/battle/BattleScene.gd")

## Derived from the shipped constants, never hand-copied — a hand-copy drifts the day
## someone adds a rung, and drifts SILENTLY because both sides would still be self-consistent.
func _ladder() -> Array[float]:
	return BattleSceneClass.BATTLE_SPEEDS


func test_ladder_is_readable_and_populated() -> void:
	var speeds := _ladder()
	assert_gt(speeds.size(), 0,
		"CONTROL: BATTLE_SPEEDS read back empty — every assertion below would pass vacuously")
	assert_eq(speeds.size(), BattleSceneClass.BATTLE_SPEED_LABELS.size(),
		"speeds and labels must stay 1:1 — the speed indicator indexes labels by speed index")
	assert_true(0.25 in speeds,
		"CONTROL naming a known member: 0.25 is the documented default (label '1x'). A size check alone passes on a wrong-but-populated array")


func test_every_ladder_rung_maps_to_a_tier() -> void:
	var seen := {}
	for s in _ladder():
		var t: int = BattleJuiceClass.presentation_tier(s, false, false)
		assert_true(t in [BattleJuiceClass.Tier.FULL, BattleJuiceClass.Tier.REDUCED,
			BattleJuiceClass.Tier.MINIMAL, BattleJuiceClass.Tier.OFF],
			"speed %s produced a tier outside the enum" % s)
		seen[t] = true
	## SET EQUALITY, not "at least one" — a resolver stuck on a single tier still returns a
	## valid enum for every rung, and a per-rung loop passes while the mapping is degenerate.
	assert_eq(seen.keys().size(), 4,
		"all four tiers must be REACHABLE from the shipped ladder. Got %d distinct. If a boundary or a rung moves so that a tier becomes unreachable, the motion gated behind it becomes dead code and nothing else would say so" % seen.keys().size())


func test_the_default_speed_gets_full_presentation() -> void:
	## struktured 2026-07-11: engine 0.25 IS the default (label "1x"). If the default ever
	## stopped being FULL, every Phase D animation would be off by default and read as "not shipped".
	assert_eq(BattleJuiceClass.presentation_tier(0.25, false, false), BattleJuiceClass.Tier.FULL,
		"default battle speed (engine 0.25 = label 1x) must resolve to FULL")


func test_the_exact_ladder_mapping_is_pinned() -> void:
	## The VALUES, not just the shape. Two rungs collapse to FULL and three to OFF today —
	## a boundary edit that regroups them is a real presentation change and must be deliberate.
	var expected := {
		0.25: BattleJuiceClass.Tier.FULL,     # 1x  — default
		0.5:  BattleJuiceClass.Tier.FULL,     # 2x
		1.0:  BattleJuiceClass.Tier.REDUCED,  # 4x
		2.0:  BattleJuiceClass.Tier.MINIMAL,  # 8x
		4.0:  BattleJuiceClass.Tier.OFF,      # 16x
		8.0:  BattleJuiceClass.Tier.OFF,      # 32x
		16.0: BattleJuiceClass.Tier.OFF,      # 64x
	}
	var checked := 0
	for s in _ladder():
		assert_true(expected.has(s),
			"ladder rung %s is not pinned here — a new speed was added without deciding its tier" % s)
		if expected.has(s):
			assert_eq(BattleJuiceClass.presentation_tier(s, false, false), expected[s],
				"speed %s changed tier" % s)
			checked += 1
	assert_eq(checked, _ladder().size(),
		"every shipped rung must be checked — %d of %d were" % [checked, _ladder().size()])


func test_turbo_and_autogrind_force_off_at_every_speed() -> void:
	## These are the OFF paths a player reaches WITHOUT touching the speed ladder, so they
	## are the ones most likely to be exercised and least likely to be tested.
	var turbo_checked := 0
	var grind_checked := 0
	for s in _ladder():
		assert_eq(BattleJuiceClass.presentation_tier(s, true, false), BattleJuiceClass.Tier.OFF,
			"turbo must force OFF at speed %s" % s)
		turbo_checked += 1
		assert_eq(BattleJuiceClass.presentation_tier(s, false, true), BattleJuiceClass.Tier.OFF,
			"autogrind must force OFF at speed %s" % s)
		grind_checked += 1
	assert_eq(turbo_checked, _ladder().size(), "turbo not checked at every rung")
	assert_eq(grind_checked, _ladder().size(), "autogrind not checked at every rung")


## Requested by cowir-autogrind, and it is the arm that exposes the class: a test which only
## ever passes the bools EXPLICITLY can never see that omitting them changes the answer.
func test_omitting_the_bools_asserts_a_fact_instead_of_deriving_one() -> void:
	## time_scale DERIVES from Engine when omitted; turbo/autogrind ASSERT false when omitted.
	## That asymmetry is the defect — a caller who forgets gets "not grinding" for free, in
	## the unsafe direction, with no error and a valid Tier returned.
	var omitted: int = BattleJuiceClass.presentation_tier(1.0)
	var explicit_grind: int = BattleJuiceClass.presentation_tier(1.0, false, true)
	var explicit_turbo: int = BattleJuiceClass.presentation_tier(1.0, true, false)
	assert_eq(omitted, BattleJuiceClass.Tier.REDUCED,
		"omitting the bools yields the non-grinding answer")
	assert_eq(explicit_grind, BattleJuiceClass.Tier.OFF, "autogrind must force OFF")
	assert_eq(explicit_turbo, BattleJuiceClass.Tier.OFF, "turbo must force OFF")
	assert_ne(omitted, explicit_grind,
		"THE HAZARD, pinned: same speed, opposite tier, and the only difference is whether the caller remembered the third argument. Win98Menu shipped this exact omission and animated through visible autogrinds")


func test_off_is_reachable_by_speed_alone() -> void:
	## Guards the specific thing I nearly filed as a defect: if the ladder's top ever drops
	## below the 4.0 boundary, OFF becomes reachable ONLY via turbo/autogrind, and the
	## speed-based OFF path silently becomes dead without any test noticing.
	var by_speed := 0
	for s in _ladder():
		if BattleJuiceClass.presentation_tier(s, false, false) == BattleJuiceClass.Tier.OFF:
			by_speed += 1
	assert_gt(by_speed, 0,
		"no ladder rung reaches OFF by speed alone — OFF would be turbo/autogrind-only and the speed path dead")
