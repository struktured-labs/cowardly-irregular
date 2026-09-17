extends GutTest

## TitleScreen, SaveScreen, WorldMapMenu and JobMenu, converted to the latched reader.
##
## The WORLD MAP is the one worth the arms: it is a GRID, so it navigates on all four directions,
## and the two axes must latch INDEPENDENTLY — a single latch would let a held vertical swallow a
## horizontal step. That property has a helper-level arm; this is its first grid consumer.
##
## TitleScreen is the first thing a player touches and SaveScreen the screen where a mis-aimed
## cursor costs the most. Neither had a test driving its navigation before this file.

const TitleScript = preload("res://src/ui/TitleScreen.gd")
const SaveScript = preload("res://src/ui/SaveScreen.gd")
const WorldMapScript = preload("res://src/ui/WorldMapMenu.gd")

const RAMP := [0.55, 0.7, 0.85, 0.95, 1.0]


func _motion(axis: int, v: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	return ev


func _clear() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(a)
	MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.0))
	MenuNav.step(_motion(JOY_AXIS_LEFT_X, 0.0))


func before_each() -> void:
	_clear()


func after_each() -> void:
	_clear()


func _push(menu: Node, action: String, axis: int, sign: float) -> void:
	Input.action_press(action)
	for v in RAMP:
		menu._input(_motion(axis, v * sign))


# ------------------------------------------------------------------ SaveScreen

func test_the_save_slots_step_once_per_stick_push() -> void:
	var m = SaveScript.new()
	add_child_autofree(m)
	m.visible = true
	m._slot_panels = [Control.new(), Control.new(), Control.new()]
	m.selected_slot = 0
	_push(m, "ui_down", JOY_AXIS_LEFT_Y, 1.0)
	assert_eq(m.selected_slot, 1, "one push is one slot — a mis-aimed cursor costs most here")


# ----------------------------------------------------------------- World map

func _world_map() -> Node:
	var m = WorldMapScript.new()
	add_child_autofree(m)
	m.visible = true
	m._selected = 0
	return m


## ⚠️ PUSH DOWN, NOT RIGHT, and the reason is measured: the grid is 2 columns wide, so from cell 0
## the row-edge clamp stops a horizontal burst after ONE step all by itself — the arm passed
## against the unconverted code and discriminated nothing. Vertically there are three rows, so a
## ramp really did carry the cursor 0 -> 2 -> 4 before this change.
func test_the_world_map_steps_once_per_stick_push() -> void:
	var m := _world_map()
	_push(m, "ui_down", JOY_AXIS_LEFT_Y, 1.0)
	assert_eq(m._selected, 2, "one push is one ROW of the grid — a ramp used to carry it two")


## ⛔ THE GRID PROPERTY: the two axes latch independently, so a held vertical cannot swallow a
## horizontal step. This is MenuNav's first grid consumer and the first place it is observable
## on a real menu rather than on the helper.
func test_a_held_vertical_does_not_swallow_a_horizontal_step_on_the_map() -> void:
	var m := _world_map()
	m._selected = 0
	Input.action_press("ui_down")
	m._input(_motion(JOY_AXIS_LEFT_Y, 0.9))
	var after_down: int = m._selected
	assert_ne(after_down, 0, "precondition: the vertical stepped")
	m._input(_motion(JOY_AXIS_LEFT_Y, 1.0))
	assert_eq(m._selected, after_down, "…and its ramp does not repeat")

	Input.action_press("ui_right")
	m._input(_motion(JOY_AXIS_LEFT_X, 0.9))
	assert_eq(m._selected, after_down + 1,
		"a horizontal push must still step while the vertical is held")


# ---------------------------------------------------------------- TitleScreen

## TitleScreen CLAMPS rather than wrapping and skips disabled rows, so the assertion is "one
## enabled row", not "index + 1". The field is `selected_index`; my first version guessed
## `selected_option` and the precondition caught it rather than the arm passing on a -1.
func test_the_title_menu_steps_once_per_stick_push() -> void:
	var m = TitleScript.new()
	add_child_autofree(m)
	m.visible = true
	# _input refuses until input is enabled and the screen has left PRESS_START — read off
	# _input's own guards rather than guessed; the arm scored 0 steps until both were set.
	m._can_input = true
	m._phase = TitleScript.Phase.MENU
	# ⛔ APPEND, never assign: menu_items is Array[Dictionary], and assigning an untyped Array
	# literal is a SCRIPT ERROR that ABORTS the function — CLAUDE.md's typed-array trap. My first
	# version did exactly that and the arm asserted nothing; run_tests.sh's EC=4 named it rather
	# than letting it score as a pass.
	m.menu_items.clear()
	for label in ["Continue", "New Game", "Settings"]:
		m.menu_items.append({"label": label, "enabled": true})
	m.selected_index = 0
	_push(m, "ui_down", JOY_AXIS_LEFT_Y, 1.0)
	assert_eq(m.selected_index, 1,
		"one push is one row — a ramp used to carry the cursor past every enabled option")
