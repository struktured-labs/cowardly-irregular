extends GutTest

## Every AreaTransition target_map must resolve to a real destination.
##
## THE GAP THIS CLOSES: AreaTransition.gd validates `target_map == ""` and
## nothing else. A typo'd but non-empty id passes, reaches GameLoop's map
## dispatch, misses every arm, and hits the default:
##     _:  exploration_scene = OverworldSceneRes.instantiate()
## So a mistyped door does NOT fade to nothing — it silently dumps the
## player on the overworld. No warning, no error. It LOOKS like it worked,
## which is worse than the empty-target failure it's siblings with.
##
## The existing transition tests check GEOMETRY, not identity — a typo
## passes all of them (it has a reachable cell and non-zero collision, and
## the interior-exit test only checks spawn registration).
##
## The id set is DERIVED from the dispatch, never copied. A pinned list
## would be a second source that drifts the moment someone adds a village.

const GAMELOOP := "res://src/GameLoop.gd"

## Resolved outside the dispatch (GameLoop.gd:4272 handles it before the match).
const SENTINEL_TARGETS := ["village_return"]


## The canonical destination set: GameLoop's map dispatch IS the registry,
## because it is the only thing that turns a map_id into a scene.
func _dispatch_ids() -> Array:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var start := src.find("match _current_map_id:")
	assert_gt(start, 0, "the map dispatch still exists")
	# Bound the scan at the default arm — everything after it is other code.
	var end := src.find("\n\t\t_:", start)
	assert_gt(end, start, "the dispatch still has a default arm")
	var block := src.substr(start, end - start)
	var ids: Array = []
	for m in RegEx.create_from_string("\"([a-z0-9_]+)\"\\s*:").search_all(block):
		ids.append(m.get_string(1))
	return ids


## Every target_map assigned anywhere in src/, with the file that set it.
func _assigned_targets() -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("target_map\\s*=\\s*\"([^\"]+)\"")
	for path in _gd_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			out.append({"id": m.get_string(1), "file": path.get_file()})
	return out


func _gd_files(root: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [root, entry]
		if dir.current_is_dir():
			found.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Positive control FIRST. A scan that silently found nothing would make
## every assertion below vacuously true — the failure mode that lets a
## ratchet stay green over a dead feature.
func test_the_scan_actually_finds_things() -> void:
	var ids := _dispatch_ids()
	var targets := _assigned_targets()
	assert_gt(ids.size(), 50,
		"dispatch parse must find the real arms — a broken regex here makes the whole file vacuous")
	assert_gt(targets.size(), 10,
		"target scan must find real assignments — zero targets would pass every test below for free")
	assert_true("overworld" in ids, "a known-present arm resolves")
	assert_false("definitely_not_a_map" in ids, "a known-absent id does not")


## THE RATCHET. A typo'd door silently teleports the player to the overworld.
func test_every_transition_target_resolves_to_a_real_destination() -> void:
	var ids := _dispatch_ids()
	var unresolvable: Array = []
	for t in _assigned_targets():
		var id: String = t["id"]
		if id in ids or id in SENTINEL_TARGETS:
			continue
		unresolvable.append("%s (set in %s)" % [id, t["file"]])
	assert_eq(unresolvable, [],
		"every target_map must appear in GameLoop's dispatch — an id that misses every arm falls to the default and dumps the player on the overworld with no warning")


## The default arm is load-bearing for this bug's severity: it is why a typo
## presents as "wrong place" rather than "nothing happened". If someone ever
## makes it warn or error, this test should be revisited, not silently kept.
func test_the_default_arm_is_still_the_silent_overworld_fallback() -> void:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var at := src.find("match _current_map_id:")
	var arm := src.find("\n\t\t_:", at)
	assert_gt(arm, at, "default arm present")
	var tail: String = src.substr(arm, 400)
	assert_true(tail.contains("OverworldSceneRes.instantiate()"),
		"default still falls back to the overworld — the reason an unresolvable id is invisible rather than fatal")
