extends GutTest

## An examine that describes a prop its village already draws is read beside that prop, not at an offset from the spawn (main 24242, census group B).

const BV_PATH := "res://src/maps/villages/BaseVillage.gd"
const VP := preload("res://src/exploration/VillageProp.gd")
const EXAMINES := "res://data/examine_texts.json"
const TILE := 32
const N4: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## In front of or beside a footprint cell; never behind it, where the prop's art grows up over the readable.
const BESIDE: Array = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]


## Read at runtime: a class_name preload makes get_script_constant_map() a parse-time static call, which is a parse error.
func _bv_consts() -> Dictionary:
	return (load(BV_PATH) as GDScript).get_script_constant_map()


func _described() -> Dictionary:
	return _bv_consts().get("_EXAMINE_DESCRIBES", {})


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


## Census group B's two door anchors: the incident board and the threshold sign are read just beside the door they describe.
func test_each_door_examine_stands_beside_its_door() -> void:
	var by_door: Dictionary = _bv_consts().get("_EXAMINE_BESIDE_DOOR", {})
	assert_gt(by_door.size(), 0, "CONTROL: BaseVillage._EXAMINE_BESIDE_DOOR must name at least one examine")
	var pack := _pack()
	var checked := 0
	for id in by_door:
		var scene := str((pack.get(id, {}) as Dictionary).get("scene", ""))
		assert_true(ResourceLoader.exists(_script_for(scene)), "CONTROL: %s's village script %s exists" % [id, _script_for(scene)])
		if not ResourceLoader.exists(_script_for(scene)):
			continue
		var v: Node = await _village(_script_for(scene))
		var door: Node = v.buildings.get_node_or_null(str(by_door[id]))
		assert_not_null(door, "CONTROL: %s builds the door %s that %s describes" % [scene, by_door[id], id])
		var ex: Node2D = v.npcs.get_node_or_null("Examine_" + str(id))
		assert_not_null(ex, "%s placed no readable for %s" % [scene, id])
		if door == null or ex == null:
			continue
		var box: Array = v._door_box_cells(door)
		assert_gt(box.size(), 0, "CONTROL: %s's trigger box covers some cells" % by_door[id])
		var at := _cell(ex)
		assert_false(box.has(at), "%s at %s stands inside %s's trigger %s, so a press there is contested" % [id, str(at), by_door[id], str(box)])
		var touches := false
		for c in box:
			for d in N4:
				touches = touches or (c + d == at)
		assert_true(touches, "%s is read at %s, not beside %s's approach %s" % [id, str(at), by_door[id], str(box)])
		assert_true(_reach(v).has(at), "%s at %s cannot be walked to from %s's arrival spawn" % [id, str(at), scene])
		checked += 1
	assert_eq(checked, by_door.size(), "every door examine was judged, not skipped")


## Village examines whose object no village draws yet (ruling 24242): each names what it waits for. Anchor one and it must leave this list.
const AWAITING := {
	"brasston_clocktower_plaque": "ruling: Brasston has a Clockwork Loft, not a clocktower",
	"brasston_redundancy_index": "ruling: a card-catalogue drawer, better moved indoors",
	"eldertree_gravestone": "a GRAVESTONE prop",
	"frosthold_cairn": "a CAIRN prop",
	"harmonia_statue": "a STATUE prop",
	"ironhaven_furnace_log": "a FURNACE prop",
	"node_prime_sticky": "a TERMINAL prop (the note is on its monitor)",
	"node_prime_terminal": "a TERMINAL prop",
	"vertex_monolith": "a MONOLITH prop",
}
## Anchored by a village's own _examine_anchor_cell override rather than a BaseVillage table.
const BY_OVERRIDE := {"harmonia_well": "res://src/maps/villages/HarmoniaVillage.gd"}


func test_every_village_examine_is_anchored_or_says_what_it_waits_for() -> void:
	var by_prop := _described()
	var by_door: Dictionary = _bv_consts().get("_EXAMINE_BESIDE_DOOR", {})
	assert_gt(by_prop.size() + by_door.size(), 0, "CONTROL: the anchor tables must be read")
	for id in BY_OVERRIDE:
		var src := FileAccess.get_file_as_string(BY_OVERRIDE[id])
		assert_true(src.contains("func _examine_anchor_cell") and src.contains('"%s"' % id), "%s's override no longer names %s" % [BY_OVERRIDE[id], id])
	var pack := _pack()
	var village := 0
	for id in pack:
		if not str((pack[id] as Dictionary).get("scene", "")).ends_with("_village"):
			continue
		village += 1
		var anchored: bool = by_prop.has(id) or by_door.has(id) or BY_OVERRIDE.has(id)
		assert_true(anchored or AWAITING.has(id), "%s is read at an offset from the spawn: anchor it beside what it describes, or add it to AWAITING with what it needs" % id)
		assert_false(anchored and AWAITING.has(id), "%s is anchored now: take it off AWAITING" % id)
	assert_gt(village, 0, "CONTROL: the pack has village examines")
	for id in AWAITING:
		assert_true(pack.has(id), "AWAITING names %s, which is not in the examine pack" % id)
