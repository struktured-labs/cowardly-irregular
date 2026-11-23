extends GutTest

## cowir-main 24280 (.794): whatever moves a sprite owns it, and a knock-back is one of the movers. While it owns
## the sprite the idle writer leaves y alone, so the pop carries the sway itself: it leaves from the swayed y the
## hit found and lands on the y the sway resumes at. Resting at a fixed home y jumped by up to 3 px at both ends
## of a 4 px pop. Tweens are stepped by hand: a headless frame is as long as the box makes it.

const SCENE := preload("res://src/battle/BattleScene.gd")
const BASE := Vector2(300, 200)
var _battle = preload("res://test/unit/helpers/battle_state.gd").new()


func before_each() -> void:
	_battle.snapshot()
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()


func after_each() -> void:
	_battle.restore()


## [scene, sprite]: one monster sprite at index `index` of the enemy line, as the scene's own spawn leaves it.
func _fixture(index: int = 0, as_enemy: bool = true) -> Array:
	var scene = SCENE.new()
	add_child_autofree(scene)
	scene.set_process(false)  # the arm advances the idle clock itself
	var sprite: Node2D = null
	for i in index + 1:
		sprite = AnimatedSprite2D.new()
		sprite.position = BASE
		sprite.set_meta("home_position", BASE)
		scene.add_child(sprite)
		if as_enemy:
			scene.enemy_sprite_nodes.append(sprite)
			scene._enemy_base_positions.append(BASE)
		else:
			scene.party_sprite_nodes.append(sprite)
			scene._party_base_positions.append(BASE)
	return [scene, sprite]


## A moment when the sway has the sprite well away from its base y, so "home" and "the swayed y" are different numbers.
func _far_from_base(scene, is_enemy: bool, index: int) -> float:
	var t := 0.0
	while absf(SCENE.idle_offset(is_enemy, index, t)) < (2.4 if is_enemy else 1.6) and t < 20.0:
		t += 0.01
	scene._idle_time = t
	scene._process_idle_animations(0.0)
	return SCENE.idle_offset(is_enemy, index, t)


func _knock(sprite: Node2D) -> Tween:
	var tween: Tween = sprite.get_meta("knockback_tween")
	tween.pause()
	return tween


func test_the_idle_writer_and_the_knock_back_read_one_sway() -> void:
	for is_enemy in [true, false]:
		for index in [0, 2]:
			var f := _fixture(index, is_enemy)
			var scene = f[0]; var sprite: Node2D = f[1]
			var off := _far_from_base(scene, is_enemy, index)
			assert_gt(absf(off), 1.5, "CONTROL: the sway has moved the sprite (%.2f px)" % off)
			assert_almost_eq(sprite.position.y, BASE.y + off, 0.001, "the idle writer puts the sprite where idle_offset says (enemy=%s, index %d)" % [is_enemy, index])
			assert_almost_eq(scene.idle_y(sprite, -1.0), sprite.position.y, 0.001, "idle_y is the y the idle writer just wrote")
	var loose := Node2D.new()
	autofree(loose)
	var g := _fixture()
	assert_eq(g[0].idle_y(loose, 77.0), 77.0, "CONTROL: a sprite the idle writer does not move answers with the fallback")
	assert_ne(SCENE.idle_offset(true, 0, 0.3), SCENE.idle_offset(true, 1, 0.3), "neighbours are out of step")
	assert_lte(absf(SCENE.idle_offset(true, 3, 1.234)), 3.0, "an enemy sways within 3 px")
	assert_lte(absf(SCENE.idle_offset(false, 3, 1.234)), 2.0, "a hero breathes within 2 px")


