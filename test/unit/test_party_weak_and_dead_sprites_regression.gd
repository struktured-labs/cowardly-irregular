extends GutTest

## struktured 2026-09-02 (via cowir-sprites): five jobs shipped weak.png + dead.png and NONE of
## the ten sheets could appear on screen — loading is not playing. "weak" had zero consumers and
## nothing ever entered AnimState.DEAD, so downed party members kept standing.
##
## The fix is a REST-STATE seam: BattleAnimator asks a provider what "at rest" means (idle/weak/
## dead) at every return-to-idle site; BattleScene wires the provider to the combatant (dead when
## down, weak strictly below DANGER_HP_THRESHOLD — the same beat as danger music). Unset provider
## = always idle, so enemies and every old caller are untouched.

const AnimatorScript := preload("res://src/battle/BattleAnimator.gd")


func _animator_with(anims: Array) -> Array:
	var sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	for a in anims:
		if not frames.has_animation(a):
			frames.add_animation(a)
		frames.add_frame(a, tex)
	sprite.sprite_frames = frames
	add_child_autofree(sprite)
	var animator = AnimatorScript.new()
	animator.setup(sprite)
	add_child_autofree(animator)
	return [animator, sprite]


func test_unset_provider_is_byte_identical_idle() -> void:
	var pair := _animator_with(["idle", "weak", "dead"])
	assert_eq(pair[0].rest_anim_name(), "idle", "no provider — enemies and old callers must idle")


func test_provider_drives_weak_and_dead_rest_states() -> void:
	var pair := _animator_with(["idle", "weak", "dead"])
	var animator = pair[0]
	var state := ["weak"]
	animator.rest_state_provider = func() -> String: return state[0]
	assert_eq(animator.rest_anim_name(), "weak")
	animator.set_idle()
	assert_eq(pair[1].animation, &"weak", "set_idle must land on the WEAK animation when the provider says so")
	state[0] = "dead"
	animator.set_idle()
	assert_eq(pair[1].animation, &"dead", "a downed combatant's rest state is DEAD — standing corpses were the report")
	assert_eq(animator.current_state, AnimatorScript.AnimState.DEAD)
	state[0] = "idle"
	animator.set_idle()
	assert_eq(pair[1].animation, &"idle", "revive path: rest returns to idle")


func test_missing_sheet_animation_falls_back_to_idle() -> void:
	# Procedural sprites have no weak/dead — the gate on has_animation is load-bearing.
	var pair := _animator_with(["idle"])
	pair[0].rest_state_provider = func() -> String: return "weak"
	assert_eq(pair[0].rest_anim_name(), "idle", "a sheet without 'weak' must idle, never warn-and-freeze")


func test_battle_scene_wires_the_provider_to_the_combatant() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i: int = src.find("rest_state_provider = func()")
	assert_gt(i, -1, "party animators must get a rest-state provider — without it the seam is decorative")
	var body: String = src.substr(i, 400)
	assert_true(body.contains('return "dead"'), "the provider must map a downed combatant to dead")
	assert_true(body.contains("< DANGER_HP_THRESHOLD * 100.0"),
		"weak keys STRICTLY BELOW the shared danger threshold — one beat with the danger music, per spec")
	var snap: int = src.find("func _on_round_started_snap_home")
	var snap_body: String = src.substr(snap, 900)
	assert_true(snap_body.contains("set_idle()"),
		"round boundary must re-resolve rest — poison deaths and item revives have no hit animation")


func test_every_shipped_weak_or_dead_sheet_is_reachable() -> void:
	# Data half: iterate jobs that SHIP the art, so this auto-covers rogue/cleric when they fold.
	var checked := 0
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		for anim in ["weak", "dead"]:
			var path := "res://assets/sprites/jobs/%s/%s.png" % [job, anim]
			if not ResourceLoader.exists(path):
				continue
			checked += 1
			assert_not_null(load(path), "%s must load" % path)
	assert_gt(checked, 4, "CONTROL: the shipped weak/dead sheets must be found (%d) — 0 means the scan is dead" % checked)
