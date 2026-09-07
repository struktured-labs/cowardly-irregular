extends GutTest

## Treasure-chest integrity guard (2026-07-01, cowir-main brief).
##
## The chest ecosystem spans 6 overworlds (10 chests each), 11 village
## scenes, WhisperingCave's per-floor chests, and DragonCave's T-marker
## loot pools across 10 dungeon subclasses. A contents_id that doesn't
## resolve no-ops silently (player opens chest, gets nothing), and a
## duplicate chest_id silently shares its opened-flag with the other
## chest. Both bug classes slip manual review — same rationale as
## test_monster_data_integrity.
##
## Static source-scan style (regex over .gd) mirroring the other
## integrity tests — chests are authored inline in scene scripts, not
## in a data file.

const OVERWORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}

const VILLAGE_DIR := "res://src/maps/villages"
const DUNGEON_DIR := "res://src/maps/dungeons"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "expected %s to be readable" % path)
	return text


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	assert_not_null(data, "%s must parse" % path)
	return data


func _resolvable_ids() -> Dictionary:
	var ok: Dictionary = {}
	for iid in _read_json("res://data/items.json").keys():
		ok[iid] = true
	var equipment := _read_json("res://data/equipment.json")
	for cat in ["weapons", "armors", "accessories"]:
		for eid in equipment.get(cat, {}).keys():
			ok[eid] = true
	return ok


func _dir_gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, "dir should exist: %s" % dir_path)
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	return out


func _extract(pattern: String, text: String) -> Array:
	var re := RegEx.new()
	re.compile(pattern)
	var out: Array = []
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out


func test_every_overworld_has_at_least_8_chests() -> void:
	for world in OVERWORLDS:
		var ids := _extract("\\{\"id\": \"([a-z0-9_]+)\"", _read(OVERWORLDS[world]))
		assert_gte(ids.size(), 8,
			"%s overworld must keep >= 8 placed chests (found %d) — exploration reward floor" % [world, ids.size()])


func test_all_chest_ids_are_globally_unique() -> void:
	var seen: Dictionary = {}
	var dupes: Array = []
	var sources: Array = []
	for world in OVERWORLDS:
		sources.append(OVERWORLDS[world])
	sources.append_array(_dir_gd_files(VILLAGE_DIR))
	for path in sources:
		var text := _read(path)
		for id in _extract("\\{\"id\": \"([a-z0-9_]+)\"", text):
			if seen.has(id):
				dupes.append("%s (in %s and %s)" % [id, seen[id], path])
			seen[id] = path
		for id in _extract("chest_id = \"([a-z0-9_]+)\"", text):
			if seen.has(id):
				dupes.append("%s (in %s and %s)" % [id, seen[id], path])
			seen[id] = path
	assert_eq(dupes.size(), 0,
		"chest_id collision = two chests share one opened-flag (silent double-open). Dupes: %s" % str(dupes.slice(0, 8)))


func test_every_overworld_chest_item_resolves() -> void:
	var ok := _resolvable_ids()
	var bad: Array = []
	for world in OVERWORLDS:
		for iid in _extract("\"item\": \"([a-z0-9_]+)\"", _read(OVERWORLDS[world])):
			if not ok.has(iid):
				bad.append("%s -> %s" % [world, iid])
	assert_eq(bad.size(), 0,
		"Every overworld chest contents_id must resolve in items/equipment. Broken: %s" % str(bad.slice(0, 10)))


func test_every_village_chest_item_resolves() -> void:
	var ok := _resolvable_ids()
	var bad: Array = []
	for path in _dir_gd_files(VILLAGE_DIR):
		var text := _read(path)
		for iid in _extract("contents_id = \"([a-z0-9_]+)\"", text):
			if not ok.has(iid):
				bad.append("%s -> %s" % [path.get_file(), iid])
	assert_eq(bad.size(), 0,
		"Every village chest contents_id must resolve. Broken: %s" % str(bad.slice(0, 10)))


func test_every_dungeon_loot_pool_item_resolves() -> void:
	# DragonCave._place_floor_treasure draws from inline item pools;
	# WhisperingCave authors per-floor chest_data. Both are plain string
	# ids inside array/dict literals — scan every quoted id that flows
	# into contents_id assignments or pool arrays.
	var ok := _resolvable_ids()
	var bad: Array = []
	for path in _dir_gd_files(DUNGEON_DIR):
		var text := _read(path)
		for iid in _extract("contents_id = \"([a-z0-9_]+)\"", text):
			if not ok.has(iid):
				bad.append("%s -> %s" % [path.get_file(), iid])
		for pool in _extract("item_pool = \\[([^\\]]+)\\]", text):
			for m in _extract("\"([a-z0-9_]+)\"", pool):
				if not ok.has(m):
					bad.append("%s pool -> %s" % [path.get_file(), m])
		for pool in _extract("\"item\": \"([a-z0-9_]+)\"", text):
			if not ok.has(pool):
				bad.append("%s -> %s" % [path.get_file(), pool])
	assert_eq(bad.size(), 0,
		"Every dungeon chest/pool item must resolve. Broken: %s" % str(bad.slice(0, 10)))


func test_dungeon_layouts_carry_treasure_markers() -> void:
	# Every DragonCave subclass authors T markers in floor_layouts; the
	# base class turns them into chests. A refactor that drops the
	# markers silently removes all cave loot.
	var missing: Array = []
	for path in _dir_gd_files(DUNGEON_DIR):
		var f: String = path.get_file()
		if f in ["DragonCave.gd", "BossTrigger.gd", "WhisperingCave.gd"]:
			continue  # base class / helper / bespoke chest system
		var text := _read(path)
		if not text.contains("floor_layouts"):
			continue  # not a layout-driven dungeon
		var re := RegEx.new()
		re.compile("\"[.#MTBUDSPWC ]*T[.#MTBUDSPWC ]*\"")
		if re.search(text) == null:
			missing.append(f)
	assert_eq(missing.size(), 0,
		"Layout-driven dungeons must keep at least one T (treasure) marker: %s" % str(missing))
