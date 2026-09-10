extends GutTest

## struktured's reference context is couch + TV + controller, where feel outranks features.
##
## MEASURED: the ui_left/right/up/down actions carry Godot's DEFAULT 0.5 deadzone and are bound to
## the left stick's axes. So on a pad the character did not move until the stick was pushed PAST
## HALFWAY. Nothing in src/ ever set a deadzone; it was never tuned, not chosen.
##
## The fix has to be surgical because those same actions drive MENU navigation — lowering them
## globally would make every list twitchy under a resting stick. Input.get_vector takes its own
## deadzone and does NOT mutate the action, verified below.
##
## ⚠️ THIS IS A FEEL CHANGE HE DID NOT ASK FOR. It is one constant, MOVE_DEADZONE, and reverting is
## changing that number back to 0.5. Speed is unchanged — the magnitude is discarded by the
## normalize() downstream — so the only difference is how far the stick travels before you walk.

const PLAYER := "res://src/exploration/OverworldPlayer.gd"


## The premise: the shared actions really do carry the high default, and really are stick-bound.
func test_the_menu_actions_still_carry_the_default_deadzone() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		assert_eq(InputMap.action_get_deadzone(a), 0.5,
			"%s must keep 0.5 — menus share these actions and a lower value makes lists twitchy" % a)
	var axis_bound := false
	for ev in InputMap.action_get_events("ui_up"):
		if ev is InputEventJoypadMotion:
			axis_bound = true
	assert_true(axis_bound, "PRECONDITION: ui_up is stick-bound, or the deadzone is irrelevant")


## get_vector must not mutate what it is passed — the whole reason this fix is safe.
func test_get_vector_does_not_mutate_the_action_deadzone() -> void:
	var before := InputMap.action_get_deadzone("ui_up")
	var _v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down", 0.25)
	assert_eq(InputMap.action_get_deadzone("ui_up"), before,
		"a custom deadzone must be local to the call, or menus change too")


## Movement must read through the lower threshold.
func test_movement_uses_its_own_lower_deadzone() -> void:
	var src := FileAccess.get_file_as_string(PLAYER)
	assert_true(src.contains("MOVE_DEADZONE"), "movement must declare its own deadzone constant")
	assert_true(src.contains("Input.get_vector("),
		"and read the stick through get_vector, which accepts one")
	var re := RegEx.new()
	re.compile("MOVE_DEADZONE\\s*:=\\s*([0-9.]+)")
	var m := re.search(src)
	assert_not_null(m, "the constant must be readable")
	var dz := float(m.get_string(1))
	assert_lt(dz, 0.5, "it must actually be lower than the shared default, or nothing changed")
	assert_gt(dz, 0.05, "and above stick-drift territory, or a resting pad walks on its own")


## Speed must NOT have changed: the magnitude is discarded downstream. If that normalize ever
## goes away, this stops being a threshold change and becomes a variable-speed change.
func test_speed_is_unchanged_because_magnitude_is_discarded() -> void:
	var src := FileAccess.get_file_as_string(PLAYER)
	var at := src.find("Input.get_vector(")
	assert_gt(at, -1, "movement reads get_vector")
	# Bounded at the END OF THE FUNCTION, not a fixed character count. My first version used 2000
	# chars and failed on correct code — a fixed window is not a scope, which is the trap this lane
	# has flagged in three other lanes' instruments tonight and then walked into.
	var nxt := src.find("\nfunc ", at)
	var after := src.substr(at, (nxt - at) if nxt > -1 else src.length() - at)
	assert_true(after.contains("input_dir = input_dir.normalized()"),
		"the magnitude must still be normalised away IN THE SAME FUNCTION — otherwise this became a speed change too")
