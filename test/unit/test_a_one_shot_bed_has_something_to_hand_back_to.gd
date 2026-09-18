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


## ⛔ DRIVEN, NOT PINNED TO A SPELLING. The first version of this arm asserted the source contained
## `should_loop = false`. A correct refactor — `should_loop = not is_stinger and entry.get("loop",
## true)` — reds it, and a loosened `should_loop = ` would be satisfied by the line beside it.
## cowir-controller produced both halves of that today: a spelling pin red on a correct fix, and
## its loosened form passing 2/2 with the write DELETED, because a sibling line in the same body
## matched. Driving the subject has neither failure mode.
func test_a_stinger_is_forced_not_to_loop_whatever_the_manifest_says() -> void:
	if SoundManager == null:
		assert_true(false, "SoundManager autoload unavailable — this arm would prove nothing")
		return
	var before_key: String = str(SoundManager._current_music)

	## ⛔ DRIVEN WITH THE MANIFEST ENTRY SAYING `loop: true`, WHICH IS THE ONLY WAY THIS ARM CAN SEE
	## THE OVERRIDE AT ALL. Measured: with the real entry (`loop: false`) the outcome is correct via
	## TWO routes, so deleting the override left this GREEN — covered by a different mechanism, not
	## by the one it names. A stinger authored `loop: true` IS the 2026-05-02 shape.
	SoundManager._load_music_manifest()
	var entry = SoundManager._music_manifest.get("stinger_level_up", {})
	assert_true(entry is Dictionary and not (entry as Dictionary).is_empty(),
		"SCOPE control: stinger_level_up is not in the loaded manifest, so this arm drives nothing")
	var authored_loop = (entry as Dictionary).get("loop", true)
	(entry as Dictionary)["loop"] = true
	assert_true(SoundManager._try_play_from_manifest("stinger_level_up"),
		"SCOPE control: stinger_level_up did not play from the manifest, so the assert below is about nothing")
	var stinger_stream: AudioStream = SoundManager._music_player.stream
	(entry as Dictionary)["loop"] = authored_loop
	assert_not_null(stinger_stream, "the stinger produced no stream")
	if stinger_stream != null:
		assert_false(bool(stinger_stream.loop),
			"a stinger authored `loop: true` was left LOOPING — `finished` never fires and the bed it interrupted never comes back, the 2026-05-02 defect verbatim (level up music repeats itself)")

	## The inverse, so "always false" cannot pass the arm above: a bed must still loop.
	assert_true(SoundManager._try_play_from_manifest("battle_medieval"),
		"SCOPE control: battle_medieval did not play from the manifest")
	var bed_stream: AudioStream = SoundManager._music_player.stream
	assert_not_null(bed_stream, "the bed produced no stream")
	if bed_stream != null:
		assert_true(bool(bed_stream.loop),
			"a looping bed was forced not to loop — the override stopped discriminating and every bed now ends in silence")

	## Teardown: this lane shares one autoload and the next file must not inherit a track.
	SoundManager.stop_music()
	SoundManager._current_music = before_key
