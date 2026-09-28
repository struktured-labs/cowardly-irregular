extends GutTest

## Watched autogrind logged "Lambda capture at index 0 was freed. Passed "null" instead." up to 59
## times a battle (cowir-autogrind, 272 in 15 battles). The BattleScene survives from one grind battle
## to the next, and the restart cleanup queue_frees every sprite and animator. The melee swing's tween
## was created with the SCENE's create_tween(), so it outlived them, and its contact callback then ran
## with its captured attacker_anim freed. The callback's own is_instance_valid kept it harmless;
## the engine still logged every call. Bound to the attacker sprite, the tween dies with the sprite.

const SCENE := preload("res://src/battle/BattleScene.gd")


func _sprite(x: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.position = Vector2(x, 0)
	return s


func test_the_swing_tween_is_killed_when_its_attacker_is_freed() -> void:
	var scene = SCENE.new()
	add_child_autofree(scene)
	var attacker := _sprite(400)
	var target := _sprite(100)
	scene.add_child(attacker)
	scene.add_child(target)
	scene._animate_melee_attack(attacker, target, null, null, 0.3)
	var tween: Tween = attacker.get_meta("attack_tween", null)
	assert_not_null(tween, "CONTROL: the swing must record its tween on the attacker")
	assert_true(tween.is_valid(), "CONTROL: the swing tween must be running before the cleanup")
	attacker.queue_free()
	target.queue_free()
	## A bound tween is killed on its next STEP after the node goes, before any tweener runs. 0.2s is
	## inside the 0.3s lead-in, so a scene-owned tween would still be valid here.
	await wait_seconds(0.2)
	assert_false(is_instance_valid(tween) and tween.is_valid(),
		"the grind's cleanup freed the attacker mid-swing; a tween still running will call its contact callback with freed captures")


func test_every_attack_tween_is_bound_to_its_sprite() -> void:
	## The cast and rush tweens and the death fade are the same pattern inside larger functions.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var scene_bound := 0
	for line in src.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("var ") and l.ends_with("= create_tween()") and (l.contains("cast_tween") or l.contains("rush_tween")):
			scene_bound += 1
	assert_eq(scene_bound, 0,
		"the cast and rush tweens capture the caster's animator; created on the scene they outlive a grind restart")
