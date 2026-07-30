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


## Magic tokens that never reach the dispatch because the transition entry
## point rewrites them first. DERIVED, not listed: the old hand-list held one
## id and a line-number citation, and by the time anyone re-read it the line
## had moved 41 lines. A new sentinel would have read as a typo and gone red
## on a correct change.
func _sentinel_targets() -> Array:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var start := src.find("func _on_area_transition(")
	assert_gt(start, 0, "the transition entry point still exists — every target_map arrives through it")
	var end := src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, end - start) if end > start else src.substr(start)
	var out: Array = []
	for m in RegEx.create_from_string("target_map\\s*==\\s*\"([a-z0-9_]+)\"").search_all(body):
		out.append(m.get_string(1))
	return out


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


## Every destination id assigned anywhere in src/, with the file that set it.
## Covers BOTH spellings: AreaTransition's `target_map` and VillageInn's
## `interior_target` @export. The latter is a separate door into the same
## dispatch — scanning only `target_map` leaves every village inn unguarded.
func _assigned_targets() -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?:target_map|interior_target)\\s*=\\s*\"([^\"]+)\"")
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
	# Cross-check the regex against the block's own shape rather than a magic
	# floor. `> 50` was a coincidental magnitude: it passes a parse that finds
	# 51 of 63 arms, and would refuse a correct dispatch that shrank.
	assert_eq(ids.size(), _arm_lines(),
		"the parse must capture EVERY quoted arm — a divergence means the dispatch grew a shape the regex cannot read (a multi-id arm captures only its first id, silently narrowing this ratchet)")
	assert_gt(_arm_lines(), 0, "the dispatch has arms at all")
	assert_gt(targets.size(), 10,
		"target scan must find real assignments — zero targets would pass every test below for free")
	assert_true("overworld" in ids, "a known-present arm resolves")
	assert_false("definitely_not_a_map" in ids, "a known-absent id does not")


## Independent count of the dispatch's arms — by INDENT, not by quoting. An
## earlier draft counted lines starting with a quote, which is the same
## property the capture regex keys on: an arm renamed to a constant would
## vanish from both and the counts would still agree. Arms sit at two tabs,
## their bodies at three, so indent is a property the regex cannot see.
func _arm_lines() -> int:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var start := src.find("match _current_map_id:")
	var end := src.find("\n\t\t_:", start)
	var n := 0
	for line in src.substr(start, end - start).split("\n"):
		if line.begins_with("\t\t") and not line.begins_with("\t\t\t") and line.strip_edges().ends_with(":"):
			n += 1
	return n


## A sentinel is by definition NOT a dispatch arm. If the derivation starts
## picking up ordinary comparisons the two sets overlap, and every overlap
## silently widens the ratchet's exemption.
func test_the_sentinel_derivation_resolves_and_stays_disjoint() -> void:
	var sentinels := _sentinel_targets()
	var ids := _dispatch_ids()
	assert_gt(sentinels.size(), 0,
		"at least one token is resolved before the dispatch — at zero, a real sentinel reads as a typo and this ratchet goes red on correct code")
	for s in sentinels:
		assert_false(s in ids,
			"'%s' is both a sentinel and a dispatch arm — the derivation is over-matching" % s)


## THE RATCHET. A typo'd door silently teleports the player to the overworld.
func test_every_transition_target_resolves_to_a_real_destination() -> void:
	var ids := _dispatch_ids()
	var unresolvable: Array = []
	for t in _assigned_targets():
		var id: String = t["id"]
		if id in ids or id in _sentinel_targets():
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
