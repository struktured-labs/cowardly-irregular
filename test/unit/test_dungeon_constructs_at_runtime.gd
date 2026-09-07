extends GutTest

## Every dungeon must BUILD, and restore a legal floor while doing it.
##
## Completes the construction sweep: of 57 scripts under
## src/maps/{villages,interiors,dungeons}, 39 were never constructed as a node by
## any test — 12 of them dungeons, including all four dragon caves, Whispering
## Cave and Castle Harmonia. Every `load()` of a map scene in test/ names a
## hardcoded class path, so no generic sweep supplies that coverage.
##
## Safe to construct: `_ready` runs `_setup_scene()` + `_load_boss_state()`, and
## every `battle_triggered.emit` sits in a trigger handler (DragonCave:528/751,
## WhisperingCave:613/739), not in the build path.
##
## The floor-restore invariant is the runtime-only part. DragonCave._ready reads
## `<cave_id>_floor` out of game_constants and clamps it, and tick 153 added the
## rule that a defeated boss resets you to floor 1 rather than dropping you into
## the depopulated arena you last won in. Both are conditional writes to a
## member no source scan can evaluate — only construction shows the result.

const DUNGEON_DIR := "res://src/maps/dungeons"

var _saved_constants: Dictionary = {}


## Dungeons READ game_constants for saved floors. Snapshot the whole dict so a
## build cannot leak floor state into another test — and restore by value, since
## Dictionary assignment is by reference.
func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


## Class names some OTHER dungeon extends are bases, not rooms — derived, so a
## future base is excluded on arrival rather than silenced by a skip list later.
func _base_class_names() -> Dictionary:
	var bases := {}
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return bases
	var re := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var m := re.search(FileAccess.get_file_as_string(DUNGEON_DIR + "/" + f))
		if m != null:
			bases[m.get_string(1)] = true
	return bases


func _dungeon_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return out
	var bases := _base_class_names()
	for f in dir.get_files():
		if f.ends_with(".gd") and not bases.has(f.get_basename()):
			out.append(f)
	out.sort()
	return out


func _painted_cells(root: Node) -> int:
	var n := 0
	for child in root.get_children():
		if child is TileMapLayer:
			n += (child as TileMapLayer).get_used_cells().size()
		elif child.has_method("get_used_cells"):
			n += child.get_used_cells().size()
		n += _painted_cells(child)
	return n


func test_every_dungeon_builds_and_paints_its_floor() -> void:
	var files := _dungeon_scripts()
	assert_gt(files.size(), 0, "found dungeon scripts — zero would pass this file for free")
	var built := 0
	var non_node := 0
	var offenders: Array = []
	for f in files:
		var script = load(DUNGEON_DIR + "/" + f)
		assert_not_null(script, "%s loads as a script" % f)
		if script == null:
			continue
		var d = script.new()
		if d == null:
			offenders.append("%s: .new() returned null" % f)
			continue
		# A room is a scene ROOT; an Area2D in this directory is a trigger
		# component (BossTrigger). Discriminated by TYPE, not by name — and not
		# by "has total_floors", which would wrongly drop WhisperingCave.
		if not (d is Node) or d is Area2D:
			non_node += 1
			d.free()
			continue
		_isolated_viewport().add_child(d)
		await get_tree().process_frame
		built += 1
		if _painted_cells(d) == 0:
			offenders.append("%s: built with ZERO painted cells" % f)

	assert_eq(built + non_node, files.size(),
		"accounted for %d of %d dungeon scripts (%d built, %d non-Node) — the difference was skipped in silence" % [
			built + non_node, files.size(), built, non_node])
	assert_gt(built, 0, "built at least one dungeon")
	assert_true(offenders.is_empty(),
		"%d dungeon(s) built badly:\n  %s" % [offenders.size(), "\n  ".join(offenders)])


## A saved floor beyond the dungeon's depth must be clamped, not honoured. Source
## shows the guard; only a build shows what current_floor ends up as.
func test_a_corrupt_saved_floor_never_survives_the_build() -> void:
	var checked := 0
	var offenders: Array = []
	for f in _dungeon_scripts():
		var probe = load(DUNGEON_DIR + "/" + f).new()
		if probe == null or not (probe is Node) or not ("cave_id" in probe):
			if probe is Node:
				probe.free()
			continue
		var cid: String = str(probe.cave_id)
		probe.free()
		if cid == "":
			continue
		# Poison the saved floor, then build and see what survives.
		GameState.game_constants[cid + "_floor"] = 9999
		var d = load(DUNGEON_DIR + "/" + f).new()
		_isolated_viewport().add_child(d)
		await get_tree().process_frame
		checked += 1
		var cur: int = int(d.current_floor)
		var total: int = int(d.total_floors)
		if cur < 1 or cur > total:
			offenders.append("%s: saved floor 9999 produced current_floor=%d (total_floors=%d)" % [f, cur, total])

	assert_gt(checked, 0,
		"probed at least one dungeon with a cave_id — zero means this test asserted nothing")
	assert_true(offenders.is_empty(),
		"%d dungeon(s) honoured an out-of-range saved floor:\n  %s" % [
			offenders.size(), "\n  ".join(offenders)])
