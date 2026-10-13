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
## Named once so the arm and the teardown cannot drift apart, and named for THIS file:
## two guards sharing one probe path is shared mutable state keyed by nothing.
const PROBE := "user://examine_map_id_probe.gd"


## ⛔ THE UNION, AND THE FIRST VERSION OF THIS FILE GOT IT WRONG. TeleportMenu enumerates the
## TELEPORTABLE maps, which is a SUBSET: 15 real maps are reachable only by walking into them
## (blacksmith_interior, dungeon_cave, eldertree_grafting_house...) and appear only as a `map_id` in
## locations.json, which SaveSystem reads to name the place the player is standing in. A corpus
## narrower than the thing it judges reds a legitimate key — and a guard that reds on correct data
## is one somebody deletes.
## The ONE accessor: every arm and every control reads ids through this, so a swap here is visible
## to the arm below rather than only to a helper nobody asserts about.
func _ids_in(path: String) -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string('"id"\\s*:\\s*"([a-z0-9_]+)"')
	for m in rx.search_all(GdSource.code_of(path)):
		out.append(m.get_string(1))
	return out


func _map_ids() -> Array[String]:
	var out: Array[String] = _ids_in(TELEPORT)
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
	## The specific defect, named: a bed name reads like a map id and is not one.
	##
	## ⛔ THE SHAPE IS NOT THE DISCRIMINATOR, AND THE COMMENT THAT SAID IT WAS IS FALSE. This arm
	## used to flag any `village_*` / `overworld_*` / `dungeon_*` scene, resting on "beds are
	## `village_<place>`, map ids are `<place>_village`, nothing else distinguishes them". FOUR REAL
	## MAP IDS CARRY THE BED SHAPE -- `village_starter`, `village_capital`, `dungeon_cave`,
	## `dungeon_forest`, all `map_id` values in locations.json and all present in `_map_ids()`. So the
	## old predicate RED ON A LEGITIMATE KEY, in the one file whose header says a guard that reds on
	## correct data is one somebody deletes. Measured: planting `village_starter` as a scene red the
	## old arm (Failing 1, naming that key) and passes the new one.
	##
	## 🔑 THE REAL PREDICATE IS BED-SHAPED **AND NOT A MAP**. That makes this arm a refinement of
	## test_every_examine_names_a_real_map rather than a second opinion: that one says "not a map",
	## this one says "and it is a bed name, here is the swap". Both fire together on a real mistake.
	var ids: Array[String] = _map_ids()
	var bad: Array[String] = []
	var checked := 0
	for key in _examines():
		var scene: String = str((_examines()[key] as Dictionary).get("scene", ""))
		checked += 1
		if ids.has(scene):
			continue
		if scene.begins_with("village_") or scene.begins_with("overworld_") or scene.begins_with("dungeon_"):
			bad.append("%s -> %s" % [key, scene])
	## ⛔ THIS ARM HAD NO FLOOR OF ITS OWN. Its subject is an ABSENCE, so a broken `_examines()`
	## yields an empty `bad` and a green -- and a control in a sibling arm does not cover this frame.
	assert_gt(checked, 20, "CONTROL: every entry must be read, saw %d -- without this an empty verdict below means nothing" % checked)
	## And the exclusion needs its own floor: if `_map_ids()` ever returned [], every scene would miss
	## `ids.has` and this arm would silently go back to reding on the four real bed-shaped maps.
	assert_gt(ids.size(), MIN_MAP_IDS, "CONTROL: the map-id union must be populated, saw %d" % ids.size())
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


## ⛔ THE INSTRUMENT'S OWN WIRING, PINNED IN BOTH DIRECTIONS. Measured 2026-10-12: swapping
## _ids_in's accessor to a raw FileAccess read left this file 7 passing / 0 failing — the corpus is
## an ACCEPTANCE set, so prose reaching it WIDENS what the guard accepts and a scene keyed to a
## commented id would pass. Three lanes found the same hole in their own prose guards the same hour
## (@cowir-battle's _window_body, @cowir-deploy's gd_code_lines, @cowir-autogrind's controls), and in
## every case the control called the HELPER directly, so it certified GdSource and said nothing about
## what the arm used. This routes through _ids_in, the accessor the real arm uses.
##
## 🔑 AND BOTH DIRECTIONS, because either assertion alone is satisfied by a defect in the other
## (@cowir-autogrind): "a real id survives" passes a strip that never happened, and "the commented id
## is absent" passes a strip that ate the file.
func test_the_accessor_this_guard_uses_strips_prose_both_ways() -> void:
	var probe := PROBE
	var f := FileAccess.open(probe, FileAccess.WRITE)
	assert_not_null(f, "CONTROL: the probe file must be writable")
	f.store_string("\n".join([
		"extends Node",
		"## a comment showing the shape: {\"id\": \"zz_prose_only_map\"}",
		"const MAP_IDS := [",
		"\t{\"id\": \"zz_real_map\", \"label\": \"Real\"},",
		"]",
		"\"\"\"",
		"a docstring naming {\"id\": \"zz_docstring_map\"}",
		"\"\"\"",
	]))
	f.close()
	var got: Array[String] = _ids_in(probe)
	assert_true(got.has("zz_real_map"),
		"the real id did not survive, so the accessor is over-stripping and every verdict here is vacuous")
	assert_false(got.has("zz_prose_only_map"),
		"a `#` comment reached the accepted-id set: prose would widen what this guard accepts")
	assert_false(got.has("zz_docstring_map"),
		"a \"\"\" docstring reached the accepted-id set — code_of() strips comments by LINE and regions by split()")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))


## The plant is erased HERE, not only at the end of the arm: a GDScript error inside the arm aborts
## the enclosing function, so the inline remove never runs and the plant survives into the next run.
## A persisting plant is the one thing that can make this guard lie in the direction it rules out.
func after_each() -> void:
	if FileAccess.file_exists(PROBE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE))
