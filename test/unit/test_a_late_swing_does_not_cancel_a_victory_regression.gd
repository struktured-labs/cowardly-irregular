extends GutTest

## struktured 2026-11-07 (playtest of 79b5d5a5c): "fighter didn't celebrate after battle, he just sat there". The Fighter
## swung, the Mage's Fulmen landed the kill, and victory began while the Fighter's lunge was still in flight; its contact
## callback then played the attack over the Celebration, and the attack's finish dropped him to idle. The earlier fix
## (test_victory_pose_survives_attack_snap_regression) only guarded the snap-home timer. Now the animator itself holds
## victory against any late swing, cast, steal or named animation, while death, defeat and an explicit set_idle may still follow it.

func _animator() -> BattleAnimator:
	var frames := SpriteFrames.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	for anim in ["idle", "attack", "cast", "hit", "victory", "dead", "power_strike"]:
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.add_frame(anim, tex)
		frames.set_animation_loop(anim, anim in ["idle", "victory"])
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	add_child_autofree(sprite)
	var a := BattleAnimator.new()
	sprite.add_child(a)
	a.setup(sprite)
	return a


func test_a_swing_landing_after_the_win_keeps_the_celebration() -> void:
	var a := _animator()
	a.play_victory()
	assert_eq(a.sprite.animation, &"victory", "CONTROL: the Celebration started")
	var ran := [false]
	a.play_attack(func(): ran[0] = true)
	a.play_cast()
	a.play_hit()
	a.play_named_animation("power_strike")
	a.play_steal()
	a.play_mug()
	a.play_backstab()
	assert_eq(a.current_state, BattleAnimator.AnimState.VICTORY, "a late swing, cast, hit or steal must not replace the win")
	assert_eq(a.sprite.animation, &"victory", "the sprite still plays the Celebration")
	assert_true(ran[0], "the refused swing's on_complete still runs, so its action chain does not stall")


func test_before_the_win_a_swing_plays_as_always() -> void:
	var a := _animator()
	a.play_attack()
	assert_eq(a.sprite.animation, &"attack", "CONTROL: outside a victory the attack plays")
	a.play_victory()
	assert_eq(a.sprite.animation, &"victory", "and victory replaces it")


func test_death_still_follows_a_win() -> void:
	var a := _animator()
	a.play_victory()
	a.play_animation(BattleAnimator.AnimState.DEAD)
	assert_eq(a.current_state, BattleAnimator.AnimState.DEAD, "a fall is never refused, even mid-celebration")


func test_an_explicit_rest_still_leaves_the_win() -> void:
	var a := _animator()
	a.play_victory()
	a.set_idle()
	assert_eq(a.current_state, BattleAnimator.AnimState.IDLE, "set_idle is the scene's own rest call, so it hands the sprite back")
