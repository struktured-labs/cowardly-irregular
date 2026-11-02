extends GutTest

## Regression tests for ControlsMenu's button-remap capture overlay.
##
## Bug: the capture overlay's container ColorRect ("box") was built with NO
## .name, but _process() and _start_capture() looked its children up via
## get_node_or_null("*/TimerLabel") and get_node_or_null("*/CapturePrompt").
## Godot does NOT support "*" as a wildcard path segment — it is treated as a
## literal node name, so both lookups always returned null. Consequences:
##   (1) during a remap capture the 5s countdown TimerLabel never updated
##       (stuck at its build-time "5.0s"),
##   (2) the CapturePrompt never showed the action-specific
##       "Remap 'X' — press a button..." text (stuck on the generic prompt).
##
## Fix: name the capture box "CaptureBox" and address its children as
## "CaptureBox/TimerLabel" / "CaptureBox/CapturePrompt" (matching the existing
## working pattern for the test overlay's "TestBox/TestResult").

const ControlsMenuScript = preload("res://src/ui/ControlsMenu.gd")

var _saved_time_scale: float = 1.0


func before_each() -> void:
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.time_scale = _saved_time_scale


func _make_menu() -> ControlsMenu:
	var menu = ControlsMenuScript.new()
	menu.size = Vector2(1280, 720)
	add_child_autofree(menu)
	return menu


func test_capture_box_is_named() -> void:
	"""The capture overlay container must be named 'CaptureBox' so its children resolve."""
	var menu = _make_menu()
	var box = menu._capture_overlay.get_node_or_null("CaptureBox")
	assert_not_null(box, "Capture overlay should contain a node named 'CaptureBox'")


func test_capture_overlay_children_resolve_by_path() -> void:
	"""TimerLabel and CapturePrompt must be reachable via the CaptureBox path."""
	var menu = _make_menu()
	var timer_label = menu._capture_overlay.get_node_or_null("CaptureBox/TimerLabel")
	var prompt = menu._capture_overlay.get_node_or_null("CaptureBox/CapturePrompt")
	assert_not_null(timer_label, "CaptureBox/TimerLabel should resolve (was dead via '*/TimerLabel')")
	assert_not_null(prompt, "CaptureBox/CapturePrompt should resolve (was dead via '*/CapturePrompt')")


func test_wildcard_path_is_dead() -> void:
	"""Sanity-check the root cause: a '*/' segment never resolves in Godot."""
	var menu = _make_menu()
	assert_null(menu._capture_overlay.get_node_or_null("*/TimerLabel"),
		"'*/TimerLabel' must NOT resolve — '*' is a literal name, not a wildcard")
	assert_null(menu._capture_overlay.get_node_or_null("*/CapturePrompt"),
		"'*/CapturePrompt' must NOT resolve — '*' is a literal name, not a wildcard")


func test_start_capture_sets_action_specific_prompt() -> void:
	"""_start_capture should update the prompt to the action-specific remap text."""
	var menu = _make_menu()
	# Switch to Custom so remapping is permitted, then capture the first action.
	var action: String = InputProfileManager.REMAPPABLE_ACTIONS[0]
	menu._start_capture(action)
	var prompt = menu._capture_overlay.get_node_or_null("CaptureBox/CapturePrompt")
	assert_not_null(prompt, "Prompt label should exist")
	var label: String = InputProfileManager.ACTION_LABELS.get(action, action)
	assert_eq(prompt.text, "Remap '%s' — press a button..." % label,
		"Prompt should show the action-specific remap text, not the generic build-time text")
	# Clean up capture state so it doesn't leak.
	menu._cancel_capture()


func test_process_updates_countdown_label() -> void:
	"""While capturing, _process should tick the TimerLabel below its build-time value."""
	var menu = _make_menu()
	menu._start_capture(InputProfileManager.REMAPPABLE_ACTIONS[0])
	var timer_label = menu._capture_overlay.get_node_or_null("CaptureBox/TimerLabel")
	assert_not_null(timer_label, "Timer label should exist")
	# Advance the capture countdown by a fixed delta.
	menu._capture_timer = ControlsMenu.CAPTURE_TIMEOUT
	menu._process(0.25)
	assert_eq(timer_label.text, "%.1fs" % (ControlsMenu.CAPTURE_TIMEOUT - 0.25),
		"TimerLabel should reflect the decremented capture countdown, not stay frozen at '5.0s'")
	menu._cancel_capture()


## The countdown is REAL seconds: battle runs Engine.time_scale 0.25 for "1x", which scales _process's
## delta, so an engine-time 5 s capture took 20 s in the player's hand there.
func test_the_capture_countdown_is_real_seconds_under_a_battle_time_scale() -> void:
	var menu = _make_menu()
	menu._start_capture(InputProfileManager.REMAPPABLE_ACTIONS[0])
	assert_true(menu._capturing, "CONTROL: a capture must be live before the clock runs")
	Engine.time_scale = 0.25
	menu._process((ControlsMenu.CAPTURE_TIMEOUT + 0.5) * 0.25)
	assert_false(menu._capturing,
		"at time_scale 0.25 the 5 s capture is a quarter as much ENGINE delta, and must still time out")


## The flash message is read in real seconds too.
func test_a_flash_message_clears_in_real_seconds_under_a_battle_time_scale() -> void:
	var menu = _make_menu()
	menu._show_flash("probe")
	assert_true(menu._flash_label.visible, "CONTROL: the flash must be showing first")
	var shown: float = menu._flash_timer
	Engine.time_scale = 0.25
	menu._process((shown + 0.1) * 0.25)
	assert_false(menu._flash_label.visible,
		"at time_scale 0.25 a real-second flash is a quarter as much ENGINE delta, and must still clear")

