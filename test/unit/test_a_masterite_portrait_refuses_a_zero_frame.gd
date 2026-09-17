extends GutTest

## `MasteriteEncounter` scales its portrait by `TILE_SIZE * 2 / frame.x`, where `frame` comes from
## the manifest. A declared `frame_width: 0` divides to `inf` — the masterite renders at infinite
## scale and NOTHING reports it.
##
## ⛔ THE COSTUME IS A DIVISOR, NOT AN INDEX, which is why no sweep found it. cowir-sfx named the
## class 2026-09-17: a `.size()` or a declared size reaching `/` or `%` is the same hazard as one
## reaching `[]`, and a clamp-keyed search reaches none of them. This lane's own empty-list sweep
## came back clean on these files for exactly that reason.
##
## 🔑 AND IT IS THE WITHIN-LANE ASYMMETRY, WITH ONE AUTHOR: `RoamingMonster:163` refuses the same
## geometry from the same owner and falls back to the placeholder. This site did the identical
## division and refused nothing — both written by me, hours apart, on 2026-09-16.
##
## ⚠️ NO SHIPPED SHEET DECLARES A ZERO FRAME, so the refusing branch cannot be driven end-to-end.
## The proof is a PAIR and neither half is evidence alone: this arm for the RULE, driven with
## geometry nothing ships, and a source pin for the CONSUMER actually using it.
const Masterite := preload("res://src/exploration/MasteriteEncounter.gd")


## ⛔ THE INSTRUMENT FIRST, BOTH WAYS. A function that returned ZERO for everything would refuse
## every masterite and still pass an "it refuses a zero" assert.
func test_the_rule_accepts_real_geometry_and_refuses_degenerate() -> void:
	assert_eq(Masterite.usable_frame({"frame": Vector2i(32, 32)}), Vector2i(32, 32),
		"CONTROL: ordinary 32px geometry must be ACCEPTED, or every masterite falls back to procedural")
	assert_eq(Masterite.usable_frame({"frame": Vector2i(48, 48)}), Vector2i(48, 48),
		"CONTROL: a non-convention frame size is still usable — the rule is about ZERO, not about 32")

	for bad in [Vector2i(0, 32), Vector2i(32, 0), Vector2i(0, 0), Vector2i(-8, 32)]:
		assert_eq(Masterite.usable_frame({"frame": bad}), Vector2i.ZERO,
			("a %s frame divides to inf at the scale line and renders the masterite at infinite "
			+ "size with nothing failing — it must be refused so the procedural figure draws") % [bad])


## An entry with no frame at all, and one whose frame is the wrong TYPE — both reach the same
## `.get()` and neither should be trusted into a division.
func test_a_missing_or_malformed_frame_is_refused_or_defaulted() -> void:
	assert_eq(Masterite.usable_frame({}), Vector2i(32, 32),
		"an absent frame takes the documented convention, because absence must never refuse art")
	assert_eq(Masterite.usable_frame({"frame": "32x32"}), Vector2i.ZERO,
		"a frame of the wrong TYPE must be refused rather than coerced into a divisor")
	assert_eq(Masterite.usable_frame({"frame": null}), Vector2i.ZERO,
		"...and a null frame likewise")


## ⛔ THE CONSUMER HALF. The rule being correct does not mean _build_silhouette USES it — keep the
## call and discard its answer and every arm above stays green (Mutation 7, this lane, 2026-09-16).
func test_the_portrait_builder_asks_the_rule_before_dividing() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/exploration/MasteriteEncounter.gd")
	assert_gt(code.length(), 1000, "PRECONDITION: MasteriteEncounter must be readable and stripped")

	assert_true(code.contains("usable_frame(geo)"),
		"the builder must ask the rule for its frame rather than reading geo directly")
	assert_true(code.contains("frame != Vector2i.ZERO"),
		"...and must branch on the refusal, or asking the rule changes nothing")
	assert_false(code.contains("var frame: Vector2i = geo.get(\"frame\""),
		"reading the frame straight off geo is the unguarded form this replaced")
