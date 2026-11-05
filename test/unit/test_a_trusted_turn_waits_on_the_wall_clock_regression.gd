extends GutTest

## cowir-controller 21831 / cowir-main 21832, 21836, 21841: the trusted-turn interrupt window ("press ⟨cancel⟩ to take
## this turn") is a REACTION window, but it was timed in BATTLE time: 3.6 s of dead air on every trusted turn at 1x,
## and ~0.06 s, unanswerable, at the top of the speed ladder. It is now 1.0 WALL second at every speed up to and
## including "4x" (engine 1.0); above that, and in turbo, there is no window and no offer at all.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

var _guard
var _saved_scale := 1.0
var _saved_speed: float = 0.0


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_speed = float(GameState.default_battle_speed)


func after_each() -> void:
	Engine.time_scale = _saved_scale
	GameState.default_battle_speed = _saved_speed
	BattleManager.turbo_mode = false
	BattleManager._trust_window_pc = null
	_guard.restore()


func _pc() -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = "Trusted"
	pc.is_alive = true
	add_child_autofree(pc)
	return pc


## Runs one window at `scale` beside a wall-clock reference of the window's length; frames from reference to close.
func _close_vs_wall(scale: float) -> int:
	var bm = BattleManager
	var pc := _pc()
	bm.current_combatant = null  # the window then closes without handing the turn to the AI
	var closed: Array = []
	var ref: Array = []
	var on_close := func(who, _taken) -> void:
		if who == pc:
			closed.append(Engine.get_process_frames())
	bm.trust_interrupt_window_closed.connect(on_close)
	Engine.time_scale = scale
	get_tree().create_timer(bm.TRUST_INTERRUPT_WINDOW_SECONDS, true, false, true).timeout.connect(func() -> void: ref.append(Engine.get_process_frames()))
	bm._run_trust_interrupt_window(pc)
	var deadline := Time.get_ticks_msec() + int(bm.TRUST_INTERRUPT_WINDOW_SECONDS / minf(scale, 1.0) * 1000.0) + 2000
	while (closed.is_empty() or ref.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	Engine.time_scale = _saved_scale
	bm.trust_interrupt_window_closed.disconnect(on_close)
	assert_false(ref.is_empty(), "CONTROL: the wall-clock reference fired")
	if closed.is_empty() or ref.is_empty():
		return -9999
	return int(closed[0]) - int(ref[0])


func test_the_window_closes_after_the_same_wall_time_at_1x_and_4x() -> void:
	for scale in [0.25, 1.0]:
		var d: int = await _close_vs_wall(scale)
		assert_ne(d, -9999, "the window closed at engine %.2f" % scale)
		assert_between(d, -2, 2, "at engine %.2f the window lasts its wall second (%d frames off the wall clock)" % [scale, d])


func test_the_offer_stands_up_to_4x_and_not_above_or_in_turbo() -> void:
	var bm = BattleManager
	for speed in [0.25, 0.5, 1.0]:
		GameState.default_battle_speed = speed
		assert_true(bm.trust_window_offered(), "a player at engine %.2f (up to 4x) is offered the window" % speed)
	for speed in [2.0, 4.0, 16.0]:
		GameState.default_battle_speed = speed
		assert_false(bm.trust_window_offered(), "a player at engine %.2f (above 4x) is offered nothing they could take" % speed)
	GameState.default_battle_speed = 0.25
	bm.turbo_mode = true
	assert_false(bm.trust_window_offered(), "turbo never offers it, even at 1x")


## adhoc 21845: it keys on the player's CHOSEN speed, not the live engine scale a beat lowers for a moment.
func test_a_transient_slowdown_does_not_change_the_offer() -> void:
	var bm = BattleManager
	GameState.default_battle_speed = 16.0
	Engine.time_scale = 0.1  # hit-lag, or a first signature's forced 1x
	assert_false(bm.trust_window_offered(), "a 16x player in a hit-stop is still a 16x player: no surprise window")
	GameState.default_battle_speed = 0.5
	Engine.time_scale = 16.0
	assert_true(bm.trust_window_offered(), "CONTROL: a 2x player is offered it whatever the engine reads this frame")


## The routing asks: a trusted turn opens its window only when the window is offered, else goes straight to the AI.
func test_the_trusted_turn_route_asks_before_it_opens_the_window() -> void:
	var src := FileAccess.get_file_as_string(BM_PATH)
	var at := src.find("_run_trust_interrupt_window(current_combatant)")
	assert_gt(at, -1, "CONTROL: the route into the window exists")
	var guard := src.substr(maxi(at - 400, 0), 400)
	assert_string_contains(guard, "and trust_window_offered():", "the route checks the offer before opening the window")
	assert_string_contains(src, "create_timer(TRUST_INTERRUPT_WINDOW_SECONDS, true, false, true)", "and the window waits on the wall clock")
