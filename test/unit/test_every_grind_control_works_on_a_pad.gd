extends GutTest

## CLAUDE.md principle 6 is "Controller-first design — everything works on gamepad". The live
## AUTOGRIND branch broke it for exactly one control:
##
##     exit       ui_cancel                keyboard + pad
##     turbo      KEY_Y / JOY_BUTTON_Y     keyboard + pad
##     dashboard  KEY_T / L+R              keyboard + pad
##     pause      KEY_P / battle_toggle_auto   keyboard + pad
##     rules      KEY_R                    ⛔ KEYBOARD ONLY — a pad player could not reach it
##
## ⛔ AND THE KEYBOARD HALF OF THAT CONTROL WAS ADDED DELIBERATELY. Its own comment reads "the
## dashboard surface binds this through AutogrindInputHelper; without it here the control works on
## one tier and not the next" — so somebody found the tier asymmetry, fixed the keyboard, and the
## pad stayed broken on both tiers. A fix that closes one device's gap reads as closing the gap.
##
## 🔑 THIS ARM IS DERIVED, NOT A LINE PIN. Asserting "JOY_BUTTON_START appears in GameLoop" would
## pass on a binding added anywhere in the file and would never notice the NEXT keyboard-only
## control. It walks the branch, groups dispatch sites by the handler they call, and requires both
## devices per handler — so a new control arrives covered or reds.

const GAMELOOP := "res://src/GameLoop.gd"

## The branch runs from the LoopState.AUTOGRIND guard to the next same-indent statement after it.
const BRANCH_OPEN := "if current_state == LoopState.AUTOGRIND:"

## What each control ultimately calls. Derived membership would be circular here — this names the
## SUBJECTS, and the arms below derive the devices for each from source.
const CONTROL_HANDLERS := {
	"exit": "_stop_autogrind(",
	"turbo": "turbo_mode = not",
	"rules": "_on_dashboard_adjust_rules(",
	"dashboard": "cycle_tier(",
	"pause": "_toggle_autogrind_pause(",
}


func _branch_source() -> String:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of(GAMELOOP)
	assert_ne(code, "", "CONTROL: GameLoop source must survive the comment strip")
	var i: int = code.find(BRANCH_OPEN)
	if i < 0:
		return ""
	var rest: String = code.substr(i + BRANCH_OPEN.length())
	# The branch body is indented deeper than the guard; the first line back at the guard's own
	# depth ends it. Anything shallower belongs to a later state.
	var out := ""
	for line in rest.split("\n"):
		if line.strip_edges() != "" and not line.begins_with("\t\t"):
			break
		out += line + "\n"
	return out


## A dispatch site is a conditional that reaches one of the handlers. Classify each by device.
func _devices_for(branch: String, handler: String) -> Dictionary:
	var has := {"key": false, "pad": false}
	var lines: Array = branch.split("\n")
	for i in range(lines.size()):
		if not str(lines[i]).contains(handler):
			continue
		# Walk back to the nearest condition guarding this call.
		for j in range(i, maxi(-1, i - 6), -1):
			var l: String = str(lines[j])
			if l.contains("InputEventKey") or l.contains("event.keycode"):
				has["key"] = true
				break
			if l.contains("InputEventJoypadButton") or l.contains("JOY_BUTTON") \
					or l.contains("is_joy_button_pressed"):
				has["pad"] = true
				break
			# An ACTION covers both devices at once — ui_cancel is bound on keyboard and pad.
			if l.contains("is_action_pressed("):
				has["key"] = true
				has["pad"] = true
				break
	return has


func test_the_branch_is_found() -> void:
	var b := _branch_source()
	assert_ne(b, "", "CONTROL: the AUTOGRIND branch must be locatable, or every arm below is vacuous")
	assert_gt(b.length(), 400, "CONTROL: the extracted branch is too short to contain five controls")


## ANTI-VACUITY: the extractor must actually see every control, or a missing one reads as covered.
func test_every_control_is_present_in_the_branch() -> void:
	var b := _branch_source()
	for name in CONTROL_HANDLERS:
		assert_true(b.contains(str(CONTROL_HANDLERS[name])),
			"CONTROL: '%s' is not dispatched in the branch this arm reads — either it moved or the "
			% name + "extractor is wrong, and both make the parity arm below vacuous")


func test_every_grind_control_is_reachable_on_a_pad() -> void:
	var b := _branch_source()
	var keyboard_only: Array = []
	for name in CONTROL_HANDLERS:
		var d := _devices_for(b, str(CONTROL_HANDLERS[name]))
		if d["key"] and not d["pad"]:
			keyboard_only.append(name)
	# assert_true, not assert_eq: GUT prints an array comparison INSTEAD of the message, so both
	# direction arms failed with the identical text "ARRAY([\"rules\"]) != ARRAY([])" and nothing on
	# screen said which device was missing.
	assert_true(keyboard_only.is_empty(),
		"KEYBOARD-ONLY grind controls — a player grinding with a controller cannot reach them at "
		+ "all: %s" % [keyboard_only])


## The other direction, which nobody would think to check: a control reachable ONLY on a pad is
## just as broken for the keyboard player the F1 reference advertises keys to.
func test_every_grind_control_is_reachable_on_a_keyboard() -> void:
	var b := _branch_source()
	var pad_only: Array = []
	for name in CONTROL_HANDLERS:
		var d := _devices_for(b, str(CONTROL_HANDLERS[name]))
		if d["pad"] and not d["key"]:
			pad_only.append(name)
	assert_true(pad_only.is_empty(),
		"PAD-ONLY grind controls — the F1 reference advertises a key for these: %s" % [pad_only])


## The F1 reference's pad cell for this row was REFERENCE_PAD_NONE while the control was
## keyboard-only. A declaration may not outlive its fact.
func test_the_reference_advertises_the_pad_cell_it_now_has() -> void:
	var rows: String = AutogrindInputHelper.grind_reference_rows("Xbox Wireless Controller")
	assert_ne(rows, "", "CONTROL: the reference must render for a named pad")
	for line in rows.split("\n"):
		if line.contains("Adjust rules"):
			assert_false(line.begins_with(AutogrindInputHelper.REFERENCE_PAD_NONE),
				"the rules row still advertises no pad cell, but the branch now binds one: %s" % line)
			return
	assert_true(false, "CONTROL: no 'Adjust rules' row found in the reference")
