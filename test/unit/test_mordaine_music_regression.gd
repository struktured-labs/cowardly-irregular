extends GutTest

## Mordaine's own music (2026-07-26).
##
## She is the W1 final boss and was borrowing `boss_medieval` — a key that is
## ALSO the generic W1 boss fallback, whose prompt is generic ("Epic boss
## confrontation, towering enemy") while every mid-fight Masterite got a
## character-specific composition. Her canon is administrative rather than
## demonic: ledgers, columns, the plain chair beside the overturned throne,
## a defeat that closes a book instead of screaming.
##
## Two tracks now exist:
##   boss_mordaine            "A Sound Like a Verdict"   — the fight
##   cutscene_mordaine_theme  "Already Looking At You"   — puppet/approach scenes
##
## Pins:
##   1. both tracks exist, load, and loop
##   2. BattleScene routes her to boss_mordaine, NOT boss_medieval
##   3. boss_medieval survives as the generic fallback (removing it would
##      silently drop every non-Masterite W1 boss to procedural audio)
##   4. the battle track is long enough to be a battle track — the generator
##      returns 2 clips per prompt and the pipeline used to take whichever
##      finished first, which is biased toward the SHORT one (a 24s "boss
##      theme" was the symptom that found it)

const MANIFEST := "res://data/music_manifest.json"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"

## Shortest credible loop for a multi-minute boss fight. The two W1 reference
## points sit at 147s; this floor only catches the truncated-take failure.
const MIN_BOSS_SECONDS: float = 60.0


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _tracks() -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read(MANIFEST))
	assert_true(parsed is Dictionary and parsed.has("tracks"), "manifest parses")
	return parsed["tracks"]


func test_both_mordaine_tracks_exist_and_load() -> void:
	var tracks: Dictionary = _tracks()
	for key in ["boss_mordaine", "cutscene_mordaine_theme"]:
		assert_true(tracks.has(key), "manifest must carry %s" % key)
		var entry: Dictionary = tracks[key]
		var path: String = str(entry.get("file", ""))
		assert_ne(path, "", "%s must have a file: field" % key)
		if not path.begins_with("res://"):
			path = "res://" + path
		assert_not_null(load(path), "%s OGG must load from %s" % [key, path])
		assert_true(bool(entry.get("loop", false)),
			"%s must loop — it plays under a fight or a held scene, not as a stinger" % key)


func test_battle_track_is_long_enough_to_be_a_battle_track() -> void:
	## Regression on the generator, not the composition: Suno returns 2 clips
	## per prompt and they can differ wildly (37s vs 146s from one prompt here).
	## Taking the first to COMPLETE favours the shorter render.
	var tracks: Dictionary = _tracks()
	if not tracks.has("boss_mordaine"):
		return  # covered by the existence test
	var dur: float = float(tracks["boss_mordaine"].get("duration", 0.0))
	assert_gt(dur, MIN_BOSS_SECONDS,
		"boss_mordaine is %.1fs — too short to carry a boss fight. The generator returns two takes; check whether the LONGER sibling was discarded." % dur)


func test_battle_scene_routes_mordaine_to_her_own_track() -> void:
	var src := _read(BATTLE_SCENE)
	# Anchor on the music branch specifically. The bare id appears twice in
	# this file (there is an unrelated match arm ~1200 lines earlier), so
	# searching the name alone reads the wrong block — which is exactly how
	# this assertion failed on its first run.
	var idx: int = src.find("elif boss_type == \"chancellor_mordaine\":")
	assert_gt(idx, -1, "BattleScene must have the chancellor_mordaine music branch")
	# Look at the branch body only — boss_medieval legitimately appears
	# elsewhere in the file as the generic fallback.
	var branch: String = src.substr(idx, 900)
	assert_true(branch.contains("play_music(\"boss_mordaine\")"),
		"Mordaine's branch must play boss_mordaine")
	assert_true(branch.contains("_base_music_track = \"boss_mordaine\""),
		"_base_music_track must be boss_mordaine so danger-music recovery restores HER theme, not the generic one")
	assert_false(branch.contains("play_music(\"boss_medieval\")"),
		"Mordaine must no longer borrow boss_medieval — that key is the generic W1 boss fallback")


func test_generic_medieval_boss_track_still_exists() -> void:
	## Negative pin: boss_medieval is now purely the generic fallback. It must
	## survive — dropping it would send every non-Masterite W1 boss to
	## procedural audio, and nothing else would fail.
	var tracks: Dictionary = _tracks()
	assert_true(tracks.has("boss_medieval"),
		"boss_medieval must remain as the generic W1 boss theme after Mordaine stopped borrowing it")
