extends GutTest

## An examine that describes a prop its village already draws is read beside that prop, not at an offset from the spawn (main 24242, census group B).

const BV := preload("res://src/maps/villages/BaseVillage.gd")
const VP := preload("res://src/exploration/VillageProp.gd")
const EXAMINES := "res://data/examine_texts.json"
const TILE := 32
const N4: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## In front of or beside a footprint cell; never behind it, where the prop's art grows up over the readable.
const BESIDE: Array = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]


func _described() -> Dictionary:
	return BV.get_script_constant_map().get("_EXAMINE_DESCRIBES", {})


func _pack() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXAMINES))
	return (parsed as Dictionary).get("examines", {}) if parsed is Dictionary else {}


func _script_for(scene: String) -> String:
	return "res://src/maps/villages/%s.gd" % scene.to_pascal_case()


func _village(path: String) -> Node:
	var v: Node = load(path).new()
	add_child_autofree(v)
	await get_tree().process_frame
	return v


func _cell(n: Node2D) -> Vector2i:
	return Vector2i(floori(n.position.x / TILE), floori(n.position.y / TILE))


func _base(p: Node2D) -> Vector2i:
	return Vector2i(floori(p.position.x / TILE), roundi(p.position.y / TILE) - 1)


## Every cell reachable on foot from the arrival spawn.
func _reach(v: Node) -> Dictionary:
	var start := Vector2i(v.spawn_points["default"] / float(TILE))
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in N4:
			var n: Vector2i = c + d
			if not seen.has(n) and v._is_cell_walkable(n):
				seen[n] = true
				queue.append(n)
	return seen


func test_the_described_roster_is_real() -> void:
	var described := _described()
	assert_gt(described.size(), 0, "CONTROL: BaseVillage._EXAMINE_DESCRIBES must name at least one examine")
	var pack := _pack()
	for id in described:
		assert_true(pack.has(id), "%s is in _EXAMINE_DESCRIBES but not in %s" % [id, EXAMINES])
		var scene := str((pack.get(id, {}) as Dictionary).get("scene", ""))
		assert_true(scene.ends_with("_village"), "%s must belong to a village, not '%s'" % [id, scene])
		assert_true(ResourceLoader.exists(_script_for(scene)), "CONTROL: %s's village script %s exists" % [id, _script_for(scene)])


func test_each_described_examine_stands_beside_a_prop_of_its_kind() -> void:
	var described := _described()
	var pack := _pack()
	var checked := 0
	for id in described:
		var scene := str((pack.get(id, {}) as Dictionary).get("scene", ""))
		if not ResourceLoader.exists(_script_for(scene)):
			continue
		var v: Node = await _village(_script_for(scene))
		var kind: int = described[id]
		var feet: Array = []
		for p in v.props.get_children():
			if p.get("kind") == kind:
				for f in p.footprint_cells(_base(p)):
					feet.append(f)
		assert_gt(feet.size(), 0, "CONTROL: %s draws a %s for %s to describe" % [scene, VP.Kind.keys()[kind], id])
		var ex: Node2D = v.npcs.get_node_or_null("Examine_" + str(id))
		assert_not_null(ex, "%s placed no readable for %s" % [scene, id])
		if ex == null or feet.is_empty():
			continue
		var at := _cell(ex)
		var beside := false
		for f in feet:
			for s in BESIDE:
				beside = beside or (f + s == at)
		assert_true(beside, "%s is read at %s, not in front of or beside any of %s's %s cells %s" % [
			id, str(at), scene, VP.Kind.keys()[kind], str(feet)])
		assert_true(_reach(v).has(at), "%s at %s cannot be walked to from %s's arrival spawn" % [id, str(at), scene])
		checked += 1
	assert_eq(checked, described.size(), "every described examine was judged, not skipped")
