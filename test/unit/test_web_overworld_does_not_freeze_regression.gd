extends GutTest

## Entering an overworld whose bed is web-excluded must not freeze the game.
##
## MEASURED 2026-09-10 on a desktop dev box, generator + WAV conversion:
##
##     abstract     4,233,600 samples   19,951 ms   <- World 6
##     futuristic     996,660            3,821 ms
##     village      1,058,400            3,260 ms
##     overworld      846,720            2,786 ms
##     industrial     769,545            1,866 ms
##
## All of it is per-sample GDScript on the MAIN THREAD. play_area_music's
## `call_deferred` moves that work one frame later; it does not move it off the
## thread, and the docstring "so it does not block scene setup" describes the
## deferral, not the cost. WASM is slower again.
##
## 🔑 WHY IT ONLY BITES ON WEB: the Web preset drops *industrial*, *digital*,
## *abstract*, *futuristic*. On desktop every starter's own bed is present and
## returns at tier 1, so no generator ever runs and no desktop run can show
## this. On web those three tiers fell through to generation.
##
## ⚠️ AND THE ANCHOR THAT SHOULD HAVE PREVENTED IT WAS PROTECTED BUT UNUSED.
## test_web_fallback_anchors_survive_export pins overworld_medieval, saying
## "worlds 3-6 fall back to these when their own tracks are excluded". True of
## dungeon_medieval and village_medieval, which really are cross-world
## fallbacks. False of overworld_medieval: it was only ever
## _start_overworld_music's OWN first-tier bed. A guard defending a fallback
## that no code path took — the ANCHOR existed, the FALLBACK did not.
##
## THE TRADE, stated because it is a musical decision and reversible: on web,
## W4/W5/W6 overworlds now play the medieval bed instead of their procedural
## theme. Those worlds' authored music is already absent there by design; this
## swaps a 20-second freeze for the wrong-but-instant bed. If the procedural
## theme is wanted on web instead, the fix is chunked generation across frames,
## which is a much larger change.

const SM := "res://src/audio/SoundManager.gd"

## Generous by two orders of magnitude: the defect is ~20,000 ms and the
## fallback is a load(). Anything under this cannot be a generation run.
const NO_GENERATION_MS := 1500

var _saved: Dictionary = {}


func before_each() -> void:
	SoundManager._load_music_manifest()
	_saved = {}


func after_each() -> void:
	for k in _saved.keys():
		SoundManager._music_manifest[k] = _saved[k]
	_saved = {}
	SoundManager.stop_music()


func _hide_bed(key: String) -> void:
	## Reproduce the web condition: the manifest still lists it, the build has
	## no file. Restored in after_each — _music_manifest is STATIC and shared.
	if SoundManager._music_manifest.has(key):
		_saved[key] = SoundManager._music_manifest[key]
	SoundManager._music_manifest[key] = {"file": "assets/audio/music/zzq_not_in_this_build.ogg"}


func test_control_the_medieval_anchor_is_loadable() -> void:
	## Everything below depends on the fallback being playable. If this fails the
	## probe is broken, not the subject.
	assert_true(SoundManager.music_is_available("overworld_medieval") if SoundManager.has_method("music_is_available") else true,
		"CONTROL: overworld_medieval must be present for the fallback tier to mean anything")
	assert_true(SoundManager._music_manifest.has("overworld_medieval"),
		"CONTROL FAILED: overworld_medieval is not in the manifest at all")


func test_abstract_overworld_falls_back_instead_of_generating() -> void:
	_hide_bed("overworld_abstract")
	var t0: int = Time.get_ticks_msec()
	SoundManager._start_abstract_music()
	var elapsed: int = Time.get_ticks_msec() - t0
	assert_lt(elapsed, NO_GENERATION_MS,
		"entering the abstract overworld took %d ms — the shipped-bed tier did not fire and _generate_abstract_music ran 4.2M samples on the main thread (measured 19,951 ms here, worse in WASM)" % elapsed)
	var stream: AudioStream = SoundManager._music_player.stream
	assert_not_null(stream, "no stream at all after the fallback")
	assert_true(str(stream.resource_path).contains("overworld_medieval"),
		"expected the shipped medieval bed, got %s" % stream.resource_path)


func test_the_other_two_excluded_worlds_fall_back_too() -> void:
	for pair in [["overworld_digital", "_start_futuristic_music"],
				 ["overworld_industrial", "_start_industrial_music"]]:
		_hide_bed(pair[0])
		var t0: int = Time.get_ticks_msec()
		SoundManager.call(pair[1])
		var elapsed: int = Time.get_ticks_msec() - t0
		assert_lt(elapsed, NO_GENERATION_MS,
			"%s took %d ms with %s hidden — it generated instead of falling back" % [pair[1], elapsed, pair[0]])


func test_a_present_bed_still_wins_so_desktop_is_unchanged() -> void:
	## The tier must be a FALLBACK, not a replacement. Nothing about desktop
	## behaviour may change: overworld_abstract is present there and must play.
	SoundManager._start_abstract_music()
	var stream: AudioStream = SoundManager._music_player.stream
	assert_not_null(stream, "SCOPE control: no stream with the real manifest")
	assert_true(str(stream.resource_path).contains("overworld_abstract"),
		"with its own bed present the abstract overworld played %s — the fallback tier is jumping the queue and this would change every desktop run" % stream.resource_path)


func test_the_fallback_is_ordered_before_the_generator() -> void:
	## Ordering is the whole fix: after the generate call it prevents nothing,
	## and no timing assert would notice because the freeze already happened.
	var src: String = FileAccess.get_file_as_string(SM)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	for pair in [["_start_abstract_music", "_generate_abstract_music"],
				 ["_start_futuristic_music", "_generate_futuristic_music"],
				 ["_start_industrial_music", "_generate_industrial_music"]]:
		var start: int = src.find("func %s()" % pair[0])
		assert_gt(start, 0, "SCOPE control: %s not found" % pair[0])
		var body: String = src.substr(start, 1800)
		var guard: int = body.find("_try_play_from_manifest(\"overworld_medieval\")")
		var gen: int = body.find(pair[1] + "(")
		assert_gt(guard, 0, "%s never tries the shipped medieval bed — on web it goes straight to the generator" % pair[0])
		assert_gt(gen, 0, "SCOPE control: %s does not call %s any more; this ordering check is anchored on nothing" % [pair[0], pair[1]])
		assert_lt(guard, gen,
			"%s tries the shipped bed AFTER calling %s — by then the main thread has already been held for seconds" % [pair[0], pair[1]])
