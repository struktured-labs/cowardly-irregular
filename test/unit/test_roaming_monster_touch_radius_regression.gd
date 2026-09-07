extends GutTest

## Touch radius for visible roaming monsters: 48 px (≈1.5x the 32px sprite half-width).
## Previous 112 px was the "mosey-then-suddenly-trigger" symptom — encounter
## fired ~3 sprite-widths from the visible sprite center.

const RoamingMonsterScript := preload("res://src/exploration/RoamingMonster.gd")


func test_touch_radius_is_tight_enough_to_match_visible_sprite() -> void:
	# Direct const access — GDScript constants aren't enumerable via `in` so
	# accessing the symbol is the contract check.
	var r: float = float(RoamingMonsterScript.TOUCH_RADIUS_PX)
	assert_true(r >= 40.0 and r <= 80.0,
		"Touch radius (%.0f) must be in [40, 80] px — the visible 32px sprite + a small margin. Outside that range the player either bonks-on-air (>80) or feels too pixel-precise (<40)." % r)


func test_collision_shape_uses_the_constant_not_a_hardcoded_value() -> void:
	var text: String = FileAccess.get_file_as_string("res://src/exploration/RoamingMonster.gd")
	assert_ne(text, "", "RoamingMonster.gd must be readable")
	assert_true(text.find("shape.radius = TOUCH_RADIUS_PX") != -1,
		"_setup_collision must assign the radius from TOUCH_RADIUS_PX — not a literal — so the constant stays load-bearing")
