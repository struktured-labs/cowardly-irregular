extends GutTest

## ⛔ READ THIS BEFORE WIDENING THE FILE. `giver.location.map_id` IS RUNTIME-INERT. Measured again on
## today's tree: `src/` reads `giver.npc_id` (QuestSystem:125/425/446, OverworldNPC:1361) and
## `giver.display_name` (QuestLog:391) and `giver.spawn_flag` — and NOTHING reads `giver.location`.
## A previous pass in this lane already found 8 of these mismatches, checked the consumer, and ruled
## AGAINST guarding the field: a ratchet on prose enforces consistency in prose and reds on a correct
## change. That ruling stands, and this file is deliberately one arm rather than the five I first
## wrote (every giver on a real map · a declaration roster for places with no map · its expiry · its
## ghost check). Those taxed authoring: a quest written in a place that has no map yet — the W4
## tunnels, inner Node Prime — is legitimate authoring and had to buy a declaration to stay green.
##
## 🔑 THE ONE ARM THAT SURVIVES THE RULING IS SAFE BY CONSTRUCTION, WHICH IS WHY IT IS NOT THE SAME
## GUARD. It fires only when the authored value becomes a REAL map id by adding a `_village` /
## `_overworld` / `_city` suffix — `brasston` where `brasston_village` exists. That is never an
## intentional authoring act: a writer who means a real map writes its id, and a writer who means a
## place with no map writes something no suffix completes (`rivet_row_tunnels`, `node_prime_inner` —
## both silent here, both correct, neither declared anywhere). So it cannot red on a correct change,
## and it catches the only mistake in this field that is always a mistake.
##
## 21 of 33 quests carried a bad value before 2026-10-12; 19 were this near-miss shape. The same
## shape as data/examine_texts.json keying 15 entries to the MUSIC BED names, found an hour earlier.

const QUESTS := "res://data/quests"
const TELEPORT := "res://src/ui/TeleportMenu.gd"
const LOCATIONS := "res://data/locations.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SUFFIXES: Array[String] = ["_village", "_overworld", "_city"]
const MIN_MAP_IDS := 55
const MIN_QUESTS := 25


## TeleportMenu enumerates the TELEPORTABLE maps; 15 more are reached only on foot and appear as a
## `map_id` in locations.json, which SaveSystem reads to name the place the player stands in. A
## corpus of the menu alone reds correct data — and that is this file's own near-miss to make.
##
## 📌 Same derivation as test_an_examine_names_a_real_map's, deliberately copied rather than shared:
## that file is in flight on another branch, and rewiring two guards to a new helper across a fold is
## a bigger change than the duplication. A third consumer moves it into test/unit/helpers/.
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


## {quest file -> the map id its giver stands on}; a quest with no authored location is not a row.
func _giver_maps() -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(QUESTS)
	assert_not_null(d, "CONTROL: %s must be readable" % QUESTS)
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [QUESTS, f]))
		if not (parsed is Dictionary):
			continue
		var giver: Variant = (parsed as Dictionary).get("giver", null)
		if not (giver is Dictionary):
			continue
		var loc: Variant = (giver as Dictionary).get("location", null)
		if not (loc is Dictionary):
			continue
		var mid: String = str((loc as Dictionary).get("map_id", ""))
		if mid != "":
			out[f] = mid
	return out


func test_the_corpora_are_real() -> void:
	## Over-stripping, a bad regex and an unreadable directory are all an empty collection, and an
	## empty collection passes the arm below for the wrong reason.
	var ids: Array[String] = _map_ids()
	assert_gt(ids.size(), MIN_MAP_IDS, "CONTROL: the map-id union has only %d entries" % ids.size())
	for walked_only in ["blacksmith_interior", "eldertree_grafting_house"]:
		assert_true(ids.has(walked_only),
			"CONTROL: %s is a real map reached only on foot; a corpus without it would miss near misses of it" % walked_only)
	assert_gt(_giver_maps().size(), MIN_QUESTS, "CONTROL: only %d quests name a giver location" % _giver_maps().size())


func test_no_giver_map_is_a_near_miss_of_a_real_one() -> void:
	var ids: Array[String] = _map_ids()
	var near: Array[String] = []
	for f in _giver_maps():
		var mid: String = str(_giver_maps()[f])
		if ids.has(mid):
			continue
		for suffix in SUFFIXES:
			if ids.has(mid + suffix):
				near.append("%s -> '%s', but '%s' is the map" % [f, mid, mid + suffix])
	assert_eq(near, ([] as Array[String]),
		"a near-miss map id reads correct to a human and names nothing: %s" % [near])


func test_a_place_with_no_map_is_left_alone() -> void:
	## The other half of "safe by construction", kept as an arm so a future widening has to break it
	## on purpose: values naming a place with no map must pass, undeclared. If someone makes this
	## file demand that every giver stand on a real map, this arm is what reds.
	var ids: Array[String] = _map_ids()
	var unmapped: Array[String] = []
	for f in _giver_maps():
		var mid: String = str(_giver_maps()[f])
		if not ids.has(mid):
			unmapped.append("%s -> %s" % [f, mid])
	assert_gt(unmapped.size(), 0,
		"CONTROL: quests are authored in places with no map yet, and this file must stay silent about them")
	for row in unmapped:
		gut.p("NO MAP YET (correct, not a defect): %s" % row)
