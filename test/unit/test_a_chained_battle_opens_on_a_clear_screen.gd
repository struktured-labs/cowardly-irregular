extends GutTest

## struktured's playtest (main 23206): after a CHAIN link the next battle sat behind black with an iris-shaped hole. Measured
## (overworld 23240): the overlay did clear, but every transition tween ran on Engine.time_scale, so the victory close and the
## battle-2 reveal stretched to seconds at slow battle speeds and to ~10x under a crit's hitlag (0.1), while battle 2 was
## already live underneath. A transition is presentation: it runs on the wall clock and always ends clean.

var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale
	BattleTransition._cleanup_effects()
	BattleTransition._overlay.material = null
	BattleTransition._overlay.modulate.a = 0.0


func after_each() -> void:
	Engine.time_scale = _saved_scale
	BattleTransition._overlay.material = null
	BattleTransition._overlay.modulate.a = 0.0
	BattleTransition._overlay.color = Color.BLACK
	BattleTransition._cleanup_effects()


## The chained hand-off's two transitions, back to back, at one engine scale; returns the wall ms they took.
func _handoff_ms(scale: float) -> int:
	Engine.time_scale = scale
	var t0 := Time.get_ticks_msec()
	await BattleTransition.play_exit_transition(true)
	await BattleTransition.fade_out()
	return Time.get_ticks_msec() - t0


func test_the_handoff_takes_the_same_wall_time_at_any_battle_speed() -> void:
	var at_full := await _handoff_ms(1.0)
	var under_hitlag := await _handoff_ms(0.1)
	assert_lt(at_full, 2500, "CONTROL: the close and reveal fit their budget at engine 1.0 (%d ms)" % at_full)
	assert_lt(under_hitlag, 2500,
		"at a crit's hitlag scale (0.1) the chained close + reveal took %d ms; a transition must run on the wall clock" % under_hitlag)


func test_after_the_reveal_the_screen_is_clear() -> void:
	await _handoff_ms(0.375)
	assert_null(BattleTransition._overlay.material, "the iris material outlived the reveal")
	assert_lt(BattleTransition._overlay.modulate.a, 0.05, "the overlay still covers battle 2 after the reveal")

## Movie Maker steps the game by whole frames; a transition must take the same number of FRAMES at every battle speed, so a
## capture shows it (main 23604). Emulates the SceneTree: each frame advances a tween by (1/60 x Engine.time_scale).
func _frames_to_finish(scale: float) -> int:
	Engine.time_scale = scale
	var probe := Node.new()
	add_child_autofree(probe)
	probe.set_meta("v", 0.0)
	var t: Tween = BattleTransition._wall_tween()
	t.tween_method(func(v: float) -> void: probe.set_meta("v", v), 0.0, 1.0, 0.35)
	t.pause()
	var n := 0
	while t.is_valid() and n < 1000:
		t.custom_step(1.0 / 60.0 * Engine.time_scale)
		n += 1
		if float(probe.get_meta("v")) >= 1.0:
			break
	t.kill()
	return n


func test_a_transition_takes_the_same_frames_at_every_battle_speed() -> void:
	var at_full := _frames_to_finish(1.0)
	var at_quarter := _frames_to_finish(0.25)
	assert_between(at_full, 19, 23, "CONTROL: 0.35 s is ~21 frames at 60 fps at engine 1.0 (got %d)" % at_full)
	assert_eq(at_quarter, at_full, "at battle speed 0.25 the transition took %d frames vs %d: it must run on game time scaled by 1/time_scale" % [at_quarter, at_full])
