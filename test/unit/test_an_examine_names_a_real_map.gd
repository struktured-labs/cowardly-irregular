extends GutTest

## data/examine_texts.json keyed every entry to a `scene`, and 15 of the 26 named something that is
## not a map: `village_harmonia`, `village_brasston`, `overworld_sandrift`. Those are the MUSIC BED
## names — the author keyed the pack to the audio namespace, and the 11 `castle_harmonia` entries
## added later are correct, so the namespace was learned partway through and nobody went back.
##
## 🔑 RE-KEYED RATHER THAN TRANSLATED (@cowir-overworld's ruling, 2026-10-12): a consumer carrying a
## bed-name -> map-id table would be a SECOND source of truth for map identity, and that is the kind
## of thing that drifts. The pack now names map ids, and this file is what keeps it that way — the
## examine surface does not exist yet, so nothing else would notice a wrong key.

const EXAMINES := "res://data/examine_texts.json"
const TELEPORT := "res://src/ui/TeleportMenu.gd"
const LOCATIONS := "res://data/locations.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const MIN_MAP_IDS := 55


## ⛔ THE UNION, AND THE FIRST VERSION OF THIS FILE GOT IT WRONG. TeleportMenu enumerates the
## TELEPORTABLE maps, which is a SUBSET: 15 real maps are reachable only by walking into them
## (blacksmith_interior, dungeon_cave, eldertree_grafting_house...) and appear only as a `map_id` in
## locations.json, which SaveSystem reads to name the place the player is standing in. A corpus
## narrower than the thing it judges reds a legitimate key — and a guard that reds on correct data
## is one somebody deletes.
func _map_ids() -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string('"id"\\s*:\\s*"([a-z0-9_]+)"')
	for m in rx.search_all(GdSource.code_of(TELEPORT)):
		out.append(m.get_string(1))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCATIONS))
	if parsed is Dictionary:
		for key in (parsed as Dictionary):
			var entry: Variant = (parsed as Dictionary)[key]
			if entry is Dictionary:
				var mid: String = str((entry as Dictionary).get("map_id", ""))
				if mid != "" and not out.has(mid):
					out.append(mid)
	return out


func _examines() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXAMINES))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse" % EXAMINES)
	return (parsed as Dictionary).get("examines", {})


func test_the_map_id_corpus_is_real() -> void:
	## Over-stripping and a wrong regex are the same empty list, which would pass every arm below.
	var ids: Array[String] = _map_ids()
	assert_gt(ids.size(), MIN_MAP_IDS, "CONTROL: the teleport menu lists %d map ids" % ids.size())
	for expected in ["harmonia_village", "castle_harmonia", "abstract_overworld"]:
		assert_true(ids.has(expected), "CONTROL: %s must be a known map id" % expected)
	## The half a TeleportMenu-only corpus would have missed: walked into, never teleported to.
	for walked_only in ["blacksmith_interior", "eldertree_grafting_house"]:
		assert_true(ids.has(walked_only),
			"CONTROL: %s is a real map reached only on foot; a corpus without it reds correct data" % walked_only)


func test_every_examine_names_a_real_map() -> void:
	var ids: Array[String] = _map_ids()
	var wrong: Array[String] = []
	var checked := 0
	for key in _examines():
		var scene: String = str((_examines()[key] as Dictionary).get("scene", ""))
		checked += 1
		if not ids.has(scene):
			wrong.append("%s -> %s" % [key, scene])
	assert_gt(checked, 20, "CONTROL: every entry must be read, saw %d" % checked)
	assert_eq(wrong, ([] as Array[String]),
		"an examine keyed to something that is not a map can never be placed: %s" % [wrong])


func test_no_examine_is_keyed_to_a_music_bed() -> void:
	## The specific defect, named: a bed name reads like a map id and is not one. SoundManager's beds
	## are `village_<place>`; map ids are `<place>_village`. Nothing else distinguishes them.
	var bad: Array[String] = []
	for key in _examines():
		var scene: String = str((_examines()[key] as Dictionary).get("scene", ""))
		if scene.begins_with("village_") or scene.begins_with("overworld_") or scene.begins_with("dungeon_"):
			bad.append("%s -> %s" % [key, scene])
	assert_eq(bad, ([] as Array[String]),
		"these name the audio namespace, not a map (harmonia_village, not village_harmonia): %s" % [bad])


func test_every_entry_still_carries_the_text_that_is_the_point() -> void:
	## A re-key edits structure around authored prose; this is the arm that notices if it eats any.
	var thin: Array[String] = []
	var words := 0
	for key in _examines():
		var e: Dictionary = _examines()[key]
		var text: String = str(e.get("text", ""))
		words += text.split(" ", false).size()
		if text.length() < 40 or str(e.get("name", "")) == "" or str(e.get("prop", "")) == "":
			thin.append(str(key))
	assert_eq(thin, ([] as Array[String]), "an entry lost its text, name or prop: %s" % [thin])
	assert_gt(words, 850, "the pack carried 915 words of prose; only %d survive" % words)
