extends GutTest

## Nintendo mode: Confirm on the EAST face (SNES layout Y X / B A) when on, SOUTH when off.
##
## Every profile in InputProfileManager is authored EAST-confirm and the other convention is
## DERIVED, so these tests pin the derivation rather than a second hand-maintained table.
## Regression target: a player pressing the button printed "A" on their pad and getting Cancel.

var _ipm: Node


func before_each() -> void:
	_ipm = load("res://src/input/InputProfileManager.gd").new()
	add_child_autofree(_ipm)


func test_nintendo_mode_defaults_on() -> void:
	assert_true(_ipm.nintendo_mode,
		"east-confirm is struktured's stated default; flipping it silently would invert every menu")


func test_on_leaves_confirm_on_east() -> void:
	_ipm.nintendo_mode = true
	assert_eq(_ipm.face_convention_indices("ui_accept", [1]), [1], "confirm stays EAST (index 1)")
	assert_eq(_ipm.face_convention_indices("ui_cancel", [0]), [0], "cancel stays SOUTH (index 0)")


func test_off_moves_confirm_to_south() -> void:
	_ipm.nintendo_mode = false
	assert_eq(_ipm.face_convention_indices("ui_accept", [1]), [0], "confirm moves to SOUTH for Xbox/PS")
	assert_eq(_ipm.face_convention_indices("ui_cancel", [0]), [1], "cancel moves to EAST")


func test_off_does_not_touch_other_actions() -> void:
	_ipm.nintendo_mode = false
	# Shoulders and Back share the 0/1 value space; a blanket swap would silently move Defer.
	assert_eq(_ipm.face_convention_indices("battle_defer", [9]), [9], "L shoulder untouched")
	assert_eq(_ipm.face_convention_indices("battle_advance", [10]), [10], "R shoulder untouched")
	assert_eq(_ipm.face_convention_indices("battle_toggle_auto", [4]), [4], "Back untouched")
	assert_eq(_ipm.face_convention_indices("ui_menu", [6, 7]), [6, 7], "Start+L3 untouched, both kept")


func test_face_family_detection() -> void:
	assert_eq(_ipm.face_family_for_device("Sony DualSense Wireless Controller"), "playstation")
	assert_eq(_ipm.face_family_for_device("Nintendo Switch Pro Controller"), "nintendo")
	assert_eq(_ipm.face_family_for_device("8BitDo SN30 Pro"), "nintendo")
	assert_eq(_ipm.face_family_for_device("Xbox Series X Controller"), "xbox")
	# The demo case: an unknown pad on Windows is overwhelmingly XInput.
	assert_eq(_ipm.face_family_for_device("Generic USB Gamepad"), "xbox",
		"unknown pads default to xbox glyphs — the Windows-demo default")


func test_glyph_follows_the_plastic_not_the_position() -> void:
	_ipm.nintendo_mode = true
	# Same physical button (EAST) in every case; only the silkscreen differs.
	assert_eq(_ipm.glyph_for_action("ui_accept", "Nintendo Switch Pro Controller"), "Ⓐ",
		"east is printed A on a Nintendo pad")
	assert_eq(_ipm.glyph_for_action("ui_accept", "Xbox Series X Controller"), "Ⓑ",
		"the SAME east button is printed B on an Xbox pad — the prompt must not lie")
	assert_eq(_ipm.glyph_for_action("ui_accept", "Sony DualSense Wireless Controller"), "○",
		"and Circle on a PlayStation pad")


func test_glyph_tracks_the_toggle() -> void:
	_ipm.nintendo_mode = false
	assert_eq(_ipm.glyph_for_action("ui_accept", "Xbox Series X Controller"), "Ⓐ",
		"with the toggle off an Xbox player confirms with the button printed A")
	assert_eq(_ipm.glyph_for_action("ui_cancel", "Xbox Series X Controller"), "Ⓑ")


func test_every_authored_glyph_renders() -> void:
	# A tofu glyph is invisible in review and obvious in a demo. FontFallbacks chains 4 subset
	# Noto fonts; squared 🅰/🅱 are NOT covered, circled caps and PS shapes are.
	var lbl := Label.new()
	add_child_autofree(lbl)
	var f: Font = lbl.get_theme_font("font")
	assert_not_null(f, "resolved a font")
	var missing := ""
	for family in _ipm.FACE_GLYPHS:
		for idx in _ipm.FACE_GLYPHS[family]:
			var ch: String = _ipm.FACE_GLYPHS[family][idx]
			var cp := ch.unicode_at(0)
			var covered := f.has_char(cp)
			for sub in f.fallbacks:
				if not covered and sub != null and sub.has_char(cp):
					covered = true
			if not covered:
				missing += ch
	assert_eq(missing, "", "face glyphs with no coverage in the font chain (would ship as tofu)")
