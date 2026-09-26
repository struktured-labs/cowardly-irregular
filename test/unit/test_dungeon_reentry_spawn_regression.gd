extends GutTest

## Re-entering a dungeon opens the floor stored in `<cave_id>_floor`. Crystal warp
## leaves that key set (only the stairwell exit erases it), and a floor with no
## authored entrance used to spawn the player at a fixed tile: (10, 12) in every
## DragonCave, (12, 14) in Whispering Cave.
##
## On Lightning floor 4 and Shadow floor 4 — the penultimate floors, which are
## where the pre-boss save crystal is — that tile is solid wall, and the four
## tiles meeting at its corner are wall too, so the 4px body has nowhere to be
## pushed. On several other unauthored floors the same tile is the up-stair
## sensor, so the first physics frame climbs a floor with no input.
##
## The floor KEY is what `_ready` reads. `current_floor` set before the cave
## enters the tree is the write `_ready` replaces; the key has to be in place
## first. The sweep below generates each unauthored floor after `_ready`.

const DUNGEON_DIR := "res://src/maps/dungeons"
const TILE := 32

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func _scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(f)
	out.sort()
	return out


func _char_at(rows: Array, x: int, y: int, map_w: int, map_h: int) -> String:
	if x < 0 or y < 0 or x >= map_w or y >= map_h or y >= rows.size():
		return "M"
	var row: String = rows[y]
	if x >= row.length():
		return "M"
	return row[x]


func _blocked(ch: String) -> bool:
	return ch == "M" or ch == "l"


func _last_stairs(rows: Array, map_w: int, map_h: int) -> Array:
	var last := {}
	for y in range(mini(map_h, rows.size())):
		var row: String = rows[y]
		for x in range(mini(map_w, row.length())):
			if row[x] == "U" or row[x] == "D":
				last[row[x]] = Vector2i(x, y)
	return last.values()


func _in_stair(px: float, py: float, stairs: Array) -> bool:
	var half := InteractGeometry.STAIRS_BOX.x * 0.5
	for s in stairs:
		var centre := Vector2(s) * TILE + Vector2(TILE, TILE) * 0.5
		if absf(px - centre.x) < half and absf(py - centre.y) < half:
			return true
	return false


func _reaches(rows: Array, start: Vector2i, stairs: Array, map_w: int, map_h: int) -> bool:
	if stairs.is_empty():
		return not _blocked(_char_at(rows, start.x, start.y, map_w, map_h))
	var want := {}
	for s in stairs:
		want[s] = true
	if want.has(start):
		return true
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in dirs:
			var n: Vector2i = cur + d
			if seen.has(n) or _blocked(_char_at(rows, n.x, n.y, map_w, map_h)):
				continue
			if want.has(n):
				return true
			seen[n] = true
			stack.append(n)
	return false


func _fallback_for(cave) -> Vector2:
	var path := str(cave.get_script().resource_path)
	if path.ends_with("WhisperingCave.gd"):
		return Vector2(12, 14)
	return Vector2(10, 12)


func test_the_sweep_covers_the_crystal_floors() -> void:
	var saw := {}
	for f in _scripts():
		var cave = load(DUNGEON_DIR + "/" + f).new()
		if cave == null or not (cave is Node) or cave is Area2D or not ("floor_layouts" in cave):
			if cave is Node:
				cave.free()
			continue
		if (cave.floor_layouts as Dictionary).is_empty():
			cave.free()
			continue
		for floor_num in cave.floor_layouts:
			var spec: Dictionary = cave.floor_spawn_points.get(floor_num, {})
			if not spec.has("entrance"):
				saw["%s:%s" % [f, str(floor_num)]] = true
		cave.free()
	assert_gt(saw.size(), 10, "unauthored floors found — a tiny set means the directory scan missed the caves")
	assert_true(saw.has("LightningDragonCave.gd:4"), "lightning floor 4 is an unauthored crystal floor — the sweep must include it")
	assert_true(saw.has("ShadowDragonCave.gd:4"), "shadow floor 4 is an unauthored crystal floor — the sweep must include it")
	assert_true(saw.has("WhisperingCave.gd:5"), "whispering floor 5 has no entrance — the sweep must include it")


