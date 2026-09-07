extends GutTest

## Audit ratchet 2026-07-03. SoundManager.play_ui silently returns on a
## key found in neither the SFX manifest nor the procedural SOUNDS dict
## — correct at runtime (the voice_* convention depends on it) but it
## means a typo'd `sfx` in a cutscene is pure silence with no log. Same
## silent class for battle-step `enemies` ids. Both surfaces are
## hand-authored by cowir-story per batch; this pins them to their
## catalogs. Music `track` refs have their own audit
## (test_cutscene_music_track_orphan_audit).


func _each_step(fn: Callable) -> void:
	var dir := DirAccess.open("res://data/cutscenes")
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
			if d is Dictionary:
				for s in d.get("steps", []):
					if s is Dictionary:
						fn.call(f, s)
		f = dir.get_next()


func test_every_cutscene_sfx_key_resolves() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var known: Dictionary = manifest.get("sfx", {})
	var procedural: Dictionary = SoundManager.SOUNDS
	var dangling: Array = []
	_each_step(func(fname: String, s: Dictionary):
		var key: String = str(s.get("sfx", ""))
		if key != "" and not known.has(key) and not procedural.has(key):
			dangling.append("%s → %s" % [fname, key]))
	assert_eq(dangling.size(), 0,
		"cutscene sfx keys that resolve NOWHERE (play_ui returns silently): %s" % str(dangling))


func test_every_cutscene_battle_enemy_resolves() -> void:
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var dangling: Array = []
	_each_step(func(fname: String, s: Dictionary):
		var enemies = s.get("enemies", [])
		if enemies is Array:
			for m in enemies:
				if not monsters.has(str(m)):
					dangling.append("%s → %s" % [fname, str(m)]))
	assert_eq(dangling.size(), 0,
		"cutscene battle-step enemies missing from monsters.json: %s" % str(dangling))
