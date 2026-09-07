extends GutTest

## Regression (2026-07-08 stinger sweep, split with cowir-cutscenes): every
## defeat cutscene opened stop_music -> letterbox_in -> narration with ZERO
## audio — dead air on the victory beat. Rule: a defeat cutscene must either
## author its own early play_music (a deliberate audio choice — mordaine,
## w1 warden, w5 curator, calibrant) or carry the boss_defeat_stinger. Guards
## every current AND future *defeat*.json against silently rejoining the
## dead-air class.


func test_stinger_asset_registered() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(manifest.get("sfx", {}).has("boss_defeat_stinger"),
		"boss_defeat_stinger must be in sfx_manifest")


func test_every_defeat_cutscene_has_an_audio_beat() -> void:
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	var checked := 0
	for f in dir.get_files():
		if not ("defeat" in f and f.ends_with(".json")):
			continue
		checked += 1
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
		assert_eq(typeof(d), TYPE_DICTIONARY, "%s must parse" % f)
		var steps: Array = d.get("steps", [])
		var early_music := false
		for i in range(mini(3, steps.size())):
			if str(steps[i].get("type", "")) == "play_music":
				early_music = true
		var has_stinger := false
		for s in steps:
			if str(s.get("type", "")) == "play_sfx" and str(s.get("sfx", "")) == "boss_defeat_stinger":
				has_stinger = true
		assert_true(early_music or has_stinger,
			"%s opens with dead air — add boss_defeat_stinger after letterbox_in, or author an early play_music" % f)
	assert_gt(checked, 20, "sanity: the defeat-cutscene roster should be found")
