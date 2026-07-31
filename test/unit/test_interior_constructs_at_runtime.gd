extends GutTest

## Every interior must actually BUILD its exit — not merely declare one in source.
##
## THE RUNG THIS ADDS. test_interior_exit_spawn_integrity greps
## `exit.target_map = "..."` / `exit.target_spawn = "..."` out of the source and
## checks the spawn key against the target village. That is a text join: it
## proves the assignment is WRITTEN, never that the AreaTransition node exists
## after `_ready()`. An interior whose `_setup_transitions()` returns early —
## a guard that flips, a load() that fails, an exception partway — still passes
## every source scan and traps the player in a room with no door.
##
## Measured 2026-07-30: of 57 scripts under src/maps/{villages,interiors,dungeons},
## 39 are never constructed as a node by any test, 16 of them interiors. Every
## `load()` of a map scene in test/ names a hardcoded class path, so no generic
## sweep is supplying that coverage.

const INTERIOR_DIR := "res://src/maps/interiors"


## Input and the default World2D both leak across GUT tests (CLAUDE.md pitfall);
## an interior builds Area2Ds and a player body, so give each its own world.
func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


## Class names that some OTHER interior extends — those are bases, not rooms.
## DERIVED from the sources rather than hand-listed, so a future base class is
## excluded on arrival instead of being reported as a doorless room forever
## (and, worse, eventually silenced by adding it to a skip list).
func _base_class_names() -> Dictionary:
	var bases := {}
	var dir := DirAccess.open(INTERIOR_DIR)
	if dir == null:
		return bases
	var re := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var m := re.search(FileAccess.get_file_as_string(INTERIOR_DIR + "/" + f))
		if m != null:
			bases[m.get_string(1)] = true
	return bases


## Rooms: every interior script that is neither a base class nor a non-Node
## helper. `RefCounted` utilities (InteriorPlacementSweep) are excluded by the
## Node check at construction, not by name.
func _interior_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(INTERIOR_DIR)
	if dir == null:
		return out
	var bases := _base_class_names()
	for f in dir.get_files():
		if f.ends_with(".gd") and not bases.has(f.get_basename()):
			out.append(f)
	out.sort()
	return out


## Any descendant carrying a non-empty `target_map` — found by PROPERTY, not by
## class name or node name, so renaming AreaTransition or the "Exit" node does
## not silently empty this audit.
func _exit_targets(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if "target_map" in child and str(child.target_map) != "":
			out.append(str(child.target_map))
		out.append_array(_exit_targets(child))
	return out


func test_every_interior_builds_a_reachable_exit() -> void:
	var files := _interior_scripts()
	assert_gt(files.size(), 0, "found interior scripts — zero would pass this file for free")
	var built := 0
	var non_node := 0
	var doorless: Array = []
	for f in files:
		var script = load(INTERIOR_DIR + "/" + f)
		assert_not_null(script, "%s loads as a script" % f)
		if script == null:
			continue
		var room = script.new()
		if room == null:
			doorless.append("%s: .new() returned null" % f)
			continue
		# A RefCounted helper in this directory is not a room; skip by TYPE.
		if not (room is Node):
			non_node += 1
			continue
		_isolated_viewport().add_child(room)
		await get_tree().process_frame
		built += 1
		var targets := _exit_targets(room)
		if targets.is_empty():
			doorless.append("%s: built with NO exit carrying a target_map — the player cannot leave" % f)

	assert_eq(built + non_node, files.size(),
		"accounted for %d of %d interior scripts (%d built, %d non-Node helpers) — the difference returned null and was skipped in silence" % [
			built + non_node, files.size(), built, non_node])
	assert_gt(built, 0, "built at least one room — zero rooms would pass the doorless check for free")
	assert_true(doorless.is_empty(),
		"%d interior(s) built without a working exit:\n  %s" % [doorless.size(), "\n  ".join(doorless)])


## The runtime half of the text join: whatever target the built exit points at
## must be the SAME target the source declares. A drift between them means the
## source-level ratchet is validating a string the game never uses.
func test_built_exit_targets_match_what_the_source_declares() -> void:
	var re := RegEx.create_from_string("\\w+\\.target_map\\s*=\\s*\"(\\w+)\"")
	var mismatches: Array = []
	var compared := 0
	for f in _interior_scripts():
		var src: String = FileAccess.get_file_as_string(INTERIOR_DIR + "/" + f)
		var declared := {}
		for m in re.search_all(src):
			declared[m.get_string(1)] = true
		if declared.is_empty():
			continue
		var room = load(INTERIOR_DIR + "/" + f).new()
		if room == null or not (room is Node):
			continue
		_isolated_viewport().add_child(room)
		await get_tree().process_frame
		for t in _exit_targets(room):
			compared += 1
			if not declared.has(t):
				mismatches.append("%s: built exit targets \"%s\", source declares only %s" % [
					f, t, str(declared.keys())])
	assert_gt(compared, 0,
		"compared at least one built exit against its source — zero means the runtime scan found nothing and this test is vacuous")
	assert_true(mismatches.is_empty(),
		"%d built exit(s) disagree with their source declaration:\n  %s" % [
			mismatches.size(), "\n  ".join(mismatches)])
