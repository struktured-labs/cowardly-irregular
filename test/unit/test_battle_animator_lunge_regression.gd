extends GutTest

## Regression tests for BattleAnimator.play_lunge() and the LUNGE anim slot.
##
## When the artist's "Dash" tag was wired into the game, the lunge sprite
## may not exist for every job. The fallback contract: play_lunge() must
## still fire its on_complete callback synchronously so the melee attack
## chain (move → lunge → attack → hit) doesn't stall when the sprite is
## missing the "lunge" animation.
##
## User's exact words: "fall back to whatever we do before if the sprite
## set DNE" — so missing lunge sprite = original behavior preserved.

const BattleAnimatorClass = preload("res://src/battle/BattleAnimator.gd")


func _make_animator_with_anims(anims: Array[String]) -> BattleAnimatorClass:
	"""Helper: build a BattleAnimator whose SpriteFrames has only the listed
	   animation names (each with a single 8x8 white frame)."""
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)
	var sprite = AnimatedSprite2D.new()
	var frames = SpriteFrames.new()
	for name in anims:
		frames.add_animation(name)
		var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		var tex = ImageTexture.create_from_image(img)
		frames.add_frame(name, tex)
	sprite.sprite_frames = frames
	add_child_autofree(sprite)
	animator.setup(sprite)
	return animator


func test_lunge_state_exists_in_enum() -> void:
	# Regression: if AnimState.LUNGE is removed or renamed, play_lunge() breaks
	# silently. We assert the state is present.
	var script = load("res://src/battle/BattleAnimator.gd")
	assert_not_null(script, "BattleAnimator.gd must load")
	var enums = script.get_script_constant_map()
	# AnimState is an enum, not a constant — read it from the script
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)
	# Just check via the instance — enum access throws if missing
	var lunge_value = animator.AnimState.LUNGE
	assert_typeof(lunge_value, TYPE_INT,
		"AnimState.LUNGE must be defined (regression: dash/lunge wiring)")


func test_lunge_anim_name_maps_correctly() -> void:
	# When LUNGE is requested, _get_animation_name should return "lunge"
	# (artist's exported sprite filename). Mismatch = silent miss every battle.
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)
	# Use a sprite with the lunge anim so play_animation routes through play()
	var sprite = AnimatedSprite2D.new()
	var frames = SpriteFrames.new()
	frames.add_animation("lunge")
	var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	frames.add_frame("lunge", ImageTexture.create_from_image(img))
	sprite.sprite_frames = frames
	add_child_autofree(sprite)
	animator.setup(sprite)

	# Call play_lunge — sprite.animation should become "lunge"
	animator.play_lunge()
	assert_eq(sprite.animation, &"lunge",
		"play_lunge must play the 'lunge' animation by name (regression: anim slot wiring)")


func test_lunge_falls_back_when_animation_missing() -> void:
	# THE CORE FALLBACK CONTRACT.
	# When SpriteFrames has no "lunge" animation, play_lunge() must fire its
	# on_complete callback synchronously so the melee chain proceeds.
	var animator = _make_animator_with_anims(["idle", "attack"])
	# Note: NO "lunge" animation registered

	var completed = [false]
	animator.play_lunge(func(): completed[0] = true)

	assert_true(completed[0],
		"on_complete must fire synchronously when 'lunge' is missing (fallback contract — user said 'fall back to whatever we do before if the sprite set DNE')")


func test_lunge_does_not_block_when_sprite_is_null() -> void:
	# Edge case: animator has no sprite assigned (e.g. cleanup race). Must
	# not crash AND must fire callback.
	var animator = BattleAnimatorClass.new()
	add_child_autofree(animator)
	# No setup() — sprite stays null

	var completed = [false]
	animator.play_lunge(func(): completed[0] = true)

	assert_true(completed[0],
		"on_complete must fire when sprite is null (regression: stalled chain)")


func test_lunge_with_animation_does_not_fire_callback_synchronously() -> void:
	# Positive case: when the lunge animation IS present, callback should
	# NOT fire immediately — it waits for sprite.animation_finished signal.
	var animator = _make_animator_with_anims(["lunge"])

	var completed = [false]
	animator.play_lunge(func(): completed[0] = true)

	assert_false(completed[0],
		"on_complete must NOT fire synchronously when animation is present (let the sprite drive timing)")
	assert_true(animator.is_playing,
		"is_playing should be true after successful play_lunge")


func test_play_named_animation_lunge_falls_back_to_attack() -> void:
	# When code calls play_named_animation("lunge") and the sprite has no
	# lunge anim, it should fall through to play_attack rather than play_cast.
	# Lunge is a physical motion — cast would be wrong vibe.
	var animator = _make_animator_with_anims(["idle", "attack"])
	# No "lunge" registered

	var completed = [false]
	animator.play_named_animation("lunge", func(): completed[0] = true)

	# play_attack runs because lunge wasn't found — animation fires, callback
	# is wired to sprite.animation_finished. Just check it didn't crash AND
	# is_playing is true (attack is playing).
	assert_true(animator.is_playing,
		"play_named_animation('lunge') must fall back to play_attack so combat continues")
	assert_eq(animator.sprite.animation, &"attack",
		"play_named_animation('lunge') fallback should route to attack animation, not cast")


func test_play_named_animation_dash_alias_also_works() -> void:
	# Artist's tag is named "Dash" — code should also accept "dash" as an
	# alias for lunge so renaming the export doesn't break the wiring.
	var animator = _make_animator_with_anims(["idle", "attack"])
	# No "lunge" or "dash" registered

	animator.play_named_animation("dash", func(): pass)
	assert_true(animator.is_playing,
		"'dash' should also fall back to attack (artist tag alias)")
	assert_eq(animator.sprite.animation, &"attack",
		"play_named_animation('dash') should route to attack, not cast")
