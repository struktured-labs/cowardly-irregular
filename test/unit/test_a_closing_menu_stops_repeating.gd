extends GutTest

## ⛔ A MENU CLOSED MID-HOLD KEPT REPEATING FOR ONE MORE FRAME. None of these menus hide before
## `queue_free()`, so the node stays `visible` and queued until the end of the frame — and
## MenuRepeat POLLS Input, so a ramped hold steps the cursor and rebuilds the UI on a dying node.
##
## 🔑 Found by diffing the holders: AutobattleGridEditor's blocker guards `is_queued_for_deletion()`
## and four others checked only `visible`. Same sibling divergence as the scroll and the chord.
##
## ⚠️ ONE FRAME, NOT A CRASH — stated plainly rather than dressed up. The window is the tail of a
## close, and the visible effect is a last cursor step plus a wasted `_build_ui()` on a node about
## to be freed. It is a correctness gap and defence in depth, not a reported symptom.

const KeyboardScript := preload("res://src/ui/VirtualKeyboard.gd")
const PAST_DELAY := 0.5


func after_each() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")


func _held_steps(kb: Node, ticks: int) -> int:
	var before: int = int(kb.get("cursor_row"))
	Input.action_press("ui_down", 1.0)
	for i in range(ticks):
		kb._process(PAST_DELAY)
	Input.action_release("ui_down")
	return int(kb.get("cursor_row")) - before


func _keyboard() -> Node:
	var kb: Node = KeyboardScript.new()
	add_child_autofree(kb)
	kb.visible = true
	kb.set("cursor_row", 0)
	kb.set("cursor_col", 0)
	return kb


## CONTROL: the hold must move the cursor while the menu is alive, or the arm below passes because
## nothing was repeating in the first place.
func test_a_live_menu_repeats() -> void:
	var kb := _keyboard()
	assert_ne(_held_steps(kb, 3), 0,
		"CONTROL: a held direction must step a LIVE keyboard, or the closing arm proves nothing")


func test_a_closing_menu_does_not_repeat() -> void:
	var kb := _keyboard()
	# Ramp the hold first: an un-ramped repeat would not fire regardless, which is the vacuous pass.
	Input.action_press("ui_down", 1.0)
	kb._process(PAST_DELAY)
	kb._process(PAST_DELAY)
	Input.action_release("ui_down")
	assert_true(kb.is_queued_for_deletion() == false, "CONTROL: not queued yet")

	kb.queue_free()
	assert_true(kb.is_queued_for_deletion(),
		"CONTROL: queue_free must mark the node, or this arm tests nothing")
	var moved := _held_steps(kb, 3)
	assert_eq(moved, 0,
		"a menu closed mid-hold stepped its cursor %d more times on a dying node" % moved)


## ⛔ RATCHET: every MenuRepeat holder's hold path must refuse BOTH a hidden menu and a closing one.
## The visible check alone was the divergence; four of ten holders had only that.
func test_every_hold_path_refuses_a_closing_menu() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var missing: Array = []
	var scanned := 0
	for path in _gd_files("res://src"):
		var code: String = GdSource.code_of(path)
		if not code.contains("MenuRepeat.new("):
			continue
		scanned += 1
		# the guard may live in _process or in a named blocker it consults
		if not code.contains("is_queued_for_deletion()"):
			missing.append(path.get_file())
	assert_gt(scanned, 5, "CONTROL: the scan must find the holders, or this arm is vacuous")
	assert_true(missing.is_empty(),
		"these poll a held direction and never ask whether the menu is closing, so a hold that "
		+ "outlives a queue_free() steps a dying node: %s" % [missing])


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
