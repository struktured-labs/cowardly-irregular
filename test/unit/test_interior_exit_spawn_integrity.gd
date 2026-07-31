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
## dispatch discards the interior's spawn name entirely. That is what makes
## the exemption safe, so it is PINNED, not assumed:
## test_village_return_exemption_still_earns_itself.
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


## Does this interior assign a string literal to .target_map? Deliberately a
## SIMPLER pattern than _extract_exits, so a file the pairing regex stops
## reading is named instead of silently dropping out of the audit.
func _declares_a_literal_exit(src: String) -> bool:
	return RegEx.create_from_string("\\w+\\.target_map\\s*=\\s*\"\\w+\"").search(src) != null


## Assigns .target_map at all, literal or not. Swapping a literal for a variable
## would otherwise drop the file out of `declaring` AND out of the pair scan at
## once — unreachable by every check above, counted by none of them.
func _mentions_target_map(src: String) -> bool:
	return RegEx.create_from_string("\\w+\\.target_map\\s*=").search(src) != null


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
	var declaring := 0
	var mentioning := 0
	var unreadable: Array = []
	var offenders: Array = []
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "BaseInterior.gd":
			continue
		interior_count += 1
		var src := _read(INTERIOR_DIR + "/" + f)
		var exits := _extract_exits(src)
		if _mentions_target_map(src):
			mentioning += 1
		if _declares_a_literal_exit(src):
			declaring += 1
			if exits.is_empty():
				unreadable.append(f)
		for pair in exits:
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
	# RELATIONSHIPS, not magic numbers. `> 15` was fail-open by half: 31 interiors
	# declare 31 exits today, so 16 files could stop parsing and still clear it.
	assert_eq(declaring, mentioning,
		"%d interior(s) assign .target_map but only %d do so with a string literal — the difference is invisible to every check in this file" % [
			mentioning, declaring])
	assert_gt(declaring, 0,
		"no interior declares a literal target_map — the audit read nothing and everything below is vacuous")
	assert_true(unreadable.is_empty(),
		"%d interior(s) declare a literal target_map that this audit could not pair with a target_spawn — extend the pattern rather than leaving them unchecked: %s" % [
			unreadable.size(), ", ".join(unreadable)])
	assert_gte(pair_count, declaring,
		"parsed %d exit pair(s) from %d interior(s) declaring one — the pairing regex is reading less than the fleet declares" % [
			pair_count, declaring])
	assert_eq(offenders.size(), 0,
		"every interior exit's target_spawn must be a spawn_points key on the target village — %d offenders:\n  %s" % [
			offenders.size(), "\n  ".join(offenders)])


## WHY the village_return exemption is sound — pinned, not asserted by comment.
##
## GENERIC_TARGETS skips 3 of the 31 exits (Blacksmith/Inn/Shop, spawning
## "blacksmith_exit"/"inn_exit"/"shop_exit"). That is CORRECT today only because
## the dispatch DISCARDS the interior's spawn name and substitutes "default".
## Make either half stop being true and those three route to keys no village
## registers — and the audit above would still be green, because it never looks
## at them. So the exemption has to carry its justification as a live check.
func test_village_return_exemption_still_earns_itself() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var arm := src.find("target_map == \"village_return\"")
	assert_gt(arm, 0, "the village_return dispatch arm still exists")
	# Bounded to the arm, not the file: a spawn_point assignment anywhere else
	# would satisfy a whole-file search while this branch quietly stopped doing it.
	var arm_end := src.find("\n\tif ", arm)
	var body: String = src.substr(arm, arm_end - arm) if arm_end > arm else src.substr(arm, 600)
	# A boolean `contains` is too weak and I measured it: the arm has TWO redirect
	# branches (origin known / fallback to overworld), so stripping one still
	# satisfied a presence check and the mutation survived. Assert the
	# RELATIONSHIP instead — every branch that redirects also substitutes.
	var redirects := RegEx.create_from_string("target_map\\s*=\\s*[^=]").search_all(body).size()
	var subs := RegEx.create_from_string("spawn_point\\s*=\\s*[^=]").search_all(body).size()
	assert_gt(redirects, 0,
		"the village_return arm redirects target_map at least once — zero means this test is reading the wrong span")
	assert_eq(subs, redirects,
		"the arm redirects target_map %d time(s) but substitutes spawn_point %d time(s) — every redirect must replace the interior's spawn name, or the 3 exits whitelisted by GENERIC_TARGETS route to keys no village registers" % [
			redirects, subs])

	# The other half: the substituted key has to exist everywhere it can land.
	var dir := DirAccess.open(VILLAGE_DIR)
	assert_not_null(dir, "villages dir readable")
	var checked := 0
	var missing: Array = []
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "BaseVillage.gd":
			continue
		checked += 1
		if not _extract_spawn_keys(_read(VILLAGE_DIR + "/" + f)).has("default"):
			missing.append(f)
	assert_gt(checked, 0, "read at least one village — zero would pass this for free")
	assert_true(missing.is_empty(),
		"every village must register spawn_points[\"default\"] — village_return lands there from any inn/shop/blacksmith exit; missing in: %s" % ", ".join(missing))
