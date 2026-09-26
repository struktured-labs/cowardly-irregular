extends GutTest

## Victory plays ONCE and holds its last frame — the artist's ruling, relayed by struktured 2026-09-26.
##
## Until then party victory LOOPED: the loader flagged idle/victory/weak as loops. A Celebration that
## ends away from its first pose then snapped back every cycle — the cleric's 11 frames end turned
## away from the camera and popped to facing front every 2.4 s.
##
## TWO things decide it, so the behaviour arm pins the EFFECT through both, not either flag:
##   the sheet's loop flag   (HybridSpriteLoader)  -> whether the sprite repeats at all
##   the finish handler      (BattleAnimator)      -> whether a one-shot falls back to idle
## Turning off the loop alone would be wrong if the handler then snapped victory to idle.
##
## The corpus is DERIVED: every manifest job sheet that registers "victory". A job that gains a
## victory sheet tomorrow is covered the day it lands.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const MIN_JOBS := 5


func _victory_jobs() -> Array:
	var f := FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	assert_not_null(f, "sprite_manifest.json must be readable")
	var m = JSON.parse_string(f.get_as_text())
	var out: Array = []
	for job in (m.get("sheets", {}) as Dictionary):
		var entry = m["sheets"][job]
		if entry is Dictionary and "victory" in entry.get("animations", []):
			out.append(str(job))
	out.sort()
	return out


func _frames(job: String) -> SpriteFrames:
	return Loader.load_sprite_frames(null, job, "", "", "", "")


func test_the_corpus_is_every_job_with_a_victory_sheet() -> void:
	# ANTI-VACUITY: every arm loops this list, and an empty list passes them all while asserting nothing.
	var jobs := _victory_jobs()
	assert_gte(jobs.size(), MIN_JOBS, "expected the starter jobs at least, got %s" % str(jobs))
	for named in ["bard", "cleric", "mage", "rogue"]:
		assert_has(jobs, named, "%s has an artist victory and must be in the corpus" % named)


func test_idle_still_loops() -> void:
	# CONTROL: proves the loader's loop decision is being read — a loader that set nothing would pass the next arm.
	for job in _victory_jobs():
		var sf := _frames(job)
		assert_true(sf != null and sf.has_animation(&"idle"), "%s must load an idle" % job)
		if sf and sf.has_animation(&"idle"):
			assert_true(sf.get_animation_loop(&"idle"), "%s idle must keep looping — it is the rest pose" % job)


func test_every_victory_sheet_plays_once() -> void:
	var checked := 0
	for job in _victory_jobs():
		var sf := _frames(job)
		assert_true(sf != null and sf.has_animation(&"victory"), "%s registers victory, so it must load one" % job)
		if sf and sf.has_animation(&"victory"):
			assert_false(sf.get_animation_loop(&"victory"),
				"%s victory must play ONCE and hold (artist ruling 2026-09-26), not loop" % job)
			checked += 1
	assert_gte(checked, MIN_JOBS, "every victory sheet must have been judged, not zero")


func test_victory_ends_on_its_last_frame_and_stays_there() -> void:
	var checked := 0
	for job in _victory_jobs():
		var sf := _frames(job)
		if sf == null or not sf.has_animation(&"victory"):
			continue
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = sf
		add_child_autofree(sprite)
		var animator := BattleAnimator.new()
		add_child_autofree(animator)
		animator.setup(sprite)
		animator.play_victory()
		sprite.set_frame_and_progress(sf.get_frame_count(&"victory") - 1, 0.0)  # victory runs in real time; the ruling is about the END
		await wait_for_signal(sprite.animation_finished, 3.0, "%s victory must FINISH, which a looping one never does" % job)
		await wait_frames(20)  # long enough for a replay or an idle fallback to show up
		var last := sf.get_frame_count(&"victory") - 1
		assert_eq(str(sprite.animation), "victory", "%s must still be showing victory, not fall back to idle" % job)
		assert_eq(sprite.frame, last, "%s must rest on victory's LAST frame (%d)" % [job, last])
		assert_false(sprite.is_playing(), "%s victory must have stopped, not be replaying" % job)
		checked += 1
	assert_gte(checked, MIN_JOBS, "every victory sheet must have been played, not zero")
