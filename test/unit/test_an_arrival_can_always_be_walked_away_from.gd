extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## 🐛 A SOFT-LOCKED ARRIVAL IS THE ONE BUG A PLAYER CANNOT RECOVER FROM. Walk out of a cave and land
## in blocked terrain, or in a one-cell pocket, and the run is over — no menu, no reload short of an
## older save. Nothing pinned it.
##
## 🔑 THE CLASS HAS HISTORY, WHICH IS WHY IT IS WORTH AN ARM WITH ZERO CURRENT INSTANCES.
## `OverworldScene.SPAWN_CLEARANCE` exists because "Markers sit under ridge; the Mode 7 collider
## shift drops that ridge onto the marker tile, so these arrivals step aside to ground that is clear
## in the DISPLACED frame" — it carries hand-made offsets for `1`, `4` and `I` only. A new landmark
## added without one lands wherever the painted map happens to allow.
##
## ⛔ MEASURED ON THE COLLIDER THE PLAYER MEETS, NOT THE PAINTED MAP, AND THE TWO ARE 140.6 px APART.
## `Mode7Overlay.apply_terrain_collision_alignment` clones the tilemap into a hidden
## `TileMapCollision` child shifted by `MODE7_GROUND_DISPLACEMENT_PX` and DISABLES collision on the
## authored layer. `test_the_shifted_collider_is_what_we_measured` pins both halves, because a probe
## that read the authored layer would be measuring a world the player never touches.
##
## ⚠️ AND THE FLOOD RUNS ON THE WALKABLE LATTICE (`TILE_SIZE`), NOT THE CONTENT FRAME
## (`MAP_SCALE * TILE_SIZE`). My first pass used the frame and it was wrong in BOTH directions: it
## invented a pocket in W6 (`apex` has 4 free neighbours at 32 px and 1 at 64 px) and, worse, a
## double-width step can hop THROUGH a one-cell wall and report a genuine pocket as connected. The
## five worlds that looked clean on the wrong lattice were not evidence of anything.
##
## 📌 POPULATIONS. COVERED: every `spawn_points` entry in the six overworlds (Mode 7, measured on
## the shifted collider) and in the 13 villages — 146 arrivals, all clean.
##
## ⛔ NOT COVERED: DUNGEON FLOORS, AND THE REASON IS PUZZLE STATE RATHER THAN COST. The same probe
## reports four dungeon arrivals as sealed, and ALL FOUR ARE THE UNSOLVED STATE OF AN AUTHORED
## PUZZLE, not defects. Driven with the real `_transition_to_floor` and the real player body
## (`move_and_collide`, circle r=4), every direction blocked — and then explained:
##
##     whispering f3 stairs_up (11,11)  lever `sw0` flips (11,10), the cell directly above it
##     whispering f4 stairs_up  (6,11)  the `G` lock gate sits between D(6,9) and U(6,11)
##     ice f2        stairs_up (17,13)  lever `sw2` flips (16,13), directly west of it
##     whispering f2 "default"          `default` is never an arrival: every caller of
##                                      _transition_to_floor passes "up" or "down"
##
## WhisperingCave's own header says why: "struktured 2026-10-07: the first cave now teaches the
## Zelda-style gates the W1 dragon caves require". A Zelda gate IS a sealed arrival until you solve
## it, so judging a dungeon arrival needs the puzzle state the player would have, and a build-time
## probe has none. That is a different guard, not this one.
##
## ALSO NOT COVERED: interiors, deliberately — their door is pinned twice already, by
## `test_interior_return_doorstep_regression` (village side) and
## `test_an_interior_reads_its_own_examines` (room side); and battle/cutscene return positions, which
## are restored rather than authored.

const OVERWORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}
const VILLAGE_DIR := "res://src/maps/villages/"

## A landing you cannot leave is the bug; a landing with a few cells is a corridor, which is fine.
const ROOM_ENOUGH: int = 6

