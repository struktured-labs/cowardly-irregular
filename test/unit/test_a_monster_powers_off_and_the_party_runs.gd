extends GutTest

## struktured 2026-11-07: a monster's death should be "a digital-like fading out … like a TV station turning
## off", maybe per world later; and a flee should be a readable beat, not a cut. Both run on the WALL clock.
## EnemyDeathFx plays the world's style from data/enemy_death_styles.json; BattleScene.play_escape_beat runs
## the party off-screen on a successful escape, and GameLoop awaits it before its exit transition.

const STYLES := "res://data/enemy_death_styles.json"
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")


func _table() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STYLES))
	assert_true(parsed is Dictionary, "VOID: enemy_death_styles.json did not parse")
	return parsed if parsed is Dictionary else {}


func _sprite() -> Sprite2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	add_child_autofree(s)
	return s


func test_every_world_resolves_to_an_authored_style() -> void:
	var t := _table()
	var styles: Array = t.get("styles", [])
	assert_true(str(t.get("default", "")) in styles, "the default style %s is not one of the authored styles" % t.get("default"))
	var by_world: Dictionary = t.get("by_world", {})
	for suffix in HybridSpriteLoader.WORLD_SUFFIXES:
		var key := EnemyDeathFx.world_key(suffix)
		assert_true(by_world.has(key), "world '%s' has no death-style entry" % key)
		assert_true(EnemyDeathFx.style_for(key) in styles, "world '%s' resolves to '%s', not an authored style" % [key, EnemyDeathFx.style_for(key)])
	var known: Array = []
	for suffix in HybridSpriteLoader.WORLD_SUFFIXES:
		known.append(EnemyDeathFx.world_key(suffix))
	for key in by_world.keys():
		assert_true(key in known, "stale death-style entry '%s' names no world" % key)


func test_an_unknown_world_falls_back_to_the_default() -> void:
	assert_eq(EnemyDeathFx.style_for("no_such_world"), EnemyDeathFx.default_style())


func test_a_boss_keeps_its_own_death() -> void:
	var boss := Node.new()
	boss.set_meta("is_boss", true)
	var grunt := Node.new()
	assert_false(EnemyDeathFx.applies_to(boss), "a boss took the world's death style")
	assert_true(EnemyDeathFx.applies_to(grunt), "CONTROL: an ordinary monster must take the style")
	boss.free()
	grunt.free()


## Each style, at a crawling battle speed, finishes on the wall clock, ends hidden, and never pops: alpha only
## falls over its last frames.
func test_every_style_ends_hidden_on_the_wall_clock_without_a_pop() -> void:
	var saved := Engine.time_scale
	Engine.time_scale = 0.1
	for style in _table().get("styles", []):
		var s := _sprite()
		var cued := [false]
		var flashed_before_cue := [false]
		var t0 := Time.get_ticks_msec()
		EnemyDeathFx.play(s, str(style), func() -> void:
			cued[0] = true
			flashed_before_cue[0] = Time.get_ticks_msec() - t0 >= 70)
		var alphas: Array = []
		while s.visible and Time.get_ticks_msec() - t0 < 2000:
			alphas.append(s.modulate.a)
			await get_tree().process_frame
		var took := (Time.get_ticks_msec() - t0) / 1000.0
		assert_false(s.visible, "%s never hid the sprite" % style)
		assert_true(cued[0], "%s never fired the death cue" % style)
		assert_true(flashed_before_cue[0], "%s fired its cue before the white flash, where the killing blow's hit sound stomps it" % style)
		assert_lt(took, 1.0, "%s took %.2fs of wall time at 0.1x: it ran on battle time" % [style, took])
		var tail: Array = alphas.slice(maxi(0, alphas.size() - 4))
		for i in range(1, tail.size()):
			assert_lte(float(tail[i]), float(tail[i - 1]) + 0.001, "%s popped: alpha rose on its last frames %s" % [style, str(tail)])
	Engine.time_scale = saved


func test_the_escape_beat_is_about_a_second_and_capped() -> void:
	assert_eq(BattleSceneScript.escape_beat_length(0), 0.0, "no runners, no beat")
	assert_almost_eq(BattleSceneScript.escape_beat_length(5), 1.05, 0.001, "five members: the last leaves at ~1.05 s")
	assert_lte(BattleSceneScript.escape_beat_length(40), BattleSceneScript.ESCAPE_CAP, "the beat outran its cap")


