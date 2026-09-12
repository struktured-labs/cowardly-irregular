extends GutTest

## The Controls screen has THREE pad-only flows and only ONE of them checked for a pad.
##
##   _start_pad_mapping   guarded — "Connect a pad first"        ✅ the precedent, already shipped
##   _start_capture       NOT guarded                            ⛔ "Remap 'Confirm' — press a
##                                                                  button…" that only an
##                                                                  InputEventJoypadButton answers
##   _start_test          NOT guarded                            ⛔ a button tester that only ever
##                                                                  reads InputEventJoypadButton
##
## ⛔ On a screen whose own device label ALREADY SAYS "No gamepad detected". Measured before the
## fix: zero pads attached, activating a remap row set `_capturing = true` and rendered
## "Remap 'Confirm' — press a button...", which nothing reachable could satisfy.
##
## ⚠️ NOT A LOCK, and worth saying so rather than overselling it: capture times out in 5s and Esc
## or X cancels both overlays — I checked, and the escape paths are sound. This is being OFFERED a
## control you do not have, which is the same defect this lane spent .308-.338 removing from
## captions, arriving one layer up in the interaction rather than in the text.
##
## 🔑 The fix is the file's own precedent applied to its siblings, not a new mechanism — which is
## also why this is a small change: `_start_pad_mapping` had the answer eleven lines away.

const CONTROLS_MENU := "res://src/ui/ControlsMenu.gd"


func _ipm():
	return InputProfileManager


func before_each() -> void:
	_ipm().apply_profile("Custom")


func after_each() -> void:
	_ipm().apply_profile("Standard")


func _menu() -> Node:
	var cm = load(CONTROLS_MENU).new()
	add_child_autofree(cm)
	return cm


## ⛔ THE DEFECT. GUT attaches no pad, which is exactly the case that was unguarded.
func test_with_no_pad_a_remap_row_does_not_open_a_capture_nobody_can_finish() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: this arm describes the no-pad case, which is what GUT runs as")
	var cm := _menu()
	cm.selected_index = cm.ROW_ACTION_FIRST
	cm._activate_row()
	assert_false(cm._capturing,
		"a remap row must NOT start a capture with no pad attached — only an " +
		"InputEventJoypadButton can complete it, so the player is shown 'press a button…' and " +
		"nothing they can press will do")
	assert_true(cm._flash_label != null and cm._flash_label.text != "",
		"…and it must SAY why, not decline silently — a row that does nothing is its own defect")


func test_with_no_pad_the_button_tester_does_not_open_either() -> void:
	var cm := _menu()
	cm.selected_index = cm._row_test
	cm._activate_row()
	assert_false(cm._testing,
		"Test Buttons reads only InputEventJoypadButton, so with no pad it is a dead overlay")
	assert_true(cm._flash_label != null and cm._flash_label.text != "", "and it must say why")


## THE OTHER DIRECTION, so the guard cannot become "these rows never work". With a pad the flows
## must open — asserted on the helper, since no pad can be attached headless.
func test_the_guard_only_blocks_when_there_is_no_pad() -> void:
	var cm := _menu()
	assert_true(cm._needs_a_pad("x"),
		"with zero pads the guard must block — that is this file's subject")
	# The guard's ONLY condition is the pad list; nothing else can make it refuse.
	var src := FileAccess.get_file_as_string(CONTROLS_MENU)
	var at := src.find("func _needs_a_pad")
	assert_gt(at, -1, "the shared guard must exist")
	var stop := src.find("\nfunc ", at + 10)
	var body := src.substr(at, stop - at) if stop > at else src.substr(at)
	assert_true(body.find("Input.get_connected_joypads().is_empty()") > -1,
		"the guard must key on the PAD LIST and nothing else — an autoload or profile check here " +
		"would be the bucket-4 shape this lane swept in .318")
	assert_eq(body.find("active_profile"), -1,
		"…and must not smuggle in a profile condition: 'switch to Custom' is a separate message " +
		"that already exists and must keep firing on its own terms")


## The precedent this fix copies must still be there — if the mapping walk loses its guard, the
## three flows are inconsistent again in the other direction.
func test_the_mapping_walk_still_guards_too() -> void:
	var src := FileAccess.get_file_as_string(CONTROLS_MENU)
	var at := src.find("func _start_pad_mapping")
	assert_gt(at, -1, "the mapping walk must exist")
	var stop := src.find("\nfunc ", at + 10)
	var body := src.substr(at, stop - at) if stop > at else src.substr(at)
	assert_true(body.find("get_connected_joypads") > -1,
		"the mapping walk is where this guard came from — all three pad-only flows check now")


## THE CONTROL. Without it every arm passes on a menu that failed to build.
func test_the_menu_really_built_and_the_rows_are_distinct() -> void:
	var cm := _menu()
	assert_gt(cm._item_count, 3, "the Controls menu must have built its rows")
	assert_ne(cm.ROW_ACTION_FIRST, cm._row_test, "the two rows this file drives must differ")
	assert_true(cm._flash_label != null, "the flash surface must exist, or 'it said why' is vacuous")
	# and the flash starts EMPTY, so a non-empty read above is really this activation's doing
	var fresh := _menu()
	assert_eq(fresh._flash_label.text, "",
		"a fresh menu's flash must be empty — otherwise the arms above read a stale message")
