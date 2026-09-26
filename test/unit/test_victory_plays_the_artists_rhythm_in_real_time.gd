extends GutTest

## Victory plays the ARTIST'S frame timing at half speed, in real time — struktured 2026-09-26.
##
## It animated "too slow on 1x and too fast on 4x": battle speed IS Engine.time_scale (0.25 at
## "1x", 1.0 at "4x"), and victory played while it was still applied, so an 11-frame Celebration
## took 9.6 s at 1x and 2.4 s at 4x. The sheet also played every frame for the same length,
## discarding the artist's own timing (the mage's 50 ms flurry and 500 ms final beat).
##
## He picked option B from three previews: the artist's rhythm, at half speed, whatever the battle
## speed. So: authored ms x 2 per frame, and a playback rate that cancels Engine.time_scale.
##
## The corpus of artist victories is DERIVED from victory.pre_artist.png — the backup an ingest
## writes when artist art replaces a generated victory.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const PACE := 2.0


func after_each() -> void:
	Engine.time_scale = 1.0  # never leak a battle speed into the rest of the suite


func _manifest_sheets() -> Dictionary:
	var f := FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	return (JSON.parse_string(f.get_as_text()) as Dictionary).get("sheets", {})


func _artist_victory_jobs() -> Array:
	var out: Array = []
	for job in _manifest_sheets():
		if FileAccess.file_exists("res://assets/sprites/jobs/%s/victory.pre_artist.png" % job):
			out.append(str(job))
	out.sort()
	return out


func _frame_seconds(sf: SpriteFrames, i: int) -> float:
	return sf.get_frame_duration(&"victory", i) / sf.get_animation_speed(&"victory")


func _animator_for(job: String) -> Array:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Loader.load_sprite_frames(null, job, "", "", "", "")
	add_child_autofree(sprite)
	var animator := BattleAnimator.new()
	add_child_autofree(animator)
	animator.setup(sprite)
	return [animator, sprite]


func test_the_corpus_is_the_four_artist_victories() -> void:
	var jobs := _artist_victory_jobs()
	for named in ["bard", "cleric", "mage", "rogue"]:
		assert_has(jobs, named, "%s has an artist victory and must be derived into the corpus" % named)


func test_every_artist_victory_declares_its_frame_timing() -> void:
	var sheets := _manifest_sheets()
	for job in _artist_victory_jobs():
		var ms = (sheets[job] as Dictionary).get("frame_durations_ms", {}).get("victory", [])
		var sf := Loader.load_sprite_frames(null, job, "", "", "", "")
		assert_eq(ms.size(), sf.get_frame_count(&"victory"),
			"%s: frame_durations_ms.victory must hold one authored duration per victory frame" % job)


func test_each_frame_lasts_twice_the_artists_duration() -> void:
	var sheets := _manifest_sheets()
	var checked := 0
	for job in _artist_victory_jobs():
		var ms: Array = (sheets[job] as Dictionary).get("frame_durations_ms", {}).get("victory", [])
		var sf := Loader.load_sprite_frames(null, job, "", "", "", "")
		if ms.size() != sf.get_frame_count(&"victory"):
			continue
		for i in ms.size():
			assert_almost_eq(_frame_seconds(sf, i), float(ms[i]) * PACE / 1000.0, 0.0005,
				"%s victory frame %d must last %d ms x %.0f" % [job, i, int(ms[i]), PACE])
		checked += 1
	assert_eq(checked, _artist_victory_jobs().size(), "every artist victory must have been timed, not skipped")


func test_the_named_totals_he_saw() -> void:
	# Pinned to the previews struktured chose from: mage 3.34 s, cleric 2.50 s.
	for pair in [["mage", 3.34], ["cleric", 2.50]]:
		var sf := Loader.load_sprite_frames(null, pair[0], "", "", "", "")
		var total := 0.0
		for i in sf.get_frame_count(&"victory"):
			total += _frame_seconds(sf, i)
		assert_almost_eq(total, pair[1], 0.01, "%s victory must run %.2f s" % pair)


func test_victory_ignores_battle_speed() -> void:
	for scale in [0.25, 0.5, 1.0, 2.0]:
		Engine.time_scale = scale
		var pair := _animator_for("mage")
		pair[0].play_victory()
		await wait_frames(2)
		assert_almost_eq(pair[1].speed_scale * Engine.time_scale, 1.0, 0.001,
			"at battle scale %.2f victory must play in REAL time" % scale)


func test_a_late_speed_reset_cannot_drag_victory_back_to_battle_speed() -> void:
	# The final blow's hitstop and the round reset both write speed_scale = 1.0 AFTER play_victory.
	Engine.time_scale = 0.25
	var pair := _animator_for("cleric")
	pair[0].play_victory()
	await wait_frames(2)
	pair[1].speed_scale = 1.0
	await wait_frames(2)
	assert_almost_eq(pair[1].speed_scale, 4.0, 0.001, "victory must re-assert real time after a stray reset")


func test_leaving_victory_hands_the_sprite_back_to_battle_speed() -> void:
	Engine.time_scale = 0.25
	var pair := _animator_for("mage")
	pair[0].play_victory()
	await wait_frames(2)
	pair[0].set_idle()
	await wait_frames(2)
	assert_eq(pair[1].speed_scale, 1.0, "idle must follow battle speed again once victory is left")