var _vp: SubViewport = null


func _world(path: String) -> Node2D:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.set_story_flag("world1_mordaine_defeated", true)
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var w = scr.new()
	_vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return w


func _teardown(w: Node2D) -> void:
	w.queue_free()
	await get_tree().process_frame
	_vp.queue_free()
	await get_tree().process_frame


func _fits(at: Vector2) -> bool:
	var sh := CircleShape2D.new()
	sh.radius = 8.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = sh
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


## Cells reachable from `at`, capped — we only need to know it is more than a pocket.
func _room(at: Vector2, tile: float) -> int:
	if not _fits(at):
		return -1
	var start := Vector2i(at / tile)
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	while not queue.is_empty() and seen.size() <= ROOM_ENOUGH * 4:
		var c: Vector2i = queue.pop_front()
		for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + nb
			if seen.has(q) or q.x < 0 or q.y < 0:
				continue
			if not _fits(Vector2(q.x * tile + tile / 2.0, q.y * tile + tile / 2.0)):
				continue
			seen[q] = true
			queue.append(q)
	return seen.size()




func _judge(w: Node2D, who: String, bad: Array) -> int:
	var tile := float(w.TILE_SIZE)
	var n := 0
	var keys: Array = w.spawn_points.keys()
	keys.sort()
	for k in keys:
		var p: Variant = w.spawn_points[k]
		if not (p is Vector2):
			continue
		n += 1
		var r := _room(p as Vector2, tile)
		if r < 0:
			bad.append("%s/%s: arrival at %s is INSIDE terrain — a player landing here cannot move at all" % [who, str(k), str(p)])
		elif r < ROOM_ENOUGH:
			var nb := ""
			for n2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				nb += "%s:%s " % [str(n2), "free" if _fits((p as Vector2) + Vector2(n2) * tile) else "blocked"]
			bad.append("%s/%s: arrival at %s has only %d reachable cells — a pocket, and there is no way out of it [%s]" % [who, str(k), str(p), r, nb])
	return n


## ⛔ THE CONTROL THAT MAKES EVERY CLEAN RESULT BELOW MEAN ANYTHING: we must be reading the SHIFTED
## collider. If the authored layer still collided, or the clone were missing, the flood would be
## measuring a world 140.6 px away from the one the player walks in.
func test_the_shifted_collider_is_what_we_measured() -> void:
	var w = await _world(str(OVERWORLDS["medieval"]))
	assert_not_null(w, "CONTROL: W1 must build")
	if w == null:
		return
	assert_true(bool(w.mode7_enabled), "CONTROL: W1 is a Mode 7 world or the shift does not apply")
	var clone: Node = null
	for c in w.get_children():
		if str(c.name) == "TileMapCollision":
			clone = c
	assert_not_null(clone, "the shifted collider clone must exist — without it we measure the painted map")
	if clone != null:
		assert_almost_eq((clone as TileMapLayer).position.y - w.tile_map.position.y,
			InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX, 0.01,
			"the clone must sit exactly MODE7_GROUND_DISPLACEMENT_PX below the authored layer")
		assert_true((clone as TileMapLayer).collision_enabled, "the clone is the collider")
	assert_false(w.tile_map.collision_enabled,
		"the AUTHORED layer must have collision off, or the player meets two offset copies of the world")
	await _teardown(w)


