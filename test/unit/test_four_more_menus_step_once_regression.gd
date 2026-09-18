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

## ⛔ THIS FILE WRITES SoundManager AND NAMES NONE OF IT. `TitleScript.new()` + `add_child` runs
## TitleScreen's `_ready`, which starts the title theme three frames down — so the file left
## `_music_playing=true` and `_current_music=title` for whatever ran next in the process.
## `_clear()` above covers the Input singleton, which is the state this file is ABOUT, and that is
## exactly why the omission was invisible: the teardown a reader checks is the one for the subject.
## Measured with an entry/exit delta, reproduced in a virgin sandbox.
##
## 📌 Restores the whole list rather than the two fields that moved — the two that moved are the
## ones this file happens to trigger today, and a later menu with an ambient bed would add another.
## Adopt cowir-music's `test/unit/helpers/sound_state.gd` when it reaches main and delete this.
const SM_FIELDS := ["_current_area", "_current_world_suffix", "_music_playing",
	"_current_music", "_current_ambient_key"]

var _saved_sm: Dictionary = {}


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


func before_all() -> void:
	for f in SM_FIELDS:
		_saved_sm[f] = SoundManager.get(f)


## after_ALL, not after_each: the restore is about what the NEXT FILE inherits, and putting it in
## after_each would reset state between this file's own arms for no reason.
func after_all() -> void:
	SoundManager.stop_music()
	for f in SM_FIELDS:
		SoundManager.set(f, _saved_sm[f])


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


## ─────────────────────────────────────────────────────────────────────────────────────────────
## THE HORIZONTAL AXIS. Every conversion before this one was VERTICAL-ONLY — up/down through
## MenuNav, left/right still raw — in six menus, and the ledger policing the migration shared the
## blind spot exactly, because it only ever searched for ui_up/ui_down. @cowir-adhoc found it by
## classifying every .gd rather than trusting the list.
##
## The horizontal half is not cosmetic. On AbilitiesMenu left/right switch TABS, rebuilding the
## whole UI and firing menu_move per event; on BestiaryMenu left cycles the sort mode; on
## Win98Menu they expand and back out of submenus; and on SettingsMenu's QUIT confirmation they
## toggle Yes/No.

## ⛔ NO BEHAVIOURAL ARM FOR THE HORIZONTAL AXIS, and the reason is measured rather than an
## omission: EVERY candidate masks the burst with its own arithmetic, so an arm here would pass
## against the unconverted code and discriminate nothing.
##
##   AbilitiesMenu   left/right clamp at 2 tabs      -> one step from either end, burst or not
##   OverworldMenu   character cycles % party.size() -> 5 steps of a 2-party wrap land on 1
##   BestiaryMenu    re-sorting refills _entries from BestiarySystem, which is EMPTY headless,
##                   so _input's own early return eats events 2..5. PROBED, not assumed:
##                       ev pressed=true x5, sort_idx 0 -> 1 -> 1 -> 1 -> 1
##   Win98Menu       left/right expand submenus; a real battle is a documented headless wall
##
## Two such arms were written, passed against the unconverted code, and are NOT kept — a green
## that cannot go red is worse than no arm, because the next reader counts it as coverage.
##
## What DOES discriminate is the ledger's raw-read scan: it searches all four directions, and
## widening it from two is exactly what surfaced these six half-conversions. The helper's own
## `test_a_held_vertical_does_not_swallow_a_horizontal_step` covers the latch itself.
