extends GutTest

## Regression: cutscene start_timer / stop_timer step types are dispatched
## and render a HUD countdown. Per cowir-story spec (forwarded by
## cowir-main): atmospheric only, NEVER a fail state. W4 orrery's 300s
## timer ticks down visibly during ~10 lines of dialogue, stop_timer
## fires well before reaching 0. Pre-fix these step types were silently
## dropped by _execute_step's match.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


const _TOUCHED_FLAGS := [
	"timer_active_world4_orrery_timer",
	"timer_active_test_timer_flag",
]


func before_each() -> void:
	if GameState:
		for f in _TOUCHED_FLAGS:
			GameState.game_constants.erase(f)


func after_each() -> void:
	if GameState:
		for f in _TOUCHED_FLAGS:
			GameState.game_constants.erase(f)


func test_dispatch_handles_start_and_stop_timer() -> void:
	var text = _read(DIRECTOR_PATH)
	var match_idx = text.find("func _execute_step")
	var fn_end = text.find("\n\nfunc ", match_idx)
	var body = text.substr(match_idx, fn_end - match_idx) if fn_end > -1 else text.substr(match_idx, 1500)
	assert_true(body.find("\"start_timer\":") > -1,
		"_execute_step match must include start_timer case")
	assert_true(body.find("\"stop_timer\":") > -1,
		"_execute_step match must include stop_timer case")


func test_start_timer_renders_hud_and_sets_flag() -> void:
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)

	d._step_start_timer({
		"type": "start_timer",
		"duration": 300,
		"flag": "world4_orrery_timer",
	})

	# Label must be present and named CutsceneTimerHUD for the test +
	# other systems to locate it.
	var label = d.get_node_or_null("CutsceneTimerHUD")
	assert_not_null(label, "start_timer must create a CutsceneTimerHUD child label")
	if label:
		assert_eq((label as Label).text, "5:00",
			"Initial label text for 300s timer must be '5:00' (M:SS format)")

	# Flag bookkeeping so other systems can probe whether timer is active.
	if GameState:
		assert_true(GameState.game_constants.get("timer_active_world4_orrery_timer", false),
			"start_timer must set timer_active_<flag> = true in game_constants")


func test_stop_timer_clears_hud_and_resets_flag() -> void:
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	d._step_start_timer({"type": "start_timer", "duration": 60, "flag": "test_timer_flag"})

	# Confirm setup state
	assert_not_null(d.get_node_or_null("CutsceneTimerHUD"))

	d._step_stop_timer({"type": "stop_timer", "flag": "test_timer_flag"})

	# Label must be freed (or queue_freed — may need a frame)
	assert_eq(d._timer_label, null,
		"stop_timer must clear _timer_label reference")
	if GameState:
		assert_false(GameState.game_constants.get("timer_active_test_timer_flag", false),
			"stop_timer must set timer_active_<flag> = false")


func test_stop_timer_is_idempotent_when_no_timer_active() -> void:
	# Defensive: stop_timer fired without a matching start_timer must not
	# crash. Pairs with the _end_cutscene defensive cleanup that calls
	# _clear_timer_hud regardless of state.
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	d._step_stop_timer({"type": "stop_timer"})  # no flag, no active timer
	assert_eq(d._timer_label, null,
		"_timer_label must stay null after stop_timer with no active timer")


func test_format_timer_text_pads_seconds() -> void:
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	# Spot-check the format helper. M:SS with leading zero on seconds.
	assert_eq(d._format_timer_text(300.0), "5:00", "300s = '5:00'")
	assert_eq(d._format_timer_text(65.0), "1:05", "65s = '1:05' (leading zero on seconds)")
	assert_eq(d._format_timer_text(9.0), "0:09", "9s = '0:09'")
	assert_eq(d._format_timer_text(0.0), "0:00", "0s = '0:00' (floor display)")
	assert_eq(d._format_timer_text(-5.0), "0:00", "Negative seconds floors to '0:00' (never a fail state)")


func test_start_timer_rejects_non_positive_duration() -> void:
	# Defensive: start_timer with duration<=0 must push_warning and skip.
	# A 0-duration timer would render "0:00" forever which is confusing.
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	d._step_start_timer({"type": "start_timer", "duration": 0})
	assert_eq(d._timer_label, null,
		"start_timer with duration=0 must skip — no HUD rendered")
	d._step_start_timer({"type": "start_timer", "duration": -5})
	assert_eq(d._timer_label, null,
		"start_timer with negative duration must skip")
