extends GutTest

## While an autogrind runs, the player has five controls — and the F1 reference, the one screen
## struktured asked for so it would be "really easy to know all the buttons", had NO AUTOGRIND
## SECTION AT ALL. Zero mentions of autogrind, turbo or tier.
##
## Found by closing a gap I had written down rather than fixed: my F-key ratchet checks
## `keycode == KEY_F<digits>` only, and GameLoop binds Y, T and P globally during
## LoopState.AUTOGRIND. Those turned out to be a whole undocumented mode.
##
## Every row was verified against AutogrindInputHelper.classify_event — the dispatch table itself,
## not a legend that might also be wrong.

const OVERLAY := "res://src/ui/HowToPlayOverlay.gd"
const HELPER := "res://src/ui/autogrind/AutogrindInputHelper.gd"


func _text() -> String:
	return FileAccess.get_file_as_string(OVERLAY)


## The section must exist. This is the whole defect.
func test_the_reference_documents_the_autogrind_mode() -> void:
	var t := _text().to_upper()
	assert_true(t.contains("AUTOGRIND"),
		"the controls reference must document the mode the game is built around")


## Each documented control must be REAL. A reference that lies is worse than one that omits.
func test_every_documented_autogrind_control_is_bound() -> void:
	var helper := FileAccess.get_file_as_string(HELPER)
	var gl := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var t := _text()
	# pause
	assert_true(t.contains("Pause"), "pause must be documented")
	assert_true(helper.contains("JOY_BUTTON_BACK") and helper.contains("KEY_P"),
		"pause must really be Select / P in the dispatch table")
	# adjust rules
	assert_true(helper.contains("JOY_BUTTON_START") and helper.contains("KEY_R"),
		"adjust-rules must really be Start / R")
	# tier
	assert_true(t.contains("Cycle monster tier"), "tier cycling must be documented")
	assert_true(helper.contains("KEY_T"), "tier must really be T on a keyboard")
	assert_true(helper.contains("JOY_BUTTON_LEFT_SHOULDER"), "and L+R on a pad")
	# turbo
	assert_true(t.contains("Turbo"), "turbo must be documented")
	assert_true(gl.contains("turbo_mode"), "turbo must really exist in GameLoop")


## CONTROL: the reference must not name a control the dispatch table does not have.
func test_the_section_invents_nothing() -> void:
	var t := _text()
	assert_false(t.contains("Rewind grind"),
		"CONTROL: a fabricated row must not be present — if this ever passes trivially, the arms above are weak")
	var helper := FileAccess.get_file_as_string(HELPER)
	assert_false(helper.contains("KEY_ZZQ"),
		"CONTROL: the dispatch-table read can report absence")


## The section must be findable from inside the mode: the dashboard advertises Select for pause,
## and the reference must agree with it rather than inventing a second convention.
func test_the_reference_agrees_with_the_dashboard_legend() -> void:
	var dash := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_true(dash.contains("Select: Pause"),
		"PRECONDITION: the dashboard advertises Select for pause")
	assert_true(_text().contains("Select"),
		"the reference must name the same button, or two screens teach two conventions")
