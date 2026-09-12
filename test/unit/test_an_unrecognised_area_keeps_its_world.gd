extends GutTest

## An area key the bed dispatcher does not recognise played World 1's overworld,
## whatever world the player was standing in.
##
## `_start_area_music_deferred`'s `_:` arm called `_start_overworld_music`, which
## hardcodes `overworld_medieval`. Both defects this file's neighbours record are
## that shape: tick 359 (five canonical `<world>_overworld` map ids fell through, so
## every non-medieval overworld played W1 battle-and-field music) and the 8-of-13
## dungeon ids named at `GameLoop:5616`. Each was fixed by adding the missing arms —
## the DEFAULT stayed World 1, so the next missing arm costs the same bug again.
##
## 🔑 THE TWO MAPS DISAGREE BY 11 KEYS AND THAT IS THE DURABLE PART. Measured
## 2026-09-12: `_get_current_world_suffix` recognises the five canonical
## `<world>_overworld` forms, `castle_harmonia`, and five W2-W6 dungeon map ids
## (`assembly_core`, `null_chamber`, `root_process`, `steampunk_mechanism`,
## `suburban_underground`) that the bed dispatcher does not. Today every scene
## supplies an AREA key rather than a map id, so none of the eleven arrives — the
## right answer by nobody's intent. The default now degrades by world, so the day one
## does arrive it costs the wrong bed for that world at worst, not World 1's.
##
## ⚠️ Not a licence to skip an arm. A world's overworld bed is not its dungeon bed;
## this is a floor, not a substitute for routing.

const W4_CANONICAL := "industrial_overworld"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _stream() -> String:
	var s: AudioStream = SoundManager._music_player.stream
	return s.resource_path if s != null else "<none>"


func _play(key: String) -> void:
	SoundManager.play_area_music(key)
	await get_tree().process_frame
	await get_tree().process_frame


func test_premise_the_canonical_form_really_has_no_bed_arm() -> void:
	## If someone adds the arm, this file's subject is gone and the arm below starts
	## passing for a different reason. Say so here rather than let it drift.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 10000, "SCOPE control: source read back %d chars" % src.length())
	var at: int = src.find("func _start_area_music_deferred")
	assert_gt(at, 0, "CONTROL FAILED: the dispatcher is gone")
	var body: String = src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_false(body.contains("\"%s\"" % W4_CANONICAL),
		"%s now HAS a bed arm — good, but then this file is testing the default through a key that no longer reaches it. Pick another unrecognised key." % W4_CANONICAL)


func test_an_unrecognised_key_plays_this_worlds_overworld_not_world_ones() -> void:
	## The suffix resolver DOES know this form, so the cache is correct while the
	## dispatcher misses — which is exactly the state the default has to survive.
	await _play(W4_CANONICAL)
	assert_eq(SoundManager._current_world_suffix, "industrial",
		"PREMISE FAILED: the suffix resolver reported '%s', so the default had nothing to degrade to" % SoundManager._current_world_suffix)
	assert_eq(_stream(), "res://assets/audio/music/overworld_industrial.ogg",
		"an unrecognised World 4 area key played %s — the default is still World 1's bed" % _stream())


func test_control_the_medieval_default_is_unchanged() -> void:
	## The old behaviour is still correct when the world IS medieval, and this is the
	## arm that catches a fix which simply stopped playing anything.
	await _play("overworld")
	assert_eq(_stream(), "res://assets/audio/music/overworld_medieval.ogg",
		"the plain overworld key stopped playing the medieval bed (%s)" % _stream())


func test_control_a_recognised_key_still_routes_through_its_own_arm() -> void:
	## ⛔ MUST be a key whose ARM and the DEFAULT disagree, or the control cannot fail.
	## First draft used `overworld_suburban`: deleting its arm left the test GREEN,
	## because the world-aware default composes `overworld_suburban` too. The new
	## default SHADOWS all five overworld arms — measured, and the reason this arm
	## moved to a dungeon, where the arm plays dungeon_suburban and the default would
	## play overworld_suburban.
	await _play("suburban_dungeon")
	assert_eq(_stream(), "res://assets/audio/music/dungeon_suburban.ogg",
		"a key WITH an arm now resolves through the default instead (%s) — the default is a floor for unrouted keys, never a substitute for routing" % _stream())


func test_an_unknown_key_in_an_unknown_world_still_lands_somewhere() -> void:
	## The floor: a key with no arm in EITHER map falls to the cached world, and with
	## no cache to speak of that is medieval. It must still play, not go silent.
	await _play("overworld")
	await _play("a_place_that_does_not_exist")
	assert_ne(_stream(), "<none>",
		"an entirely unknown area key left the player in silence")
