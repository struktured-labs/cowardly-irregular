extends GutTest

## A door to a map id with no dispatch arm SILENTLY DUMPS YOU ON THE OVERWORLD.
##
## GameLoop._start_exploration builds the scene with `match _current_map_id:` and its default arm is
## `exploration_scene = OverworldSceneRes.instantiate()`. So a typo'd or removed target does not
## crash and does not black-screen: the transition plays its fade, and the player arrives on the
## world map. That reads as a door that worked and teleported you somewhere odd, which is why it
## could sit for a long time.
##
## The other direction is quieter still: a map id with an arm that no door names is authored content
## nobody can reach. Nothing renders it, so nothing looks wrong. Same shape as the three village
## walkways sealed by their own props -- an empty result is what unreachable looks like.
##
## WHY THIS IS A SOURCE-LEVEL LEDGER AND SAYS SO. Match arms cannot be enumerated at runtime, so both
## sides are parsed from source. That is legitimate here because the property IS an agreement between
## two lists of literals -- but it means this pins REFERENCE reachability, not PLAY reachability. A
## door that exists behind a story flag nobody sets still counts as routed. Do not read a green here
## as "every map can be visited".
##
## TWO INSTRUMENT BUGS WORTH LEAVING IN THE RECORD, both caught by this test before it certified
## anything, and both producing the SAME false finding -- "entrance", which is not a map id at all
## but the third argument of `_add_area_transition(name, target_map, target_spawn, ...)`:
##   1. Every source file is concatenated into one blob, and `[^"]*` does not exclude newlines, so a
##      gap pattern paired an opening quote in one call with a quote several lines later in another.
##      The classes are `[^"\n]*` now.
##   2. The VillageInn definer was `interior_target[^"]*"(...)"`, which matched the USE
##      `transition_triggered.emit(interior_target, "entrance")` and not just the declaration. It is
##      anchored on `var` and `=` now.
## Fixing the first did not fix the finding, which is the useful part: one symptom, two independent
## causes, and stopping at the first plausible one would have left the second in place.
##
## THE CONTROL THAT MATTERS IS THE DEFINER COUNT, not the orphan count. Routes are authored through
## seven different helpers, and the audit that produced this test reported 14 false orphans on its
## first run and 8 on its second, purely because two of those helpers were not in the list yet. A
## definer that matches nothing has silently left the corpus and every count downstream is free, so
## each one must still match at least one route or this test fails before it reports anything.

const GAMELOOP := "res://src/GameLoop.gd"
const SRC_DIRS := ["res://src/exploration", "res://src/maps/villages", "res://src/maps/dungeons", "res://src/maps/interiors", "res://src"]

## Resolved before the dispatch is reached (GameLoop: `if target_map == "village_return"`), so it is
## never expected to have an arm of its own.
const RESOLVED_EARLY := ["village_return"]

## Each entry is one authoring route. The `min` is a floor, not the current count -- it exists so a
## helper that gets renamed fails loudly instead of quietly contributing nothing.
const ROUTE_DEFINERS := [
	{"name": "target_map =", "rx": "target_map\\s*=\\s*\"([a-z0-9_]+)\"", "min": 20},
	{"name": "_add_interior_door", "rx": "_add_interior_door\\(\\s*\"[^\"\n]*\"\\s*,\\s*\"([a-z0-9_]+)\"", "min": 10},
	{"name": "_add_area_transition", "rx": "_add_area_transition\\(\\s*\"[^\"\n]*\"\\s*,\\s*\"([a-z0-9_]+)\"", "min": 5},
	{"name": "transition_triggered.emit", "rx": "transition_triggered\\.emit\\(\"([a-z0-9_]+)\"", "min": 1},
	{"name": "VillageShop._interior_target", "rx": "return\\s+\"(shop_interior_[a-z_]+)\"", "min": 3},
	{"name": "VillageInn.interior_target", "rx": "var interior_target[^\"\n]*=\\s*\"([a-z0-9_]+)\"", "min": 1},
]


func _all_sources() -> Array:
	var out: Array = []
	var seen := {}
	for d in SRC_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd") and not seen.has(d + "/" + f):
				seen[d + "/" + f] = true
				out.append(d + "/" + f)
	return out


## The ids GameLoop can actually build, read from its own match block.
func _dispatched_ids() -> Array:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var start := src.find("match _current_map_id:")
	assert_gt(start, -1, "CONTROL: GameLoop's map dispatch was not found -- every list below is empty and every assertion free")
	if start < 0:
		return []
	# Bound at the next top-level func so a later match block cannot leak in.
	var stop := src.find("\nfunc ", start)
	var block: String = src.substr(start, (stop - start) if stop > start else -1)
	var rx := RegEx.new()
	rx.compile("(?m)^\\s+\"([a-z0-9_]+)\":\\s*$")
	var ids: Array = []
	for m in rx.search_all(block):
		var id: String = m.get_string(1)
		if not (id in ids):
			ids.append(id)
	ids.sort()
	return ids


func _routed_ids() -> Dictionary:
	var sources := _all_sources()
	assert_gt(sources.size(), 30, "CONTROL: only %d source files scanned for doors" % sources.size())
	var text := ""
	for f in sources:
		text += FileAccess.get_file_as_string(f) + "\n"

	var routed := {}
	var thin: Array = []
	for d in ROUTE_DEFINERS:
		var rx := RegEx.new()
		rx.compile(d["rx"])
		var hits := 0
		for m in rx.search_all(text):
			routed[m.get_string(1)] = true
			hits += 1
		if hits < int(d["min"]):
			thin.append("%s matched %d (floor %d)" % [d["name"], hits, int(d["min"])])
	assert_eq(thin, [],
		"a route definer stopped matching -- it was renamed or removed, and every id it used to contribute now reads as unreachable: %s" % str(thin))
	return routed


func test_no_door_leads_to_a_map_that_cannot_be_built() -> void:
	var dispatched := _dispatched_ids()
	assert_gt(dispatched.size(), 50, "CONTROL: only %d dispatch arms parsed (65 at time of writing)" % dispatched.size())
	var routed := _routed_ids()

	var nowhere: Array = []
	for id in routed:
		if not (id in dispatched) and not (id in RESOLVED_EARLY):
			nowhere.append(id)
	nowhere.sort()
	assert_eq(nowhere, [],
		"a door names a map id GameLoop cannot build -- the default arm loads the OVERWORLD, so the player is quietly teleported to the world map instead of anything failing: %s" % str(nowhere))


func test_every_buildable_map_has_a_door_to_it() -> void:
	var dispatched := _dispatched_ids()
	var routed := _routed_ids()

	var unreachable: Array = []
	for id in dispatched:
		if not routed.has(id):
			unreachable.append(id)
	assert_eq(unreachable, [],
		"a map GameLoop can build that nothing routes to -- authored content with no door, which renders as nothing being wrong: %s" % str(unreachable))


func test_the_ledger_can_see_a_fabricated_id() -> void:
	var dispatched := _dispatched_ids()
	assert_false("zzz_no_such_map" in dispatched,
		"CONTROL: a fabricated id must read as undispatched, or both comparisons above are vacuous")
	var routed := _routed_ids()
	assert_false(routed.has("zzz_no_such_map"),
		"CONTROL: a fabricated id must read as unrouted")
