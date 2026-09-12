extends GutTest

## A pad-only player could remap themselves into a Controls screen they cannot leave — on the one
## screen they would have to be standing on to undo it.
##
## ⛔ THE CHAIN, each link measured rather than reasoned:
##   1. the capture flow accepts ANY button for any remappable action
##   2. detect_conflicts() DISPLAYS the collision and nothing refuses it
##   3. ControlsMenu._input checks ui_accept BEFORE ui_cancel in an elif chain
##   -> bind Cancel onto Confirm's button and the shared press fires Confirm; the screen never closes
##
## Measured before the fix, with a positive control so "did not close" could not be confused with
## "the probe never saw a close":
##   stock cancel (button 0)          closed = TRUE   <- the probe CAN report a close
##   after remapping cancel onto 1    closed = FALSE  <- the trap
##
## Keyboard X/Escape still worked, which is precisely the consolation a couch player does not have.
##
## 🔑 WHY THIS ONE CONFLICT AND NOT THE OTHERS. Every other collision is survivable and stays the
## player's business — the conflict readout exists to inform, not to forbid, and a guard that
## refused them all would be the allowlist-on-day-one shape. This pair is different because it
## removes the only way to undo itself. The refusal is therefore narrow BY NAME, not a general
## conflict veto, and the arm below pins that narrowness in both directions.

const CONTROLS_MENU := "res://src/ui/ControlsMenu.gd"


func _ipm():
	return InputProfileManager


func before_each() -> void:
	_ipm().apply_profile("Standard")


func after_each() -> void:
	_ipm().apply_profile("Standard")


## Press one pad button on a fresh Controls screen; did it close?
func _closes_on(button_index: int) -> bool:
	var cm = load(CONTROLS_MENU).new()
	add_child_autofree(cm)
	var closed := {"v": false}
	cm.closed.connect(func(): closed["v"] = true)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index
	ev.pressed = true
	cm._input(ev)
	return closed["v"]


## ⛔ THE DEFECT, behavioural. Attempt the trapping remap; the way out must survive it.
func test_the_controls_screen_can_always_be_closed_on_a_pad() -> void:
	var accept_btn: int = int(_ipm().PROFILE_STANDARD["ui_accept"][0])
	var cancel_btn: int = int(_ipm().PROFILE_STANDARD["ui_cancel"][0])
	assert_ne(accept_btn, cancel_btn, "precondition: stock Confirm and Cancel are different buttons")

	# CONTROL FIRST: the probe must be able to report a close, or every assert below is vacuous.
	assert_true(_closes_on(cancel_btn),
		"CONTROL: the stock Cancel button must close the Controls screen — if this fails the probe " +
		"cannot see a close and the trap arm proves nothing")

	_ipm().set_custom_binding("ui_cancel", [accept_btn])
	var bound: Array = _ipm().get_current_button_indices("ui_cancel")
	assert_false(bound.has(accept_btn),
		"binding Cancel onto Confirm's button must be REFUSED — it makes the Controls screen " +
		"inescapable on a pad, and that screen is where a player would be when they did it")
	assert_true(_closes_on(cancel_btn),
		"…and the way out must still work afterwards: Cancel stays on its own button")


## The refusal names the reason, because a bind that silently does nothing is its own defect.
func test_the_refusal_says_why() -> void:
	var accept_btn: int = int(_ipm().PROFILE_STANDARD["ui_accept"][0])
	var verdict: Dictionary = _ipm().binding_would_trap_the_player("ui_cancel", [accept_btn])
	assert_true(verdict.get("trapped", false), "the trapping pair must be recognised")
	var reason: String = str(verdict.get("reason", ""))
	assert_gt(reason.length(), 30, "the reason must be a sentence, not a flag: '%s'" % reason)
	for needle in ["Cancel", "Confirm"]:
		assert_true(reason.find(needle) > -1,
			"the reason must name both actions so the player knows what collided, got: %s" % reason)


## ⛔ NARROWNESS, pinned in BOTH directions. This must not become a general conflict veto: every
## other collision is the player's business and the readout exists to inform, not forbid.
func test_only_the_confirm_cancel_pair_is_refused() -> void:
	var accept_btn: int = int(_ipm().PROFILE_STANDARD["ui_accept"][0])
	var defer_btn: int = int(_ipm().PROFILE_STANDARD["battle_defer"][0])

	# REFUSED: the pair that removes the way out, in both orders.
	assert_true(_ipm().binding_would_trap_the_player("ui_cancel", [accept_btn]).get("trapped", false),
		"Cancel onto Confirm's button must be refused")
	var cancel_btn: int = int(_ipm().PROFILE_STANDARD["ui_cancel"][0])
	assert_true(_ipm().binding_would_trap_the_player("ui_accept", [cancel_btn]).get("trapped", false),
		"…and Confirm onto Cancel's button, which is the same trap approached from the other side")

	# ALLOWED: every other collision, including ones that genuinely conflict.
	assert_false(_ipm().binding_would_trap_the_player("battle_defer", [accept_btn]).get("trapped", false),
		"Defer sharing Confirm's button is a conflict the readout reports and the player may want — " +
		"it does not remove the way out, so it must NOT be refused")
	assert_false(_ipm().binding_would_trap_the_player("ui_cancel", [defer_btn]).get("trapped", false),
		"and Cancel onto an unrelated button is an ordinary rebind")


## The collision is still REPORTED even though it is refused — the readout is how a player learns
## that two things collide at all, and silence would be a worse failure than the refusal.
func test_ordinary_conflicts_are_still_detected_and_shown() -> void:
	var accept_btn: int = int(_ipm().PROFILE_STANDARD["ui_accept"][0])
	_ipm().set_custom_binding("battle_defer", [accept_btn])
	var conflicts: Array = _ipm().detect_conflicts()
	assert_gt(conflicts.size(), 0,
		"a real collision must still be DETECTED — refusing the trap pair must not have turned the " +
		"conflict readout off for everything else")
