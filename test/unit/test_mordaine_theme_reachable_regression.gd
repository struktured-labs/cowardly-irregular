extends GutTest

## struktured 2026-09-06: "mordaine doesnt have her own battle song. thats sad."
## She DOES — "A Sound Like a Verdict" (boss_mordaine, cowir-music 2026-07-26) — so this
## file proves every link of the chain is live at RUNTIME, the same way the Rat King test
## does. A composed track that never plays is the inert-asset class we keep re-hitting.

const OGG := "res://assets/audio/music/boss_mordaine.ogg"


func test_the_track_ships_and_loads() -> void:
	assert_true(ResourceLoader.exists(OGG), "boss_mordaine.ogg must exist AND be imported")
	var stream = load(OGG)
	assert_not_null(stream, "the OGG must load as an AudioStream")
	assert_gt(stream.get_length(), 60.0, "a final-boss theme under a minute is a stub")


func test_manifest_entry_carries_the_file() -> void:
	var f := FileAccess.open("res://data/music_manifest.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var e: Dictionary = (d.get("tracks", {}) as Dictionary).get("boss_mordaine", {})
	assert_false(e.is_empty(), "boss_mordaine must be in the manifest")
	assert_ne(str(e.get("file", "")), "", "and carry a file, or the procedural boss theme wins")
	assert_false(bool(e.get("placeholder", false)), "and not be flagged placeholder")


func test_she_is_a_boss_so_the_music_selector_can_see_her() -> void:
	# BattleEnemySpawner stamps is_miniboss only when monsters.json says boss/miniboss.
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var ms = d.get("monsters", d)
	var m: Dictionary = ms.get("chancellor_mordaine", {}) if ms is Dictionary else {}
	assert_true(bool(m.get("boss", false)) or bool(m.get("miniboss", false)),
		"without the boss flag _get_boss_type() returns '' and she falls to the generic theme")


func test_battle_scene_routes_her_id_to_her_track() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i: int = src.find('elif boss_type == "chancellor_mordaine":')
	assert_gt(i, -1, "the music selector must special-case her id")
	assert_true(src.substr(i, 900).contains('play_music("boss_mordaine")'), "and play boss_mordaine there")


func test_play_music_actually_puts_her_track_on_the_player() -> void:
	# THE runtime proof: the manifest path resolves and the player holds her stream.
	SoundManager.play_music("boss_mordaine")
	var stream = SoundManager._music_player.stream
	assert_not_null(stream, "play_music must set a stream")
	assert_true(str(stream.resource_path).ends_with("boss_mordaine.ogg"),
		"the player must hold boss_mordaine.ogg, got: %s" % str(stream.resource_path if stream else "null"))
	SoundManager.stop_music()
