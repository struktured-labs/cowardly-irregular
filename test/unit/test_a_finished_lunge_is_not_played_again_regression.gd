extends GutTest

## Regression (his Rat King fight 2026-11-14, adhoc 25532): a new lunge killed the one a hit-stop held, and the stop's end played the dead tween.

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


## A running lunge, a 0.18 s stop that holds it, then (if `replace`) a new lunge that kills it. Returns [valid_at_end, finished, resumed].
func _hold(replace: bool) -> Array:
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
	lunge.tween_property(attacker, "position:x", 10.0, 0.4)
	var finished := [false]
	lunge.finished.connect(func(): finished[0] = true)
	await wait_physics_frames(2)
	scene._hitstop_seconds = 0.18
	scene._apply_hitstop(attacker, target)
	if replace:
		lunge.kill()
		var next: Tween = attacker.create_tween()
		next.tween_property(attacker, "position:y", 5.0, 0.5)
		attacker.set_meta("attack_tween", next)
	await wait_seconds(0.12)
	var valid_in_hold: bool = lunge.is_valid()
	await wait_seconds(0.5)
	return [valid_in_hold, finished[0], int(scene._lunges_resumed)]


func test_a_lunge_killed_during_its_stop_is_not_played_again() -> void:
	var r: Array = await _hold(true)
	assert_true(r[0], "PRECONDITION: a killed, paused lunge is still is_valid() while the stop runs (else the reported error has another cause)")
	assert_eq(r[2], 0, "the stop's end played a lunge a newer one had killed")


func test_a_held_lunge_is_still_resumed() -> void:
	var r: Array = await _hold(false)
	assert_eq(r[2], 1, "CONTROL: the held lunge was not resumed after the stop")
	assert_true(r[1], "CONTROL: the resumed lunge then runs to its end")
