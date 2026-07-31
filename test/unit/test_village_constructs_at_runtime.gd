extends GutTest

## Every village must actually BUILD — not merely parse.
##
## THE RUNG THIS ADDS. The village guards that exist all read source TEXT:
##   test_village_placement_walkability   parses the map_data literal
##   test_village_npc_connectivity        flood-fills the parsed grid
##   test_interior_exit_spawn_integrity   greps spawn_points["..."] literals
## None of them ever runs `_ready()`. Measured 2026-07-30: of 57 scripts under
## src/maps/{villages,interiors,dungeons}, 39 are never constructed as a node by
## any test — including all 11 villages and every dragon cave. Every `load()` of
## a map scene in test/ names a hardcoded class, so there is no generic sweep
## hiding the coverage.
##
## What that misses is the whole silent-failure class this project cares about:
## a village whose `_generate_map()` returns early, whose spawn_points dict never
## gets populated, or whose `_ready` aborts partway leaves a scene that looks
## fine to a text scan and drops the player at a fallback coordinate in game.
## Source says spawn_points["default"] is ASSIGNED; only construction says it is
## POPULATED.

const VILLAGE_DIR := "res://src/maps/villages"


## Godot's Input singleton and the default World2D both leak across GUT tests
## (CLAUDE.md pitfall, 24px drift measured 2026-07-18). A village builds bodies
## and Area2Ds, so give each one its own world rather than the shared root.
func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


func _village_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(VILLAGE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "BaseVillage.gd":
			out.append(f)
	out.sort()
	return out


func test_every_village_builds_and_populates_its_spawn_points() -> void:
	var files := _village_scripts()
	assert_gt(files.size(), 0, "found village scripts — zero would pass this file for free")
	var built := 0
	var offenders: Array = []
	for f in files:
		var script = load(VILLAGE_DIR + "/" + f)
		assert_not_null(script, "%s loads as a script" % f)
		if script == null:
			continue
		var v = script.new()
		if v == null:
			offenders.append("%s: .new() returned null" % f)
			continue
		_isolated_viewport().add_child(v)
		await get_tree().process_frame
		built += 1

		# `spawn_points` is what every interior exit and every scene transition
		# resolves against. Source-level guards prove the key is WRITTEN; this
		# proves the dict is non-empty once the scene has actually run.
		if not ("spawn_points" in v):
			offenders.append("%s: no spawn_points member after build" % f)
		elif (v.spawn_points as Dictionary).is_empty():
			offenders.append("%s: spawn_points is EMPTY after _ready — every arrival lands at the fallback" % f)
		elif not (v.spawn_points as Dictionary).has("default"):
			offenders.append("%s: spawn_points has no \"default\" — village_return from any inn/shop/blacksmith lands at the fallback" % f)
		v.queue_free()

	assert_eq(built, files.size(),
		"constructed %d of %d village scripts — the difference returned null and was skipped" % [built, files.size()])
	assert_true(offenders.is_empty(),
		"%d village(s) built but did not populate spawn_points:\n  %s" % [
			offenders.size(), "\n  ".join(offenders)])


## The runtime complement to the parsed-grid audits: a village that builds must
## put real tiles down. A `_generate_map` that returns early leaves an empty
## TileMapLayer that no source scan can distinguish from a full one.
func test_every_village_lays_down_tiles() -> void:
	var offenders: Array = []
	var checked := 0
	for f in _village_scripts():
		var v = load(VILLAGE_DIR + "/" + f).new()
		if v == null:
			continue
		_isolated_viewport().add_child(v)
		await get_tree().process_frame
		var cells := _painted_cells(v)
		checked += 1
		if cells == 0:
			offenders.append("%s: built with ZERO painted cells" % f)
		v.queue_free()
	assert_gt(checked, 0, "checked at least one village")
	assert_true(offenders.is_empty(),
		"%d village(s) built an empty map:\n  %s" % [offenders.size(), "\n  ".join(offenders)])


## Total used cells across every TileMapLayer/TileMap descendant.
func _painted_cells(root: Node) -> int:
	var n := 0
	for child in root.get_children():
		if child is TileMapLayer:
			n += (child as TileMapLayer).get_used_cells().size()
		elif child.has_method("get_used_cells"):
			n += child.get_used_cells().size()
		n += _painted_cells(child)
	return n
