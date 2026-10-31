extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

## struktured, 2026-10-30: "villagers no longer walk" in Eldertree. It was never a regression -- only Harmonia
## had ever called _create_wandering_npc. Every other village was a diorama. Walkers now take their lines from
## the village's own ground (BaseVillage._walker_runs), so a map edit cannot strand one inside a wall.

const VILLAGE_DIR := "res://src/maps/villages"
const MIN_WALKERS := 2
## The ONE exemption, with its measurement: every floor island in Vertex is occupied, so no line clears it.
const NO_ROOM_TO_WALK := {"VertexVillage.gd": "shops, a door, four NPCs and three masterites fill its islands"}

var _built: Array = []


## Built once and shared: eleven villages per arm is most of this file's runtime.
func _ensure_built() -> void:
	if not _built.is_empty():
		return
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child(vp)
		var village = load(path).new()
		vp.add_child(village)
		_built.append({"path": path, "village": village, "vp": vp})
	await get_tree().physics_frame
	await get_tree().process_frame


func after_all() -> void:
	for b in _built:
		(b["vp"] as Node).queue_free()
	_built.clear()
	SoundState.restore()


func _walkers(v: Node, ambient_only: bool) -> Array:
	var out: Array = []
	for n in v.npcs.get_children():
		if n is WanderingNPC and (not ambient_only or String(n.name).begins_with("Walker_")):
			out.append(n)
	return out


func test_every_village_has_people_walking() -> void:
	await _ensure_built()
	assert_gt(_built.size(), 10, "CONTROL: the walk built the villages (%d)" % _built.size())
	for b in _built:
		var n: int = _walkers(b["village"], false).size()
		var asked: int = b["village"]._get_ambient_walkers().size()
		assert_eq(_walkers(b["village"], true).size(), asked, "%s asked for %d walker(s) and its ground fit fewer" % [b["path"].get_file(), asked])
		if NO_ROOM_TO_WALK.has(b["path"].get_file()):
			assert_eq(asked, 0, "%s is exempt as having no room, so it must not ask for walkers" % b["path"].get_file())
			continue
		assert_gte(n, MIN_WALKERS, "%s has %d walker(s): a town with nobody moving reads as a diorama" % [b["path"].get_file(), n])


func test_a_walkers_line_is_ground_it_can_walk() -> void:
	await _ensure_built()
	## Walkers lerp with no physics, so the LINE is the only thing keeping one out of a wall.
	var legs: int = 0
	for b in _built:
		var v = b["village"]
		for w in _walkers(v, true):
			var pts: Array[Vector2] = w.get_patrol()
			assert_eq(pts.size(), 2, "%s/%s has no line" % [b["path"].get_file(), w.name])
			if pts.size() < 2:
				continue
			assert_gte(pts[0].distance_to(pts[1]), float((v.WALKER_MIN_RUN - 1) * v.TILE_SIZE) - 0.5,
				"%s/%s walks a line shorter than a run: something clipped it" % [b["path"].get_file(), w.name])
			var steps: int = int(ceil(pts[0].distance_to(pts[1]) / (v.TILE_SIZE * 0.25)))
			var last: Vector2i = v._cell_of(pts[0])
			for s in range(steps + 1):
				var cell: Vector2i = v._cell_of(pts[0].lerp(pts[1], float(s) / float(steps)))
				assert_true(v._is_cell_walkable(cell), "%s/%s walks through %s" % [b["path"].get_file(), w.name, str(cell)])
				if cell != last:
					assert_true(v._can_step(last, cell), "%s/%s steps %s -> %s off a ledge" % [b["path"].get_file(), w.name, str(last), str(cell)])
				last = cell
			legs += 1
	assert_gt(legs, 15, "CONTROL: ambient walkers were found and walked (%d)" % legs)


func test_placement_validation_never_had_to_move_a_walker() -> void:
	await _ensure_built()
	## The derivation is the authority; if the sweep had to clip a line, the derivation and the sweep disagree.
	var judged: int = 0
	for b in _built:
		var v = b["village"]
		for w in _walkers(v, true):
			var want: Array = v.ambient_walker_lines.get(String(w.name), [])
			assert_eq(want.size(), 2, "%s/%s has no recorded line" % [b["path"].get_file(), w.name])
			var pts: Array[Vector2] = w.get_patrol()
			assert_eq(Array(pts), Array(want), "%s/%s was moved by placement validation" % [b["path"].get_file(), w.name])
			judged += 1
	assert_gt(judged, 15, "CONTROL: walkers were judged (%d)" % judged)


func _zone(door: Node2D) -> Rect2:
	for c in door.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var size: Vector2 = (c.shape as RectangleShape2D).size
			return Rect2(door.global_position + c.position - size * 0.5, size)
	return Rect2()


func test_no_walker_crosses_a_door_or_a_gate() -> void:
	await _ensure_built()
	## A walker in a door's zone competes with the door for the press -- the same defect Scholar Fynn was.
	var zones: int = 0
	for b in _built:
		var v = b["village"]
		var rects: Array = []
		for d in v.buildings.get_children():
			if d is AreaTransition and d.get("require_interaction") == true:
				var z := _zone(d)
				if z.has_area():
					rects.append(z.grow(8.0))
		var gate := v.find_child("Exit", true, false) as Node2D
		if gate != null:
			## The same box test_a_village_exit_sits_on_its_exit keeps clear, so a walker never paces through a gate.
			rects.append(Rect2(gate.global_position + Vector2(-44.0, -76.0), Vector2(88.0, 80.0)))
		zones += rects.size()
		for w in _walkers(v, true):
			var pts: Array[Vector2] = w.get_patrol()
			for s in range(17):
				var p: Vector2 = pts[0].lerp(pts[1], s / 16.0) + v.global_position
				for r in rects:
					assert_false(r.has_point(p), "%s/%s walks through a door's zone at %s" % [b["path"].get_file(), w.name, str(p / 32.0)])
	assert_gt(zones, 15, "CONTROL: door zones were found (%d)" % zones)
