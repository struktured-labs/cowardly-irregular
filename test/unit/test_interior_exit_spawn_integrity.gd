extends GutTest

## Interior→village exit-spawn integrity lint.
##
## Every interior scene builds an exit AreaTransition with
##   `exit.target_map = "some_village_id"`
##   `exit.target_spawn = "some_spawn_name"`
## When the player walks through the exit, the target village looks up
## `target_spawn` in its `spawn_points` dict. If the key is missing, the
## fallback puts the player at the map default (or a hard-coded 0,0
## depending on the caller) — silent regression, no console warning.
##
## Precedent for the class: my 2026-07-11 playtest PR #103 found a
## Brasston loft-exit spawn placed inside a house wall — same shape of
## silent bug, but from the village side. This ratchet catches the
## interior-side complement at commit time.

const INTERIOR_DIR := "res://src/maps/interiors"
const VILLAGE_DIR := "res://src/maps/villages"

## Villages that inherit BaseVillage — the "target_map" of interior exits
## should be one of these ids. `village_return` is a generic router used
## by BlacksmithInterior + reused for any generic "return to whichever
## village you came from" flow — it doesn't have its own file, and the
## dispatch is handled elsewhere; whitelisted.
const GENERIC_TARGETS := ["village_return", "overworld"]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


## Extract every (target_map, target_spawn) pair from an interior file.
func _extract_exits(src: String) -> Array:
	var pairs: Array = []
	# We scan for co-located target_map/target_spawn assignments — sibling
	# lines with an identifier prefix. `exit.` and `front.` and `bay.` are
	# the three prefixes in play across current interiors.
	var re := RegEx.create_from_string(
		"\\b(\\w+)\\.target_map\\s*=\\s*\"(\\w+)\"[\\s\\S]{0,300}?\\1\\.target_spawn\\s*=\\s*\"(\\w+)\"")
	for m in re.search_all(src):
		pairs.append([m.get_string(2), m.get_string(3)])
	return pairs


## Every spawn_points["key"] literal declared in a village .gd file.
func _extract_spawn_keys(src: String) -> Dictionary:
	var keys := {}
	var re := RegEx.create_from_string("spawn_points\\[\"(\\w+)\"\\]")
	for m in re.search_all(src):
		keys[m.get_string(1)] = true
	return keys


## Map a target village id ("harmonia_village") to its .gd file.
func _village_source_for(target_map: String) -> String:
	if target_map in GENERIC_TARGETS:
		return ""
	# harmonia_village → HarmoniaVillage.gd
	# maple_heights_village → MapleHeightsVillage.gd
	var parts: Array = target_map.split("_")
	var camel: String = ""
	for p in parts:
		camel += (p as String).capitalize()
	# maple_heights_village is a special case, camel from parts already yields "MapleHeightsVillage".
	var candidate := VILLAGE_DIR + "/" + camel + ".gd"
	if FileAccess.file_exists(candidate):
		return candidate
	return ""


func test_every_interior_exit_spawn_is_registered_on_target_village() -> void:
	var dir := DirAccess.open(INTERIOR_DIR)
	assert_not_null(dir, "interiors dir readable")
	var interior_count := 0
	var pair_count := 0
	var offenders: Array = []
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "BaseInterior.gd":
			continue
		interior_count += 1
		var src := _read(INTERIOR_DIR + "/" + f)
		for pair in _extract_exits(src):
			var target_map: String = pair[0]
			var spawn: String = pair[1]
			pair_count += 1
			if target_map in GENERIC_TARGETS:
				continue
			var village_src_path := _village_source_for(target_map)
			if village_src_path == "":
				offenders.append("%s → target_map \"%s\" has no matching village .gd file" % [
					f, target_map])
				continue
			var village_src := _read(village_src_path)
			var keys := _extract_spawn_keys(village_src)
			if not keys.has(spawn):
				offenders.append("%s → %s.spawn_points[\"%s\"] never registered (would land player at fallback)" % [
					f, target_map, spawn])
	assert_gt(interior_count, 15,
		"expected the interior fleet to be > 15 files (got %d)" % interior_count)
	assert_gt(pair_count, 15,
		"expected the interior fleet to declare > 15 exit pairs (got %d)" % pair_count)
	assert_eq(offenders.size(), 0,
		"every interior exit's target_spawn must be a spawn_points key on the target village — %d offenders:\n  %s" % [
			offenders.size(), "\n  ".join(offenders)])
