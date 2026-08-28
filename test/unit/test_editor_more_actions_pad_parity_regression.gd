extends GutTest

## struktured 2026-08-26: "focus on better controller situation acreoss the board its a
## blocker for demoing it to ppl who arent me at this point."
##
## MEASURED before building: the editor's legend advertises 11 verbs; a pad could reach 2.
## The other nine were raw `keycode == KEY_*` branches with no InputMap action, so export,
## import, copy/paste share code, compose, per-row toggle, profile cycle and rename were
## keyboard-only — in the screen the game calls its design pillar.
##
## There was no button left to bind (Y taken, R3 spent on the help overlay, Guide untouchable),
## so this is a submenu reached by D-pad LEFT from the portrait panel — which was a dead end
## playing menu_error, and which is this game's documented "enter submenu" gesture.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _editor: Node = null


func before_each() -> void:
	_editor = load(ED).new()
	add_child_autofree(_editor)
	_editor.setup("hero", "Hero")
	await get_tree().process_frame


func _press(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


## Behavioural: drive the real editor into portrait focus and press left. A source pin here
## would pass on a handler that is present and dead — the exact hollowness that bit me on the
## right-click claim in this same file earlier today.
func test_left_from_the_portrait_opens_more_actions() -> void:
	_editor._portrait_focused = true
	assert_null(_editor._option_picker, "precondition: no picker open")
	_editor._input(_press("ui_left"))
	assert_not_null(_editor._option_picker, "D-pad left from the portrait must open a submenu")
	var spec: Dictionary = _editor._option_picker.get_meta("spec")
	assert_eq(str(spec.get("kind", "")), "more_actions", "and it must be the More Actions list")
	assert_gt((spec.get("options", []) as Array).size(), 4,
		"a submenu with fewer than five entries is not carrying the nine keyboard-only verbs")


## CONTROL. Without this, "a picker opened" could pass on an editor that opens one for any
## input, which would be a worse bug than the one being fixed.
func test_left_in_the_GRID_does_not_open_more_actions() -> void:
	_editor._portrait_focused = false
	_editor._input(_press("ui_left"))
	# Unconditional: an `if opened:` guard here asserts NOTHING on the good path, which GUT
	# scores [Risky] and which is the same hollowness this file exists to avoid.
	var kind := ""
	if _editor._option_picker != null and is_instance_valid(_editor._option_picker):
		kind = str((_editor._option_picker.get_meta("spec") as Dictionary).get("kind", ""))
	assert_ne(kind, "more_actions", "left in the grid is cursor movement, not the submenu")


## Enumerate from the OTHER side: every id the menu offers must reach a method that exists.
## A renamed handler leaves the menu rendering perfectly and doing nothing — silent by
## construction, and no amount of driving the UI would surface it.
func test_every_offered_action_dispatches_to_a_real_handler() -> void:
	_editor._portrait_focused = true
	_editor._input(_press("ui_left"))
	var spec: Dictionary = _editor._option_picker.get_meta("spec")
	var src := FileAccess.get_file_as_string(ED)
	var commit_at := src.find("func _commit_more_action")
	assert_gt(commit_at, -1, "the dispatcher must exist")
	var commit_body := src.substr(commit_at, src.find("\nfunc ", commit_at + 10) - commit_at)
	var checked := 0
	for opt in (spec.get("options", []) as Array):
		var id := str(opt.get("id", ""))
		assert_true(commit_body.contains('"%s"' % id),
			"offered id '%s' has no arm in _commit_more_action — the row would do nothing" % id)
		checked += 1
	assert_gt(checked, 4, "the walk must actually inspect rows, got %d" % checked)
	# and every handler the dispatcher names is really defined on this class
	for m in ["_toggle_row_enabled", "_copy_share_code", "_paste_share_code", "_export_script",
			"_open_share_picker", "_open_rule_composer_overlay", "_cycle_profile", "_open_rename_profile"]:
		assert_true(_editor.has_method(m), "dispatcher targets %s, which must exist on the editor" % m)
	assert_false(_editor.has_method("_zz_not_a_real_handler"),
		"CONTROL: has_method must be able to say NO, else the loop above proves nothing")


## The keyboard route must survive — this adds a pad path, it does not replace anything.
func test_the_keyboard_bindings_are_untouched() -> void:
	var src := FileAccess.get_file_as_string(ED)
	for key in ["KEY_TAB", "KEY_E", "KEY_I", "KEY_K", "KEY_R"]:
		assert_true(src.contains("keycode == %s" % key),
			"%s must still work — a keyboard player loses nothing here" % key)
