extends GutTest

## Paging the 161-row Jukebox with the analog triggers was DEAD in the shipped build and every
## existing guard said it worked.
##
## ⛔ THE ARMS WERE ABOUT THE HELPER; THE DEFECT WAS IN THE CALL SITE. `MenuPaging.page_delta`
## became a CONSUMING read when the analog latch landed, and JukeboxMenu called it TWICE in one
## handler — once as the branch condition, once inside the branch for the direction:
##
##     elif MenuPaging.page_delta(event) != 0:                       <- first read: -1
##         selected_index = clampi(selected_index
##             + MenuPaging.page_delta(event) * MenuPaging.PAGE_ROWS, ...)   <- second read: 0
##
## On a TRIGGER the branch is entered and the cursor moves `0 * PAGE_ROWS`. On a shoulder BUTTON
## both reads return -1, because buttons are deliberately not latched — so the two routes anyone
## tests with kept working while the trigger route did nothing. Found by @cowir-cutscenes, fixed
## by @cowir-controller, who hoisted the read; this arm is the behavioural half from the menu's
## own side.
##
## ⛔ WHY NOTHING CAUGHT IT: measured 2026-09-17, three files mention the Jukebox and a trigger.
## `test_the_jukebox_names_the_key_that_pages_it` pins SOURCE TEXT and then calls
## `MenuPaging.page_delta(ev)` DIRECTLY. `test_one_trigger_pull_is_one_page_regression` drives the
## helper and names the Jukebox only in a comment. `test_menu_paging_coverage_ratchet` counts call
## sites. NOT ONE sends an event through `JukeboxMenu._input` and asks whether the cursor moved —
## so the helper being correct was mistaken for the menu being correct.
##
## The direction is deliberately not asserted: which trigger pages which way is MenuPaging's
## contract and has its own guard. What this arm owns is that ONE pull moves the Jukebox's cursor
## by exactly PAGE_ROWS, which is the part a player notices and the part that was broken.

const JUKEBOX := preload("res://src/ui/JukeboxMenu.gd")
const RAMP := [0.35, 0.55, 0.75, 0.95]


func before_each() -> void:
	JUKEBOX._last_selected = 0
	_release()


func after_each() -> void:
	JUKEBOX._last_selected = 0
	_release()
	SoundManager.stop_music()


## Clear both the engine action state and MenuPaging's static latch through its public seam.
func _release() -> void:
	Input.action_release("battle_defer")
	Input.action_release("battle_advance")
	for axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		MenuPaging.page_delta(_motion(axis, 0.0))


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _open() -> Node:
	var jb: Node = JUKEBOX.new()
	add_child_autofree(jb)
	await get_tree().process_frame
	return jb


## The engine sets the action state from the axis and THEN delivers the event; an arm that only
## calls _input() leaves page_delta's own is_action_pressed poll reading "nothing held".
func _pull(jb: Node, action: String, axis: int) -> void:
	Input.action_press(action, 1.0)
	for v in RAMP:
		jb._input(_motion(axis, v))


func test_one_trigger_pull_moves_the_cursor_one_page() -> void:
	var jb: Node = await _open()
	assert_gt(jb.TRACKS.size(), MenuPaging.PAGE_ROWS * 2,
		"CONTROL: the Jukebox lists %d rows — a page jump has to have somewhere to land" % jb.TRACKS.size())
	var start: int = MenuPaging.PAGE_ROWS * 2
	jb.selected_index = start
	_pull(jb, "battle_advance", JOY_AXIS_TRIGGER_RIGHT)
	assert_eq(absi(jb.selected_index - start), MenuPaging.PAGE_ROWS,
		"one trigger pull moved the cursor %d rows, not %d — the second read of page_delta returns 0 on an axis, so the branch runs and pages nothing" % [absi(jb.selected_index - start), MenuPaging.PAGE_ROWS])


func test_the_other_trigger_pages_the_other_way() -> void:
	var jb: Node = await _open()
	var start: int = MenuPaging.PAGE_ROWS * 2
	jb.selected_index = start
	_pull(jb, "battle_defer", JOY_AXIS_TRIGGER_LEFT)
	assert_eq(absi(jb.selected_index - start), MenuPaging.PAGE_ROWS,
		"the other trigger moved %d rows, not %d" % [absi(jb.selected_index - start), MenuPaging.PAGE_ROWS])


func test_the_shoulder_button_still_pages() -> void:
	## CONTROL, and it is the reason the defect survived: buttons are NOT latched, so both reads
	## return the same value and this route worked throughout. If this ever reds the cause is a
	## different one from the trigger arms above.
	var jb: Node = await _open()
	var start: int = MenuPaging.PAGE_ROWS * 2
	jb.selected_index = start
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_RIGHT_SHOULDER
	e.pressed = true
	Input.action_press("battle_advance", 1.0)
	jb._input(e)
	assert_eq(absi(jb.selected_index - start), MenuPaging.PAGE_ROWS,
		"the shoulder route paged %d rows, not %d — this one was never broken, so a red here is a NEW defect" % [absi(jb.selected_index - start), MenuPaging.PAGE_ROWS])
