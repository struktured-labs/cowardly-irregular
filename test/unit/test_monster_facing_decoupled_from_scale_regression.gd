extends GutTest

## Two bugs in one day, one root cause: frame size silently meant TWO unrelated
## things — how big to draw a monster, AND which way it faces.
##
##   cave_rat_king         a 256px sheet authored facing LEFT rendered backwards
##                         in battle (struktured, 2026-07-25: "I saw a rat sprite
##                         backwards in battle")
##   chancellor_mordaine   re-exported 256px -> 128px purely to gain the scale
##                         bump; that ALSO reversed her facing. It renders right
##                         only because she happens to be drawn facing left
##                         (caught at fold review 2026-07-26)
##
## The second is the dangerous one and the reason for this test. A resolution
## change is a SIZING decision. It must not be able to reverse a monster's facing
## as a side effect, with every check green, and be discovered by a player.
##
## So facing is DECLARED (manifest "flip_h") and only falls back to the frame-size
## convention. These assert the two decisions are genuinely independent — which a
## source read cannot tell you, because the old code produced correct output while
## conflating them.
##
## Note the shape: nothing here needs an allowlist or a suppression flag. The
## correct state today passes clean.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const SMALL := 128


func test_scale_bump_is_decided_by_frame_size_alone() -> void:
	assert_true(Loader.monster_needs_scale_bump(128, SMALL), "128px is at the threshold — bump")
	assert_true(Loader.monster_needs_scale_bump(64, SMALL), "smaller than threshold — bump")
	assert_false(Loader.monster_needs_scale_bump(256, SMALL), "256px proc-gen scale — no bump")
	assert_false(Loader.monster_needs_scale_bump(0, SMALL), "a zero/absent frame must not bump")


func test_declared_facing_overrides_the_frame_size_convention_in_both_directions() -> void:
	# cave_rat_king is the live case: 256px (convention says "don't flip") but
	# authored facing left, so the manifest declares flip_h true.
	assert_true(
		Loader.monster_faces_party("cave_rat_king", false),
		"cave_rat_king declares flip_h — the declaration must beat the frame-size convention, "
		+ "or it renders facing away from the party again"
	)
	# And the reverse direction must work too, or the mechanism only fixes one
	# of the two ways a sheet can be drawn wrong.
	assert_true(
		Loader.monster_faces_party("cave_rat_king", true),
		"a declared facing must not depend on what the convention happened to say"
	)


func test_undeclared_sheets_still_follow_the_convention() -> void:
	# The fallback must remain intact — 90-odd sheets rely on it and none of them
	# should need to declare anything.
	assert_true(Loader.monster_faces_party("__no_such_monster__", true),
		"an undeclared sheet takes the convention default (small frame -> flip)")
	assert_false(Loader.monster_faces_party("__no_such_monster__", false),
		"an undeclared sheet takes the convention default (large frame -> no flip)")


func test_a_resolution_change_cannot_silently_reverse_a_declared_facing() -> void:
	# THE regression. Simulate Mordaine's re-export: same monster, frame height
	# changes 256 -> 128, which flips the convention default. A declared facing
	# must be unmoved by that.
	var big_default := Loader.monster_needs_scale_bump(256, SMALL)   # false
	var small_default := Loader.monster_needs_scale_bump(128, SMALL) # true
	assert_ne(big_default, small_default,
		"precondition: the convention default really does invert across the threshold")

	var before := Loader.monster_faces_party("cave_rat_king", big_default)
	var after := Loader.monster_faces_party("cave_rat_king", small_default)
	assert_eq(before, after,
		"re-exporting a DECLARED monster at a different resolution changed its facing — "
		+ "a sizing decision must never reverse facing as a side effect")


func test_both_battle_sites_use_the_facing_helper_not_a_local_rule() -> void:
	# Battle-start and summon must agree; a summoned monster facing the wrong way
	# while its battle-start twin is correct is the parity bug this replaced.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_eq(src.count("HybridSpriteLoader.monster_faces_party("), 2,
		"exactly two flip sites (battle-start + summon) must resolve facing through the helper")
	assert_eq(src.count("HybridSpriteLoader.monster_needs_scale_bump("), 2,
		"and both must take sizing from the sizing helper, so neither can drift back into one boolean")


func test_declared_flip_entries_are_explained() -> void:
	# A bare "flip_h": true is a magic value; the next person needs to know the
	# sheet is drawn against convention and why. Requires the DELIVERABLE (the
	# note), never permission to skip — you can't silence this green.
	var raw := FileAccess.get_file_as_string("res://data/sprite_manifest.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "sprite_manifest must parse")
	var sheets: Dictionary = parsed.get("monster_sheets", {})
	var undocumented: Array = []
	for mid in sheets:
		var e = sheets[mid]
		if e is Dictionary and e.has("flip_h") and str(e.get("flip_h_reason", "")) == "":
			undocumented.append(mid)
	assert_eq(undocumented, [],
		"every sheet declaring flip_h must also carry flip_h_reason saying which way it is "
		+ "authored and why it differs from the frame-size convention: %s" % [undocumented])
