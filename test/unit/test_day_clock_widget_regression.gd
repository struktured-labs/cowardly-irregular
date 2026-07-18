extends GutTest

## struktured 2026-07-18: overworld day/night clock — themed per world,
## "should disappear when you enter the menu."

const GAME_LOOP := "res://src/GameLoop.gd"


func test_all_six_worlds_have_themes() -> void:
	for w in range(1, 7):
		assert_true(DayClockWidget.WORLD_THEMES.has(w), "world %d needs a clock theme" % w)
		var t: Dictionary = DayClockWidget.WORLD_THEMES[w]
		assert_true(t.has("ring") and t.has("face"))


func test_every_band_has_a_glyph() -> void:
	for band in ["dawn", "day", "dusk", "night"]:
		assert_true(DayClockWidget.BAND_GLYPH.has(band), "band '%s' needs a glyph" % band)


func test_visibility_gates() -> void:
	# Detached widget with a stub parent carrying the state surface.
	var stub := GDScript.new()
	stub.source_code = "extends Node\nenum LoopState {EXPLORATION, BATTLE}\nvar current_state: int = LoopState.EXPLORATION"
	stub.reload()
	var parent: Node = stub.new()
	add_child_autofree(parent)
	var clock := DayClockWidget.new()
	parent.add_child(clock)

	clock.set_outdoor(true)
	clock.set_menu_open(false)
	clock._process(0.0)
	assert_true(clock.visible, "outdoor + no menu + exploring → shown")

	clock.set_menu_open(true)
	clock._process(0.0)
	assert_false(clock.visible, "MENU OPEN must hide the clock — the verbatim ask")

	clock.set_menu_open(false)
	clock.set_outdoor(false)
	clock._process(0.0)
	assert_false(clock.visible, "interiors/dungeons: no sky, no clock")

	clock.set_outdoor(true)
	parent.current_state = parent.LoopState.BATTLE
	clock._process(0.0)
	assert_false(clock.visible, "battle owns the screen")


func test_gameloop_wires_menu_flags() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	assert_true("_day_clock.set_menu_open(true)" in src, "menu open must hide the clock")
	assert_true("_day_clock.set_menu_open(false)" in src, "menu close must restore it")
	assert_true("_day_clock.set_outdoor(outdoor_scene)" in src, "outdoor gate shared with the tint overlay")
	assert_true("_day_clock.set_world(" in src, "per-world theming needs the world id")
