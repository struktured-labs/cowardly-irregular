extends GutTest

## Regression (his Rat King fight 2026-11-14, adhoc 25532): a stop from the lunge's LAST callback finished it, and the resume played a finished tween.

const SCENE := preload("res://src/battle/BattleScene.gd")

var _saved_scale := 1.0
var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_scale = Engine.time_scale
	Engine.time_scale = 1.0
	_saved_flags = (GameState.battle_fx_flags as Dictionary).duplicate()
	GameState.battle_fx_flags["hit_stop"] = true


func after_each() -> void:
	Engine.time_scale = _saved_scale
	GameState.battle_fx_flags = _saved_flags


## One lunge whose callback applies a 0.18 s stop; `tail` seconds of lunge follow the callback. Returns [finished, resumed].
func _lunge(tail: float) -> Array:
	var scene = SCENE.new()
	add_child_autofree(scene)
	var attacker := AnimatedSprite2D.new()
	attacker.sprite_frames = SpriteFrames.new()
	scene.add_child(attacker)
	var target := AnimatedSprite2D.new()
	target.sprite_frames = SpriteFrames.new()
	scene.add_child(target)
	var lunge: Tween = attacker.create_tween()
	attacker.set_meta("attack_tween", lunge)
	lunge.tween_property(attacker, "position:x", 10.0, 0.05)
	lunge.tween_callback(func():
		scene._hitstop_seconds = 0.18
		scene._apply_hitstop(attacker, target))
	if tail > 0.0:
		lunge.tween_interval(tail)
	var finished := [false]
	lunge.finished.connect(func(): finished[0] = true)
	await wait_seconds(0.12)
	var finished_in_hold: bool = finished[0]
	await wait_seconds(0.5)
	return [finished_in_hold, finished[0], int(scene._lunges_resumed)]


func test_a_stop_from_the_lunges_last_step_does_not_play_it_again() -> void:
	var r: Array = await _lunge(0.0)
	assert_true(r[0], "PRECONDITION: the lunge finished inside its own hold (else the reported error has another cause)")
	assert_eq(r[2], 0, "a finished lunge was played again after the hit-stop")


func test_a_lunge_with_steps_left_is_still_resumed() -> void:
	var r: Array = await _lunge(0.1)
	assert_false(r[0], "CONTROL: a lunge with a step after the callback is held, not finished, during the stop")
	assert_eq(r[2], 1, "CONTROL: the held lunge was not resumed after the stop")
	assert_true(r[1], "CONTROL: the resumed lunge then runs to its end")
