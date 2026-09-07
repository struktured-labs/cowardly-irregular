extends GutTest

## struktured 2026-09-03: the bard's death "oscillated between prone and standing". When the
## non-looping collapse finishes, _on_sprite_animation_finished calls set_idle(), and play() on a
## same-name animation that ended restarts it at frame 0 — a self-sustaining stand-and-fall loop.
## Real playback here, not a simulated finish: pause()+frame=N resets frame progress, so play()
## RESUMES it and a simulated arm scores green on the exact defect (measured before this landed).

const AnimatorScript := preload("res://src/battle/BattleAnimator.gd")


func _animator_with_dead() -> Array:
	var sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	for a in ["idle", "dead"]:
		frames.add_animation(a)
		for i in (5 if a == "dead" else 2):
			frames.add_frame(a, tex)
	frames.set_animation_loop("dead", false)
	frames.set_animation_speed("dead", 30.0)
	sprite.sprite_frames = frames
	add_child_autofree(sprite)
	var animator = AnimatorScript.new()
	animator.setup(sprite)
	add_child_autofree(animator)
	return [animator, sprite]


func test_a_finished_collapse_stays_down() -> void:
	var pair := _animator_with_dead()
	var animator = pair[0]
	var sprite: AnimatedSprite2D = pair[1]
	animator.rest_state_provider = func() -> String: return "dead"
	animator.set_idle()
	assert_eq(sprite.animation, &"dead", "CONTROL: the collapse must actually start")
	assert_true(sprite.is_playing(), "CONTROL: and actually play")
	await sprite.animation_finished
	# the animator's finished-handler ran on this same signal, before the await resumed
	assert_false(sprite.is_playing(), "the finished-handler replayed the collapse — the prone<->standing oscillation")
	assert_eq(sprite.frame, 4, "a finished collapse rests on its LAST frame, not back at frame 0")
	animator.set_idle()
	assert_false(sprite.is_playing(), "the round-start re-resolve must be idempotent on a finished collapse")
	assert_eq(sprite.frame, 4)
	# the await resumed INSIDE the emission; unwind before GUT frees the emitting sprite
	await get_tree().process_frame


func test_a_revived_then_redowned_combatant_collapses_afresh() -> void:
	var pair := _animator_with_dead()
	var animator = pair[0]
	var sprite: AnimatedSprite2D = pair[1]
	var state := ["dead"]
	animator.rest_state_provider = func() -> String: return state[0]
	animator.set_idle()
	await sprite.animation_finished
	state[0] = "idle"
	animator.set_idle()
	assert_eq(sprite.animation, &"idle", "CONTROL: revive returns rest to idle")
	state[0] = "dead"
	animator.set_idle()
	assert_eq(sprite.animation, &"dead", "a second death must reach the collapse again")
	assert_true(sprite.is_playing(), "the re-death plays afresh — idempotency must not freeze a NEW collapse")
	await get_tree().process_frame


func test_weak_loops_but_dead_does_not() -> void:
	# set_idle() already treats weak as a looping rest pose; the sheet flag must agree,
	# else weak freezes on its final slump frame while the animator believes it breathes
	var frames = load("res://src/battle/sprites/HybridSpriteLoader.gd").call("load_sprite_frames", null, "bard")
	assert_not_null(frames, "CONTROL: the bard sheet must resolve through the loader")
	if frames == null:
		return
	assert_true(frames.has_animation("weak"), "CONTROL: bard ships weak art")
	assert_true(frames.get_animation_loop("weak"), "weak is a REST pose — it must breathe like idle, not freeze mid-slump")
	assert_false(frames.get_animation_loop("dead"), "dead must NOT loop — a looping collapse is the oscillation this file exists for")