func test_the_pop_leaves_from_the_swayed_y_and_lands_on_it() -> void:
	for kind in ["plain", "weakness"]:
		var f := _fixture()
		var scene = f[0]; var sprite: Node2D = f[1]
		var off := _far_from_base(scene, true, 0)
		var found_y: float = sprite.position.y
		match kind:
			"plain":
				scene._apply_hit_knockback(sprite, -1.0, 6.0)
			_:
				scene._apply_weakness_hit_knockback(sprite, -1.0, 1.5)
		var up: float = 0.05 if kind == "plain" else 0.08
		var down: float = 0.15 if kind == "plain" else 0.22
		var tween := _knock(sprite)
		assert_true(SCENE.motion_owns(sprite), "CONTROL (%s): the knock-back owns the sprite while it runs" % kind)
		tween.custom_step(0.0001)
		assert_almost_eq(sprite.position.y, found_y, 0.05, "%s: the pop's first frame is at the swayed y it found, not at home (home is %.2f px away)" % [kind, off])
		tween.custom_step(up)
		var lifted: float = found_y - sprite.position.y
		assert_between(lifted, 3.5 if kind == "plain" else 6.5, 4.5 if kind == "plain" else 7.5, "%s: at the top the sprite is lifted from the SWAYED y by the pop alone, 4 px plain / 7 px on a weakness (%.2f)" % [kind, lifted])
		assert_ne(sprite.position.x, BASE.x, "CONTROL (%s): it was knocked sideways" % kind)
		## The idle writer must not take y back while the knock-back owns the sprite.
		var held: float = sprite.position.y
		scene._process_idle_animations(0.0)
		assert_eq(sprite.position.y, held, "%s: the idle writer moved a sprite the knock-back owns" % kind)
		tween.custom_step(down + 0.01)
		assert_almost_eq(sprite.position.x, BASE.x, 0.01, "%s: it comes back to its home x" % kind)
		var landed: float = sprite.position.y
		tween.kill()
		scene._process_idle_animations(0.0)
		assert_almost_eq(sprite.position.y, landed, 0.05, "%s: the sway resumes where the pop landed: a seam of %.2f px" % [kind, absf(sprite.position.y - landed)])


## The sway does not freeze for the length of a knock-back: y keeps following it under the pop.
func test_the_sway_keeps_moving_under_the_pop() -> void:
	var f := _fixture(1)
	var scene = f[0]; var sprite: Node2D = f[1]
	scene._idle_time = 0.0
	scene._process_idle_animations(0.0)
	scene._apply_hit_knockback(sprite, -1.0, 6.0)
	var tween := _knock(sprite)
	tween.custom_step(0.05)
	var top: float = sprite.position.y
	scene._idle_time += 0.4
	tween.custom_step(0.15)
	var want: float = scene.idle_y(sprite, -1.0)
	assert_gt(absf(want - (BASE.y + SCENE.idle_offset(true, 1, 0.0))), 0.5, "CONTROL: the sway moved while the knock-back ran (%.2f px)" % absf(want - (BASE.y + SCENE.idle_offset(true, 1, 0.0))))
	assert_almost_eq(sprite.position.y, want, 0.01, "the pop landed on where the sway is NOW, not where it was when the hit landed (top was %.2f)" % top)


## A sprite mid-lunge belongs to its lunge: a hit on it lifts it from where it is and puts it back there.
func test_a_lunging_sprite_is_lifted_from_where_the_hit_found_it() -> void:
	var f := _fixture()
	var scene = f[0]; var sprite: Node2D = f[1]
	_far_from_base(scene, true, 0)
	sprite.position = Vector2(420, 260)
	var lunge: Tween = sprite.create_tween()
	lunge.tween_interval(5.0)
	lunge.pause()
	sprite.set_meta("attack_tween", lunge)
	scene._apply_hit_knockback(sprite, 1.0, 6.0)
	var tween := _knock(sprite)
	tween.custom_step(0.05)
	assert_between(260.0 - sprite.position.y, 0.0, 4.5, "lifted from the lunge's own y, not from the idle line")
	tween.custom_step(0.16)
	assert_almost_eq(sprite.position, Vector2(420, 260), Vector2(0.01, 0.01), "and put back where the hit found it, mid-lunge")
	lunge.kill()
