extends GutTest

## The .841 gloat red (story 28465): a SceneTreeTimer armed beside a >1 s frame ends on its FIRST tick, since that tick's
## delta carries the whole frame. The trusted turn's take-back window was such a timer: a hitch just before it (a first
## FX shader compile on web) closed the offer at once and the AI played a turn the player was offered back. It counts
## wall milliseconds now; battle speed and a paused tree still leave the full second (adhoc 28485).

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const LONG_FRAME_MS := 1300

var _guard
var _saved_scale := 1.0


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = _saved_scale
	BattleManager._trust_window_pc = null
	BattleManager._trust_window_deadline_ms = -1
	_guard.restore()


func _pc() -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = "Trusted"
	pc.is_alive = true
	add_child_autofree(pc)
	return pc


## Arms a window: {ms: wall ms to close (-1 never), span: deadline minus arming ms, left: time left one frame later}.
func _window(after_long_frame: bool, frame_between: bool) -> Dictionary:
	var bm = BattleManager
	var pc := _pc()
	bm.current_combatant = null  # the window then closes without handing the turn to the AI
	var closed: Array = []
	var on_close := func(who, _taken) -> void:
		if who == pc:
			closed.append(Time.get_ticks_msec())
	bm.trust_interrupt_window_closed.connect(on_close)
	var out := {"ms": -1, "span": -1, "left": -1.0, "delta": 0.0}
	if after_long_frame:
		OS.delay_msec(LONG_FRAME_MS)
		if frame_between:
			await get_tree().process_frame
			out["delta"] = get_process_delta_time()
	var t0 := Time.get_ticks_msec()
	bm._run_trust_interrupt_window(pc)
	out["span"] = bm._trust_window_deadline_ms - t0
	await get_tree().process_frame
	out["left"] = bm.trust_window_time_left()
	while closed.is_empty() and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	bm.trust_interrupt_window_closed.disconnect(on_close)
	if not closed.is_empty():
		out["ms"] = int(closed[0]) - t0
	return out


func test_a_long_frame_in_the_arming_frame_leaves_the_full_second() -> void:
	var r: Dictionary = await _window(true, false)
	gut.p("same frame: %s" % r)
	assert_gt(float(r["left"]), 0.8, "THE DEFECT: the frame that armed the window ran %d ms, and the offer emptied on its first tick" % LONG_FRAME_MS)
	assert_gte(int(r["ms"]), 950, "the window stayed open for its wall second after a long arming frame (%d ms)" % r["ms"])


func test_a_long_frame_just_before_arming_leaves_the_full_second() -> void:
	var r: Dictionary = await _window(true, true)
	gut.p("frame between: %s" % r)
	assert_gt(float(r["delta"]), 1.0, "CONTROL: the frame before arming really carried the long delta, so the hazard was present")
	assert_gt(float(r["left"]), 0.8, "THE DEFECT: the window armed right after a %d ms frame and its offer emptied at once" % LONG_FRAME_MS)
	assert_gte(int(r["ms"]), 950, "the window stayed open for its wall second after a long frame (%d ms)" % r["ms"])


func test_control_an_ordinary_frame_leaves_the_full_second() -> void:
	var r: Dictionary = await _window(false, false)
	assert_gte(int(r["ms"]), 950, "CONTROL: with no long frame the window lasts its wall second (%d ms)" % r["ms"])


func test_double_battle_speed_still_leaves_one_wall_second() -> void:
	Engine.time_scale = 2.0
	var r: Dictionary = await _window(false, false)
	Engine.time_scale = _saved_scale
	assert_gte(int(r["ms"]), 950, "at engine 2.0 the window is still one wall second, not half (%d ms)" % r["ms"])


func test_a_paused_tree_still_closes_the_window_after_one_wall_second() -> void:
	get_tree().paused = true
	var r: Dictionary = await _window(false, false)
	get_tree().paused = false
	assert_gte(int(r["ms"]), 950, "with the tree paused the window still runs and closes after one wall second (%d ms)" % r["ms"])


## The ceiling sits on the DEADLINE, which no clock or load can move; elapsed time gets only floors (main 28501).
func test_the_window_is_armed_for_exactly_one_second() -> void:
	for long_frame in [false, true]:
		var r: Dictionary = await _window(long_frame, false)
		assert_between(int(r["span"]), 1000, 1001, "the deadline is one second past arming (long frame %s): %d ms" % [long_frame, r["span"]])
