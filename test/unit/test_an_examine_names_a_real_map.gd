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
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const MIN_MAP_IDS := 40


## Every map id the teleport menu can reach — the one place in src/ that enumerates them.
func _map_ids() -> Array[String]:
	var out: Array[String] = []
	var code: String = GdSource.code_of(TELEPORT)
	var rx := RegEx.create_from_string('"id"\\s*:\\s*"([a-z0-9_]+)"')
	for m in rx.search_all(code):
		out.append(m.get_string(1))
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