## 🔑 AND THE CONTROL THAT STOPS AN EMPTY FLOOD PASSING: plant an arrival inside terrain and require
## this file's own judgement to name it. A clean sweep of 60+ spawns proves nothing if the detector
## cannot fail.
func test_a_blocked_arrival_is_named() -> void:
	var w = await _world(str(OVERWORLDS["medieval"]))
	assert_not_null(w, "CONTROL: W1 must build")
	if w == null:
		return
	var tile := float(w.TILE_SIZE)
	## Find a cell the collider refuses — searched, not assumed, so a changed map cannot make this
	## control quietly vacuous.
	var blocked := Vector2.INF
	for y in range(4, 120):
		for x in range(4, 190):
			var at := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			if not _fits(at):
				blocked = at
				break
		if blocked != Vector2.INF:
			break
	assert_ne(blocked, Vector2.INF, "CONTROL: the map must contain at least one blocked cell to plant in")
	if blocked == Vector2.INF:
		await _teardown(w)
		return
	w.spawn_points["zz_planted_blocked"] = blocked
	## \u26d4 AND A SECOND PLANT, BECAUSE THE TWO CLAUSES NEED TWO INPUTS. Deleting the pocket clause
	## left this control GREEN: it planted only a cell INSIDE terrain, which trips `r < 0`, so the
	## `r < ROOM_ENOUGH` half had no failing input anywhere in the real data and could have shipped
	## unfalsifiable. W1 has small enclosed regions — searched for, not assumed, so a remapped world
	## makes this control go loud rather than quietly vacuous.
	var pocket := Vector2.INF
	for y in range(4, 120):
		for x in range(4, 190):
			var at := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			var r := _room(at, tile)
			if r > 0 and r < ROOM_ENOUGH:
				pocket = at
				break
		if pocket != Vector2.INF:
			break
	assert_ne(pocket, Vector2.INF,
		"CONTROL: no enclosed region smaller than %d cells exists to plant in, so the pocket clause cannot be driven — say so in the header rather than shipping it unfalsifiable" % ROOM_ENOUGH)
	if pocket != Vector2.INF:
		w.spawn_points["zz_planted_pocket"] = pocket

	var bad: Array = []
	_judge(w, "medieval", bad)
	var saw_blocked := false
	var saw_pocket := false
	for b in bad:
		if str(b).contains("zz_planted_blocked"):
			saw_blocked = true
		if str(b).contains("zz_planted_pocket"):
			saw_pocket = true
	assert_true(saw_blocked,
		"a spawn planted INSIDE terrain at %s was not reported — the arms below cannot fail" % str(blocked))
	assert_true(saw_pocket,
		"a spawn planted in an enclosed region at %s was not reported — the pocket half of the invariant is dead" % str(pocket))
	await _teardown(w)


func test_every_overworld_arrival_can_be_left() -> void:
	var bad: Array = []
	var spawns := 0
	for world in OVERWORLDS.keys():
		var w = await _world(str(OVERWORLDS[world]))
		if w == null:
			continue
		spawns += _judge(w, world, bad)
		await _teardown(w)
	assert_gt(spawns, 50, "CONTROL: only %d overworld spawns examined" % spawns)
	bad.sort()
	for b in bad:
		gut.p("SOFTLOCK %s" % str(b))
	assert_eq(bad, [], "an overworld arrival strands the player: %s" % "; ".join(bad))
	gut.p("  %d overworld arrivals, all standable with room to leave" % spawns)


func test_every_village_arrival_can_be_left() -> void:
	var d := DirAccess.open(VILLAGE_DIR)
	assert_not_null(d, "CONTROL: the villages directory must be readable")
	if d == null:
		return
	var files: Array = []
	for f in d.get_files():
		if f.ends_with(".gd") and f != "BaseVillage.gd":
			files.append(f)
	files.sort()
	var bad: Array = []
	var spawns := 0
	for f in files:
		var w = await _world(VILLAGE_DIR + f)
		if w == null:
			continue
		spawns += _judge(w, f, bad)
		await _teardown(w)
	assert_gt(spawns, 20, "CONTROL: only %d village spawns examined" % spawns)
	bad.sort()
	for b in bad:
		gut.p("SOFTLOCK %s" % str(b))
	assert_eq(bad, [], "a village arrival strands the player: %s" % "; ".join(bad))
	gut.p("  %d village arrivals, all standable with room to leave" % spawns)


func after_all() -> void:
	SoundState.restore()
