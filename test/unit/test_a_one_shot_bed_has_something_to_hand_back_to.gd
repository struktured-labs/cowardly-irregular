extends GutTest

## A `loop: false` music entry ENDS. Something must follow it, and the only mechanism that does is
## the stinger resume: `_try_play_from_manifest` arms a one-shot on `_music_player.finished` ONLY
## when `_is_stinger_track(track_id)` is true. A non-stinger one-shot therefore plays, ends, and
## leaves the music player silent until some unrelated call writes it again.
##
## 🔑 THE OTHER DIRECTION IS ALREADY DEFENDED IN CODE, WHICH IS WHY ONLY THIS ONE NEEDS A GUARD.
## `SoundManager:2061-2067` force-overrides `should_loop = false` for any stinger, so a
## `stinger: true` entry cannot loop however the manifest is authored. Its comment records why:
## five stingers shipped with `loop: true` on 2026-05-02, never fired `finished`, and the previous
## music never came back — struktured's words were "level up music repeats itself".
##
## ⛔ SO THIS FIELD HAS ALREADY BEEN WRONG IN A SHIPPED BUILD, AND THE REPAIR COVERED ONE DIRECTION.
## Zero violations today (19 `loop: false` entries, all 19 `stinger: true`). This is the guard for
## the direction the override does not reach — the next one-shot cue authored without `stinger`.

const MANIFEST_PATH := "res://data/music_manifest.json"


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_gt(raw.length(), 1000, "SCOPE control: the manifest read back %d chars" % raw.length())
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "the manifest did not parse as a Dictionary")
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("tracks", {})


func test_a_non_looping_track_is_a_stinger_or_it_ends_in_silence() -> void:
	var tracks: Dictionary = _tracks()
	assert_gt(tracks.size(), 100,
		"SCOPE control: only %d tracks — the walk broke and a green here would be about nothing" % tracks.size())

	var one_shots: Array[String] = []
	var orphans: Array[String] = []
	for k in tracks.keys():
		var entry = tracks[k]
		if not (entry is Dictionary):
			continue
		if (entry as Dictionary).get("loop", true) != false:
			continue
		one_shots.append(str(k))
		## The same two ways SoundManager decides it: the explicit flag, or the key prefix.
		var is_stinger: bool = bool((entry as Dictionary).get("stinger", str(k).begins_with("stinger_")))
		if not is_stinger:
			orphans.append(str(k))

	## ANTI-VACUITY: the property is only defended while the manifest still HAS one-shots. If the
	## count goes to zero the arm passes by construction and says nothing.
	assert_gt(one_shots.size(), 10,
		"ANTI-VACUITY: found only %d `loop: false` entries — either the manifest changed shape or this walk stopped matching, and an empty corpus cannot fail" % one_shots.size())

	assert_eq(orphans, [],
		"a `loop: false` track is not a stinger, so nothing is armed to follow it: %s — it plays, ends, and the music player stays silent until an unrelated call writes it. Either mark it `\"stinger\": true` (SoundManager arms the resume and force-overrides loop) or give it `\"loop\": true`." % str(orphans))


func test_the_override_that_covers_the_other_direction_still_exists() -> void:
	## This arm's whole premise is that a stinger CANNOT loop because the code forces it. If that
	## override goes, `stinger: true` stops implying a terminating stream and the arm above is
	## defending half a property while reading as though it defends the pair.
	var code: String = str(GdSource.split(FileAccess.get_file_as_string("res://src/audio/SoundManager.gd"))["code"])
	assert_true(code.contains("func _try_play_from_manifest"),
		"CONTROL: the strip ate a known code site — the pins below would read an emptied corpus")
	assert_true(code.contains("should_loop = false"),
		"the stinger loop override is gone from SoundManager — a `stinger: true` entry authored with `loop: true` would now loop forever and never fire `finished`, which is the 2026-05-02 defect verbatim")
	assert_true(code.contains("_is_stinger_track"),
		"nothing decides stinger-ness any more, so neither this file's corpus nor SoundManager's override means what it says")