## The beat belongs to a successful escape only, and GameLoop waits for it before the exit transition.
func test_the_escape_beat_runs_only_on_a_clean_escape() -> void:
	var gl := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at := gl.find("if _escape_survivors > 0:")
	assert_gt(at, -1, "VOID: GameLoop's escape branch moved")
	var branch := gl.substr(at, 400)
	var beat := branch.find("play_escape_beat()")
	var exit := branch.find("play_exit_transition(true)")
	assert_gt(beat, -1, "the escape branch never plays the beat")
	assert_lt(beat, exit, "the beat must play before the exit transition, not under it")
	var bs := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var fn := bs.substr(bs.find("func play_escape_beat"), 300)
	assert_true(fn.contains("not _lost_battle_is_escape()"), "the beat isn't gated on a real escape, so a wipe would run it")


## Game seconds a style needs to hide its sprite, stepped by hand in 1/60 s frames with the tween paused,
## the way Movie Maker steps a capture: a fixed delta per frame, whatever the OS clock says.
func _game_seconds_to_hide(style: String) -> float:
	var s := _sprite()
	var tween := EnemyDeathFx.play(s, style)
	tween.pause()
	var stepped := 0.0
	while s.visible and stepped < 5.0:
		tween.custom_step(1.0 / 60.0)
		stepped += 1.0 / 60.0
	return stepped


## cowir-cutscenes 23594: an OS-clock tween (set_ignore_time_scale) finishes in ~2 frames of a Movie Maker
## capture, so a clip showed the monster already gone. Stepped by game frames, the death at 0.25x must take
## a quarter of the game time it takes at 1x: the same REAL length, and every frame of it drawn.
func test_every_style_steps_with_game_frames_at_its_real_length() -> void:
	var saved := Engine.time_scale
	for style in _table().get("styles", []):
		Engine.time_scale = 1.0
		var at_1x := _game_seconds_to_hide(str(style))
		Engine.time_scale = 0.25
		var at_quarter := _game_seconds_to_hide(str(style))
		Engine.time_scale = saved
		assert_between(at_1x, 0.3, 1.5, "CONTROL: %s took %.2f game s at 1x stepped by hand" % [style, at_1x])
		assert_almost_eq(at_quarter, at_1x * 0.25, 0.05, "%s took %.2f game s at 0.25x vs %.2f at 1x: it is not stepped by game frames at its real length" % [style, at_quarter, at_1x])
	Engine.time_scale = saved
	var bs := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var beat := bs.substr(bs.find("func play_escape_beat"), bs.find("func _process(") - bs.find("func play_escape_beat"))
	assert_false(beat.contains(".set_ignore_time_scale("), "the escape beat is back on the OS clock: a capture shows the party already gone")
	assert_false(beat.contains(", true, false, true)"), "the escape beat's wait is back on the OS clock")
	assert_gt(beat.count("EnemyDeathFx.real_time("), 2, "the escape beat's tweens aren't on the game-frame clock")


## A killing crit starts the death INSIDE its hitlag (time_scale 0.1 for ~80 ms). A speed fixed at that moment
## (x10) then ran the whole death ~4x fast at the battle speed. The speed must follow time_scale every frame.
func test_a_death_that_starts_in_a_hitlag_keeps_its_real_length() -> void:
	var saved := Engine.time_scale
	Engine.time_scale = 1.0
	var length := _game_seconds_to_hide("crt_off")
	var s := _sprite()
	Engine.time_scale = 0.1
	var t0 := Time.get_ticks_msec()
	EnemyDeathFx.play(s, "crt_off")
	await get_tree().process_frame
	await get_tree().process_frame
	Engine.time_scale = 0.375
	while s.visible and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	Engine.time_scale = saved
	assert_false(s.visible, "VOID: the death never finished")
	assert_gt(took, length * 0.75, "a death begun in a hitlag took %.2fs of real time, its length is %.2fs: the speed was locked at the hitlag's" % [took, length])
	assert_lt(took, length * 1.6, "a death begun in a hitlag took %.2fs, its length is %.2fs" % [took, length])
