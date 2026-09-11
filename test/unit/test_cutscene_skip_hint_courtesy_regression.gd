extends GutTest

## The "Hold Ⓑ to skip" prompt appeared only while B was ALREADY held, so a player who did not
## know the gesture never saw it — while the credits roll shows its skip hint permanently. Every
## scene now shows the prompt faintly for its first SKIP_HINT_SEC seconds, fading over the last
## SKIP_HINT_FADE_SEC, with the bar at zero. A real hold takes over at full alpha exactly as
## before; the hint never counts toward the skip and is dropped the moment the player holds B.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	Input.action_release("ui_cancel")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._active = true
	_d._skipping = false
	_d._battle_in_flight = false
	_d._skip_hold_time = 0.0
	_d._skip_hint_left = DirectorScript.SKIP_HINT_SEC


func after_each() -> void:
	Input.action_release("ui_cancel")
	if _d and is_instance_valid(_d):
		_d._active = false


func test_the_hint_shows_faintly_at_scene_start_with_no_bar() -> void:
	_d._process(0.1)
	assert_true(_d._skip_indicator.visible, "the prompt is on screen without any hold")
	assert_eq(_d._skip_bar.size.x, 0.0, "no progress bar — nothing is being held")
	assert_lt(_d._skip_indicator.modulate.a, 1.0, "faint, not the full-alpha hold presentation")
	assert_gt(_d._skip_indicator.modulate.a, 0.0)


func test_the_hint_fades_and_is_gone_after_its_window() -> void:
	_d._process(DirectorScript.SKIP_HINT_SEC - DirectorScript.SKIP_HINT_FADE_SEC * 0.5)
	var mid_fade: float = _d._skip_indicator.modulate.a
	assert_true(_d._skip_indicator.visible, "control: still visible inside the fade")
	assert_lt(mid_fade, DirectorScript.SKIP_HINT_ALPHA, "fading: below the resting alpha")
	_d._process(DirectorScript.SKIP_HINT_FADE_SEC)
	assert_false(_d._skip_indicator.visible, "gone once the window elapses")
	assert_false(_d._skipping, "the hint never counted as a skip")
	assert_eq(_d._skip_hold_time, 0.0)


func test_a_real_hold_takes_over_at_full_alpha_and_still_skips() -> void:
	# ARM+: the hint must not have replaced the hold.
	_d._process(0.5)
	Input.action_press("ui_cancel")
	_d._process(0.5)
	assert_eq(_d._skip_indicator.modulate.a, 1.0, "holding B shows the prompt at full alpha")
	assert_gt(_d._skip_bar.size.x, 0.0, "and the bar fills")
	assert_eq(_d._skip_hint_left, 0.0, "the courtesy window is over once the player has found the gesture")
	_d._process(1.5)
	assert_true(_d._skipping, "1.5s of held B still skips")


func test_after_the_hold_is_released_the_hint_does_not_come_back() -> void:
	Input.action_press("ui_cancel")
	_d._process(0.2)
	Input.action_release("ui_cancel")
	_d._process(0.1)
	assert_false(_d._skip_indicator.visible, "released before a skip: the prompt hides as before, no lingering hint")


func test_every_scene_starts_a_fresh_hint_window() -> void:
	_d._skip_hint_left = 0.0
	_d._active = false
	var runner := func() -> void:
		await _d.play_cutscene_from_data("t", {"id": "t", "world": 1, "keep_music": true, "steps": [{"type": "wait", "duration": 0.05}]})
	runner.call()
	assert_eq(_d._skip_hint_left, DirectorScript.SKIP_HINT_SEC, "entry resets the window")
	var frames := 0
	while _d._active and frames < 120:
		await get_tree().process_frame
		frames += 1