func test_unauthored_reentry_is_not_inside_a_wall_or_on_a_stair() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var checked := 0
	var offenders: Array = []
	for f in _scripts():
		var cave = load(DUNGEON_DIR + "/" + f).new()
		if cave == null or not (cave is Node) or cave is Area2D or not ("floor_layouts" in cave):
			if cave is Node:
				cave.free()
			continue
		if (cave.floor_layouts as Dictionary).is_empty():
			cave.free()
			continue
		var floors: Array = []
		for floor_num in cave.floor_layouts:
			var spec: Dictionary = cave.floor_spawn_points.get(floor_num, {})
			if not spec.has("entrance"):
				floors.append(int(floor_num))
		if floors.is_empty():
			cave.free()
			continue
		vp.add_child(cave)
		await get_tree().process_frame
		var fallback := _fallback_for(cave)
		for floor_num in floors:
			var rows: Array = cave.floor_layouts[floor_num]
			var map_w: int = cave.MAP_WIDTH
			var map_h: int = cave.MAP_HEIGHT
			cave._generate_map_for_floor(floor_num)
			var spawn: Vector2 = cave.spawn_points["default"]
			var expected: Vector2 = DragonCave.entrance_spawn_px(rows, Vector2(-1, -1), map_w, map_h, TILE, fallback)
			if spawn != expected:
				offenders.append("%s floor %d: generator spawn %s is not entrance_spawn_px %s" % [f, floor_num, spawn, expected])
			var cell := Vector2i(int(floor(spawn.x / float(TILE))), int(floor(spawn.y / float(TILE))))
			var ch := _char_at(rows, cell.x, cell.y, map_w, map_h)
			var stairs := _last_stairs(rows, map_w, map_h)
			checked += 1
			if _blocked(ch):
				offenders.append("%s floor %d: spawn %s sits on '%s' at %s" % [f, floor_num, spawn, ch, cell])
			elif _in_stair(spawn.x, spawn.y, stairs):
				offenders.append("%s floor %d: spawn %s is inside a walk-on stair" % [f, floor_num, spawn])
			elif not _reaches(rows, cell, stairs, map_w, map_h):
				offenders.append("%s floor %d: spawn cell %s cannot reach a stair" % [f, floor_num, cell])
		cave.free()
	assert_gt(checked, 10, "checked %d unauthored floors — too few to be the sweep" % checked)
	assert_eq(offenders, [], "re-entry spawn is walled in or standing on a stair:\n  %s" % "\n  ".join(offenders))


func test_penultimate_crystal_floor_reentry_stands_on_open_ground() -> void:
	for path in ["res://src/maps/dungeons/LightningDragonCave.gd", "res://src/maps/dungeons/ShadowDragonCave.gd"]:
		var cave = load(path).new()
		var floor_num := int(cave.total_floors) - 1
		var flags: Dictionary = GameState.game_constants.get("dungeon_flags", {}).duplicate()
		flags.erase(cave.boss_flag_key)
		GameState.game_constants["dungeon_flags"] = flags
		GameState.game_constants.erase("meta_dungeon_skip_pending")
		GameState.game_constants[str(cave.cave_id) + "_floor"] = floor_num
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		add_child_autofree(vp)
		vp.add_child(cave)
		await get_tree().process_frame
		assert_eq(int(cave.current_floor), floor_num,
			"%s opened on floor %d after the saved floor key was %d — _ready replaced the key" % [path.get_file(), cave.current_floor, floor_num])
		var spawn: Vector2 = cave.spawn_points["default"]
		assert_eq(cave.player.position, spawn, "%s player is not standing on the floor's default spawn" % path.get_file())
		var rows: Array = cave.floor_layouts[floor_num]
		var cell := Vector2i(int(floor(spawn.x / float(TILE))), int(floor(spawn.y / float(TILE))))
		var ch := _char_at(rows, cell.x, cell.y, cave.MAP_WIDTH, cave.MAP_HEIGHT)
		assert_false(_blocked(ch), "%s floor %d re-entry cell %s is '%s'" % [path.get_file(), floor_num, cell, ch])
		var radius := _player_radius(cave.player)
		assert_gt(radius, 0.0, "the player body has a circle — otherwise the wall check is not about the body that moves")
		assert_false(_in_stair(spawn.x, spawn.y, _last_stairs(rows, cave.MAP_WIDTH, cave.MAP_HEIGHT)),
			"%s floor %d re-entry is inside a stair sensor" % [path.get_file(), floor_num])
		cave.free()


func _player_radius(player: Node) -> float:
	for c in player.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is CircleShape2D:
			return ((c as CollisionShape2D).shape as CircleShape2D).radius
	return -1.0
