extends GutTest

## Every quest's `giver.location.map_id` is where that quest's giver stands, and 21 of 33 named
## something that is not a map: `brasston` for `brasston_village`, `rivet_row`, `maple_heights`,
## `node_prime`, `the_vertex`, `world1_overworld`. Nothing reads the field today, so nothing failed —
## the same shape as data/examine_texts.json keying 15 entries to the MUSIC BED names, found an hour
## earlier. A near-miss id is harmless until the day something looks the map up, and then it is a
## giver who stands nowhere.
##
## 🔑 TWO VALUES ARE LEFT ALONE AND DECLARED BELOW, because a rename would be an invented placement:
## they name places with no map at all. That distinction is the whole reason this is a roster and not
## a substitution table — `rivet_row_tunnels` wants a map or a design decision, not a spelling fix.
##
## 📌 _map_ids() is the same derivation as test_an_examine_names_a_real_map's, deliberately copied
## rather than shared: that file is in flight on another branch, and rewiring two guards to a new
## helper across a fold is a bigger change than the duplication. If a third consumer appears, move it
## into test/unit/helpers/ and delete both copies.

const QUESTS := "res://data/quests"
const TELEPORT := "res://src/ui/TeleportMenu.gd"
const LOCATIONS := "res://data/locations.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const MIN_MAP_IDS := 55
const MIN_QUESTS := 25

## A giver placed somewhere no map exists: the reason says what would retire the entry.
const NO_SUCH_MAP := {
	"rivet_row_tunnels": "world4_below_specification — the W4 tunnels the clockwork rats overheat in. Rivet Row has a village and a union hall; the tunnels are not a map. Retired by building them, or by moving the junction into one that exists",
	"node_prime_inner": "world5_mutual_exclusion — 'inner' Node Prime, at a shared_resource_node. Node Prime has a village and a daemon lounge; this is neither. Retired by a map or by re-placing the race condition",
}


## TeleportMenu enumerates the TELEPORTABLE maps; 15 more are reached only on foot and appear as a
## `map_id` in locations.json, which SaveSystem reads to name the place the player stands in.
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
	## Over-stripping, a bad regex and an unreadable directory are all an empty collection, which
	## would pass every arm below.
	var ids: Array[String] = _map_ids()
	assert_gt(ids.size(), MIN_MAP_IDS, "CONTROL: the map-id union has only %d entries" % ids.size())
	for walked_only in ["blacksmith_interior", "eldertree_grafting_house"]:
		assert_true(ids.has(walked_only),
			"CONTROL: %s is a real map reached only on foot; a corpus without it reds correct data" % walked_only)
	assert_gt(_giver_maps().size(), MIN_QUESTS, "CONTROL: only %d quests name a giver location" % _giver_maps().size())


func test_every_giver_stands_on_a_real_map() -> void:
	var ids: Array[String] = _map_ids()
	var nowhere: Array[String] = []
	for f in _giver_maps():
		var mid: String = str(_giver_maps()[f])
		if not ids.has(mid) and not NO_SUCH_MAP.has(mid):
			nowhere.append("%s -> %s" % [f, mid])
	assert_eq(nowhere, ([] as Array[String]),
		"these quest givers stand on something that is not a map, so nothing can place them: %s" % [nowhere])


func test_no_declaration_outlives_its_gap() -> void:
	## Build the tunnels and this reds until the entry goes — the roster must shrink, not accumulate.
	var ids: Array[String] = _map_ids()
	var stale: Array[String] = []
	for mid in NO_SUCH_MAP:
		if ids.has(str(mid)):
			stale.append(str(mid))
	assert_eq(stale, ([] as Array[String]), "these maps exist now, so their declarations are excuses: %s" % [stale])


func test_every_declaration_is_still_claimed_by_a_quest() -> void:
	## A declaration for a value no quest uses any more hides nothing and misleads a reader.
	var used: Array = _giver_maps().values()
	var ghosts: Array[String] = []
	for mid in NO_SUCH_MAP:
		if not (str(mid) in used):
			ghosts.append(str(mid))
	assert_eq(ghosts, ([] as Array[String]), "no quest places a giver here any more: %s" % [ghosts])


func test_no_giver_map_is_a_near_miss_of_a_real_one() -> void:
	## The specific defect, named: `brasston` is not a map and `brasston_village` is, so the id reads
	## correct to a human and resolves to nothing. Any value that becomes a real map by adding or
	## removing a `_village`/`_overworld` suffix is that mistake, declared or not.
	var ids: Array[String] = _map_ids()
	var near: Array[String] = []
	for f in _giver_maps():
		var mid: String = str(_giver_maps()[f])
		if ids.has(mid):
			continue
		for suffix in ["_village", "_overworld", "_city"]:
			if ids.has(mid + suffix):
				near.append("%s -> %s, but %s exists" % [f, mid, mid + suffix])
	assert_eq(near, ([] as Array[String]), "a near-miss map id reads correct and resolves to nothing: %s" % [near])
