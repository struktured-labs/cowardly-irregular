extends GutTest

## His Rat King fight (2026-11-14, godot.log 3540-3547): one rat's 3-action ADVANCE logged "Can't play finished Tween" twice.
## Engine order (4.4.1, adhoc 25634): a lunge killed earlier in the frame its stop's timer fires is valid+dead, and play() errors.
## Measured home on .803 (battle 25706): the engine logs the error, the next lunge owns the sprite and returns it. Guards that.

const SCENE := preload("res://src/battle/BattleScene.gd")
const STOP := 0.18

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


func _sprite(x: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = SpriteFrames.new()
	s.position = Vector2(x, 0)
	return s


## Three lunges by one attacker; each later lunge starts in the SAME frame the previous stop ends (its timer is made first).
## Returns [home, final position, held-and-killed count].
func _chain(same_frame: bool) -> Array:
	var scene = SCENE.new()
	add_child_autofree(scene)
	var attacker := _sprite(400)
	var target := _sprite(100)
	scene.add_child(attacker)
	scene.add_child(target)
	var home: Vector2 = attacker.position
	var killed_held := 0
	scene._animate_melee_attack(attacker, target, null, null)
	for i in range(2):
		var lunge: Tween = attacker.get_meta("attack_tween")
		await wait_seconds(scene._last_contact_in + 0.05)
		var go := [false]
		if same_frame:
			get_tree().create_timer(STOP).timeout.connect(func():
				go[0] = true
				scene._animate_melee_attack(attacker, target, null, null))
		scene._hitstop_seconds = STOP
		scene._apply_hitstop(attacker, target)
		var held: bool = lunge.is_valid() and not lunge.is_running()
		if same_frame:
			while not go[0]:
				await get_tree().process_frame
			if held and attacker.get_meta("attack_tween") != lunge and not lunge.is_valid():
				killed_held += 1
		else:
			await wait_seconds(STOP + 0.05)
			scene._animate_melee_attack(attacker, target, null, null)
	await wait_seconds(1.5)
	return [home, attacker.position, killed_held]


func test_a_chain_whose_next_lunge_kills_a_held_one_still_ends_at_home() -> void:
	var r: Array = await _chain(true)
	assert_eq(r[2], 2, "PRECONDITION: both held lunges were killed by the next one, the shape of his log")
	assert_lt((r[1] as Vector2).distance_to(r[0]), 1.0, "after the chain the attacker stands at home, not where a killed lunge froze it: %s vs %s" % [r[1], r[0]])


func test_a_chain_that_waits_out_each_stop_ends_at_home() -> void:
	var r: Array = await _chain(false)
	assert_lt((r[1] as Vector2).distance_to(r[0]), 1.0, "CONTROL: an unhurried chain ends at home: %s vs %s" % [r[1], r[0]])
