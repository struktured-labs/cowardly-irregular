extends GutTest

## Regression test for BattleAnimator.play_animation callback safety.
##
## Bug found via audit: when play_animation() was called but the sprite's
## SpriteFrames lacked the requested animation (or sprite was null), the
## function pushed a warning and set is_playing=false but NEVER invoked
## the on_complete Callable. Any battle action chain that depended on
## "play animation → callback fires → next step runs" would silently
## stall indefinitely.
##
## Fix: call on_complete synchronously in both error branches so chains
## terminate gracefully.

const BattleAnimatorClass = preload("res://src/battle/BattleAnimator.gd")


func test_missing_sprite_still_fires_on_complete() -> void:
	# Sprite is null → on_complete must still fire so caller doesn't stall
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)
	# No setup() call → sprite is null

	var completed = [false]
	animator.play_animation(
		animator.AnimState.ATTACK,
		false,
		func(): completed[0] = true
	)

	assert_true(completed[0],
		"on_complete must fire when sprite is null (regression: stalled action chain)")


func test_missing_animation_still_fires_on_complete() -> void:
	# Sprite exists but has no matching animation → on_complete must still fire
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)

	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteFrames.new()
	# Intentionally DO NOT add the 'attack' animation
	add_child_autofree(sprite)
	animator.setup(sprite)

	var completed = [false]
	animator.play_animation(
		animator.AnimState.ATTACK,
		false,
		func(): completed[0] = true
	)

	assert_true(completed[0],
		"on_complete must fire when animation is missing (regression: stalled action chain)")


func test_default_callback_does_not_crash_when_invoked() -> void:
	# If no callback is passed (default = invalid Callable), the function
	# should silently skip the call without crashing.
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)

	# No callback provided — must not crash even though sprite is null
	animator.play_animation(animator.AnimState.ATTACK, false)
	assert_true(true, "play_animation with default callback must not crash")


func test_valid_animation_plays_without_callback_triggering_early() -> void:
	# When the animation DOES exist, the callback should NOT fire immediately
	# — it fires via the sprite.animation_finished signal path instead.
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)

	var sprite = AnimatedSprite2D.new()
	var frames = SpriteFrames.new()
	frames.add_animation("attack")
	# Add at least one frame so animation is valid
	var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex = ImageTexture.create_from_image(img)
	frames.add_frame("attack", tex)
	sprite.sprite_frames = frames
	add_child_autofree(sprite)
	animator.setup(sprite)

	var completed = [false]
	animator.play_animation(
		animator.AnimState.ATTACK,
		false,
		func(): completed[0] = true
	)

	# Callback should NOT have fired yet — animation is just starting
	assert_false(completed[0],
		"on_complete must NOT fire synchronously when animation plays normally")
	assert_true(animator.is_playing,
		"is_playing should be true after successful play_animation")
