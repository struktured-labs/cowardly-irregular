extends Node
class_name DungeonMechanics

## Reusable opt-in key/door + bomb/crack puzzle vocabulary for DragonCave subclasses (struktured 2026-10-06 maze pass).
## Chars: K = small key pickup, Q = blast charge pickup, G = locked door (needs a key), Z = cracked wall (needs a charge).
## A pickup is collected once, permanently; a lock opens once a matching resource is held that hasn't been spent on an
## earlier lock of the same kind -- classic "any key opens any door of its type" Zelda small-key pooling, not 1:1 pairing.
## State persists in GameState.game_constants[cave_id + "_mechanics"]; static scan_*/lock_is_open are the single source
## of truth the solver test also uses, same shape as DungeonPuzzleLayer.

const KEY_CHAR := "K"
const BOMB_CHAR := "Q"
const DOOR_CHAR := "G"
const CRACK_CHAR := "Z"
const RESOURCE_FOR_PICKUP := {"K": "key", "Q": "bomb"}
const RESOURCE_FOR_LOCK := {"G": "key", "Z": "bomb"}
const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")

var _cave: Node = null
var _container: Node2D = null
var _collected: Dictionary = {}  ## pickup_id -> true
var _opened: Dictionary = {}     ## lock_id -> true


## ---- static / pure data helpers (shared with the solver test) ----

static func scan_pickups(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, RESOURCE_FOR_PICKUP, "pk")


static func scan_locks(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, RESOURCE_FOR_LOCK, "lk")


static func _scan(floor_layouts: Dictionary, char_map: Dictionary, prefix: String) -> Array:
	var out: Array = []
	var floors: Array = floor_layouts.keys()
	floors.sort()
	var idx := 0
	for f in floors:
		var rows: Array = floor_layouts[f]
		for y in range(rows.size()):
			var row: String = rows[y]
			for x in range(row.length()):
				var ch := row[x]
				if char_map.has(ch):
					out.append({"id": "%s%d" % [prefix, idx], "floor": int(f), "cell": Vector2i(x, y), "resource": char_map[ch]})
					idx += 1
	return out


static func lock_id_at(locks: Array, floor_num: int, cell: Vector2i) -> String:
	for lk in locks:
		if int(lk["floor"]) == floor_num and (lk["cell"] as Vector2i) == cell:
			return str(lk["id"])
	return ""


static func pickup_id_at(pickups: Array, floor_num: int, cell: Vector2i) -> String:
	for pk in pickups:
		if int(pk["floor"]) == floor_num and (pk["cell"] as Vector2i) == cell:
			return str(pk["id"])
	return ""


## True if `resource` has been collected more times than it has been spent opening earlier locks, per collected/opened sets.
static func resource_available(resource: String, pickups: Array, locks: Array, collected: Dictionary, opened: Dictionary) -> bool:
	var have := 0
	for pk in pickups:
		if str(pk["resource"]) == resource and bool(collected.get(str(pk["id"]), false)):
			have += 1
	var spent := 0
	for lk in locks:
		if str(lk["resource"]) == resource and bool(opened.get(str(lk["id"]), false)):
			spent += 1
	return have > spent


## ---- instance / scene wiring ----

func attach(cave: Node) -> void:
	_cave = cave
	_container = Node2D.new()
	_container.name = "MechanicsLayerNodes"
	cave.add_child(_container)
	_load_persisted_state()
	_load_round2_state()


func _load_persisted_state() -> void:
	_collected.clear()
	_opened.clear()
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _cave == null:
		return
	var key: String = str(_cave.cave_id) + "_mechanics"
	var saved: Dictionary = gs.game_constants.get(key, {})
	for k in (saved.get("collected", []) as Array):
		_collected[str(k)] = true
	for k in (saved.get("opened", []) as Array):
		_opened[str(k)] = true


func _save_persisted_state() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _cave == null:
		return
	gs.game_constants[str(_cave.cave_id) + "_mechanics"] = {
		"collected": _collected.keys(),
		"opened": _opened.keys(),
	}


## Clears and respawns every pickup/lock node for floor_num from persisted state -- called on floor entry and after any lock opens.
func rebuild_floor(floor_num: int) -> void:
	if _cave == null or _container == null:
		return
	for c in _container.get_children():
		c.queue_free()
	_apply_opened_tiles(floor_num)
	_spawn_pickups(floor_num)
	_spawn_locks(floor_num)
	rebuild_floor_round2(floor_num)


func _apply_opened_tiles(floor_num: int) -> void:
	var floor_atlas: Vector2i = _cave._get_atlas_coords(TileGeneratorScript.TileType.CAVE_FLOOR)
	for lk in scan_locks(_cave.floor_layouts):
		if int(lk["floor"]) != floor_num:
			continue
		if bool(_opened.get(str(lk["id"]), false)):
			_cave.tile_map.set_cell(lk["cell"], 0, floor_atlas)


func _spawn_pickups(floor_num: int) -> void:
	for pk in scan_pickups(_cave.floor_layouts):
		if int(pk["floor"]) != floor_num:
			continue
		var pid: String = str(pk["id"])
		if bool(_collected.get(pid, false)):
			continue
		var cell: Vector2i = pk["cell"]
		var pos := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		var marker := _create_pickup_marker(pos, str(pk["resource"]))
		_container.add_child(marker)
		var area := Area2D.new()
		area.name = "Pickup_%s" % pid
		area.position = pos
		InteractGeometry.setup_trigger_collision(area, Vector2(22, 22))
		area.body_entered.connect(_on_pickup_entered.bind(pid, marker))
		_container.add_child(area)


func _on_pickup_entered(body: Node2D, pid: String, marker: Node2D) -> void:
	if not body.has_method("set_can_move") or bool(_collected.get(pid, false)):
		return
	_collected[pid] = true
	_save_persisted_state()
	if is_instance_valid(marker):
		marker.queue_free()
	var sm := get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_ui("chest_open")
	var resource := ""
	for pk in scan_pickups(_cave.floor_layouts):
		if str(pk["id"]) == pid:
			resource = str(pk["resource"])
	if _cave and is_instance_valid(_cave):
		Toast.show_success(_cave, "Found a small key." if resource == "key" else "Found a blast charge.")


func _spawn_locks(floor_num: int) -> void:
	for lk in scan_locks(_cave.floor_layouts):
		if int(lk["floor"]) != floor_num:
			continue
		var lid: String = str(lk["id"])
		if bool(_opened.get(lid, false)):
			continue
		var cell: Vector2i = lk["cell"]
		var pos := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		_container.add_child(_create_lock_marker(pos, str(lk["resource"])))
		var trigger := LockTrigger.new()
		trigger.lock_id = lid
		trigger.resource = str(lk["resource"])
		trigger.layer = self
		trigger.position = pos
		InteractGeometry.setup_trigger_collision(trigger, Vector2(30, 30))
		trigger.add_to_group("interactables")
		_container.add_child(trigger)


## Public so LockTrigger.interact() can call it.
func try_open(lock_id: String) -> void:
	if _cave == null or bool(_opened.get(lock_id, false)):
		return
	var locks := scan_locks(_cave.floor_layouts)
	var resource := ""
	for lk in locks:
		if str(lk["id"]) == lock_id:
			resource = str(lk["resource"])
	if resource == "":
		return
	if not resource_available(resource, scan_pickups(_cave.floor_layouts), locks, _collected, _opened):
		var sm_fail := get_node_or_null("/root/SoundManager")
		if sm_fail:
			sm_fail.play_ui("menu_error")
		if _cave and is_instance_valid(_cave):
			Toast.show_warning(_cave, "It's locked. You need a key." if resource == "key" else "Cracked, but solid. You need a blast charge.")
		return
	_opened[lock_id] = true
	_save_persisted_state()
	var sm := get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_ui("door_open")
	rebuild_floor(int(_cave.current_floor))


## Procedural diamond (key) / circle-with-fuse (bomb) marker -- no letters.
func _create_pickup_marker(pos: Vector2, resource: String) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos
	if resource == "key":
		var head := ColorRect.new()
		head.size = Vector2(12, 12)
		head.position = Vector2(-6, -16)
		head.rotation = PI / 4.0
		head.color = Color(0.95, 0.82, 0.25, 0.95)
		marker.add_child(head)
		var shaft := ColorRect.new()
		shaft.size = Vector2(4, 14)
		shaft.position = Vector2(-2, -6)
		shaft.color = Color(0.95, 0.82, 0.25, 0.95)
		marker.add_child(shaft)
	else:
		var body := ColorRect.new()
		body.size = Vector2(18, 18)
		body.position = Vector2(-9, -14)
		body.color = Color(0.15, 0.14, 0.16, 0.95)
		marker.add_child(body)
		var fuse := ColorRect.new()
		fuse.size = Vector2(3, 8)
		fuse.position = Vector2(-1, -22)
		fuse.rotation = 0.3
		fuse.color = Color(0.85, 0.55, 0.2, 0.95)
		marker.add_child(fuse)
	marker.ready.connect(func():
		var tween := marker.create_tween()
		tween.set_loops()
		tween.tween_property(marker, "modulate:a", 0.55, 0.7)
		tween.tween_property(marker, "modulate:a", 1.0, 0.7)
	)
	return marker


## A dim plaque over the wall tile hinting a lock lives there -- no letters.
func _create_lock_marker(pos: Vector2, resource: String) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos
	var plaque := ColorRect.new()
	plaque.size = Vector2(22, 8)
	plaque.position = Vector2(-11, -4)
	plaque.color = Color(0.85, 0.75, 0.2, 0.8) if resource == "key" else Color(0.55, 0.22, 0.18, 0.85)
	marker.add_child(plaque)
	return marker


## Lever-style interactable: requires interact(), standing adjacent to the wall tile.
class LockTrigger extends Area2D:
	var lock_id: String = ""
	var resource: String = ""
	var layer: DungeonMechanics = null

	func interact(_player: Node2D) -> void:
		if layer and is_instance_valid(layer):
			layer.try_open(lock_id)


## ---- round 2 (struktured 2026-10-07 ruling: required Zelda-style puzzles) ----
## Chars: X push block, J block target (plate/pylon), O block gate (wall until its floor's
## block has touched its target, permanent once triggered -- geometry keeps the push one-way).
## Y timed plate (player, repeatable), W timed gate (wall except while the plate's timer runs).
## R mirror lever (toggle, persisted) swapping which of two wall-sets on its floor is open.
## 'j' slide ice (decorative 'i' never slides) -- ice_slide_landing models the slide-until-blocked rule.

const BLOCK_CHAR := "X"
const BLOCK_TARGET_CHAR := "J"
const BLOCK_GATE_CHAR := "O"
const TIMED_PLATE_CHAR := "Y"
const TIMED_GATE_CHAR := "W"
const MIRROR_LEVER_CHAR := "R"
const ICE_CHAR := "i"  ## decorative-only (TileGenerator.ICE); never slides -- see SLIDE_ICE_CHAR
const SLIDE_ICE_CHAR := "j"  ## the only char the Zelda-style slide rule applies to
const TIMED_PLATE_SECONDS := 6.0

var _block_pushed: Dictionary = {}   ## block_id -> true, permanent once the block has touched its target
var _mirror_state: Dictionary = {}   ## lever_id -> bool, persisted toggle
var _timed_open_until: Dictionary = {}  ## floor_num -> engine msec the timed gate(s) on that floor stay open; never persisted


static func scan_blocks(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, {BLOCK_CHAR: "block"}, "bk")


static func scan_block_targets(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, {BLOCK_TARGET_CHAR: "target"}, "bt")


static func scan_block_gates(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, {BLOCK_GATE_CHAR: "gate"}, "bg")


## One puzzle per floor that carries a block+target pair (round 2's level design never pairs
## two on one floor) -- {id, floor, block_cell, target_cell, from_cell, dir, gate_cells}.
static func block_puzzles(floor_layouts: Dictionary) -> Array:
	var out: Array = []
	var blocks := scan_blocks(floor_layouts)
	var targets := scan_block_targets(floor_layouts)
	var gates := scan_block_gates(floor_layouts)
	for bk in blocks:
		var f: int = int(bk["floor"])
		var bcell: Vector2i = bk["cell"]
		var tcell := Vector2i(-1, -1)
		for tg in targets:
			if int(tg["floor"]) == f:
				tcell = tg["cell"]
				break
		if tcell == Vector2i(-1, -1):
			continue
		var dir := Vector2i(sign(tcell.x - bcell.x), sign(tcell.y - bcell.y))
		var gate_cells: Array = []
		for gt in gates:
			if int(gt["floor"]) == f:
				gate_cells.append(gt["cell"])
		out.append({
			"id": "bp%d" % out.size(), "floor": f, "block_cell": bcell, "target_cell": tcell,
			"from_cell": bcell - dir, "dir": dir, "gate_cells": gate_cells,
		})
	return out


static func scan_timed_plates(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, {TIMED_PLATE_CHAR: "timer"}, "tp")


static func scan_timed_gates(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, {TIMED_GATE_CHAR: "timer"}, "tg")


static func scan_mirror_levers(floor_layouts: Dictionary) -> Array:
	return _scan(floor_layouts, {MIRROR_LEVER_CHAR: "mirror"}, "mr")


## One puzzle per floor that carries a timed plate -- {id, floor, plate_cell, gate_cells}, same
## shape as block_puzzles. Round 2's level design never pairs two timed plates on one floor.
static func timed_puzzles(floor_layouts: Dictionary) -> Array:
	var out: Array = []
	var plates := scan_timed_plates(floor_layouts)
	var gates := scan_timed_gates(floor_layouts)
	for tp in plates:
		var f: int = int(tp["floor"])
		var gate_cells: Array = []
		for tg in gates:
			if int(tg["floor"]) == f:
				gate_cells.append(tg["cell"])
		out.append({"id": "tp%d" % out.size(), "floor": f, "plate_cell": tp["cell"], "gate_cells": gate_cells})
	return out


## Pure BFS-shortest-path distance (tile count, 4-dir) between two cells on one floor treating
## every non-wall char as open -- used to prove a timed gate's far side is reachable in budget.
static func shortest_distance(floor_layouts: Dictionary, floor_num: int, from_cell: Vector2i, to_cell: Vector2i) -> int:
	var seen := {from_cell: true}
	var queue: Array = [from_cell]
	var dist := {from_cell: 0}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to_cell:
			return int(dist[cur])
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			var ch := _char_at(floor_layouts, floor_num, n)
			if ch == "" or ch == "M" or ch == "l":
				continue
			if not seen.has(n):
				seen[n] = true
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return -1


## Slides from `enter_cell` (already known to be ice or lava) through contiguous ice/lava cells in
## `dir` until landing on solid ground, a wall, or the map edge -- classic "can't stop on ice" rule.
## Lava is a pass-through ONLY while already sliding; walking onto it directly is never offered.
static func ice_slide_landing(floor_layouts: Dictionary, floor_num: int, enter_cell: Vector2i, dir: Vector2i) -> Vector2i:
	var cur := enter_cell
	for _i in range(64):
		var ch := _char_at(floor_layouts, floor_num, cur)
		if ch != SLIDE_ICE_CHAR and ch != "l":
			return cur
		var nxt := cur + dir
		var nch := _char_at(floor_layouts, floor_num, nxt)
		if nch == "" or nch == "M":
			return cur
		cur = nxt
	return cur


static func _char_at(floor_layouts: Dictionary, floor_num: int, cell: Vector2i) -> String:
	var rows: Array = floor_layouts.get(floor_num, [])
	if cell.y < 0 or cell.y >= rows.size():
		return ""
	var row: String = rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


## ---- round 2 instance / scene wiring ----

func _load_round2_state() -> void:
	_block_pushed.clear()
	_mirror_state.clear()
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _cave == null:
		return
	var key: String = str(_cave.cave_id) + "_mechanics2"
	var saved: Dictionary = gs.game_constants.get(key, {})
	for k in (saved.get("blocks", []) as Array):
		_block_pushed[str(k)] = true
	for k in (saved.get("mirrors", {}) as Dictionary):
		_mirror_state[str(k)] = bool(saved["mirrors"][k])


func _save_round2_state() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _cave == null:
		return
	var key: String = str(_cave.cave_id) + "_mechanics2"
	gs.game_constants[key] = {"blocks": _block_pushed.keys(), "mirrors": _mirror_state.duplicate()}


## Clears and respawns every round-2 node for floor_num -- called from rebuild_floor.
func rebuild_floor_round2(floor_num: int) -> void:
	if _cave == null or _container == null:
		return
	_apply_block_gate_tiles(floor_num)
	_apply_mirror_tiles(floor_num)
	_spawn_blocks(floor_num)
	_spawn_timed_plates_and_gates(floor_num)
	_spawn_mirror_lever(floor_num)


var _ice_sliding: bool = false

## Classic "can't stop on ice" rule, polled rather than physics-driven (SLIDE_ICE_CHAR tiles can
## sit over a lava pass-through, which a CharacterBody2D would otherwise collide with). While
## standing on a slide-ice cell with a direction held, the player is teleported to the landing
## cell computed by DungeonMechanics.ice_slide_landing instead of moving normally.
func _process(_delta: float) -> void:
	if _cave == null or not is_instance_valid(_cave) or _ice_sliding:
		return
	var player: Node2D = _cave.player
	if player == null or not is_instance_valid(player):
		return
	var tile: int = int(_cave.TILE_SIZE)
	var cell := Vector2i(int(player.position.x) / tile, int(player.position.y) / tile)
	if _char_at(_cave.floor_layouts, int(_cave.current_floor), cell) != SLIDE_ICE_CHAR:
		return
	var axis := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if axis == Vector2.ZERO:
		return
	var dir := Vector2i.ZERO
	if absf(axis.x) > absf(axis.y):
		dir = Vector2i(1, 0) if axis.x > 0.0 else Vector2i(-1, 0)
	else:
		dir = Vector2i(0, 1) if axis.y > 0.0 else Vector2i(0, -1)
	var landing := ice_slide_landing(_cave.floor_layouts, int(_cave.current_floor), cell, dir)
	if landing == cell:
		return
	_ice_sliding = true
	if player.has_method("set_can_move"):
		player.set_can_move(false)
	var dest := Vector2(landing.x * tile + tile / 2, landing.y * tile + tile / 2)
	var sm := get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_ui("portal_enter")
	var tween := create_tween()
	var dist: float = absf(landing.x - cell.x) + absf(landing.y - cell.y)
	tween.tween_property(player, "position", dest, clampf(dist * 0.08, 0.1, 0.6))
	tween.finished.connect(func():
		_ice_sliding = false
		if player and is_instance_valid(player) and player.has_method("set_can_move"):
			player.set_can_move(true)
	)


func _apply_block_gate_tiles(floor_num: int) -> void:
	var floor_atlas: Vector2i = _cave._get_atlas_coords(TileGeneratorScript.TileType.CAVE_FLOOR)
	for bp in block_puzzles(_cave.floor_layouts):
		if int(bp["floor"]) != floor_num or not bool(_block_pushed.get(str(bp["id"]), false)):
			continue
		for gc in (bp["gate_cells"] as Array):
			_cave.tile_map.set_cell(gc, 0, floor_atlas)


func _apply_mirror_tiles(floor_num: int) -> void:
	var floor_atlas: Vector2i = _cave._get_atlas_coords(TileGeneratorScript.TileType.CAVE_FLOOR)
	var wall_atlas: Vector2i = _cave._get_atlas_coords(TileGeneratorScript.TileType.CAVE_WALL)
	var effects: Dictionary = _cave.mirror_effects
	for mr in scan_mirror_levers(_cave.floor_layouts):
		if int(mr["floor"]) != floor_num:
			continue
		var mid: String = str(mr["id"])
		var eff: Dictionary = effects.get(mid, {})
		var active: bool = bool(_mirror_state.get(mid, false))
		var open_set: Array = (eff.get("b", []) if active else eff.get("a", [])) as Array
		var closed_set: Array = (eff.get("a", []) if active else eff.get("b", [])) as Array
		for pair in open_set:
			_cave.tile_map.set_cell(Vector2i(int(pair[0]), int(pair[1])), 0, floor_atlas)
		for pair in closed_set:
			_cave.tile_map.set_cell(Vector2i(int(pair[0]), int(pair[1])), 0, wall_atlas)


func _spawn_blocks(floor_num: int) -> void:
	for bp in block_puzzles(_cave.floor_layouts):
		if int(bp["floor"]) != floor_num:
			continue
		var bid: String = str(bp["id"])
		var cell: Vector2i = bp["target_cell"] if bool(_block_pushed.get(bid, false)) else bp["block_cell"]
		var block := PushBlock.new()
		block.block_id = bid
		block.layer = self
		block.cell = cell
		block.target_cell = bp["target_cell"]
		block.name = "Block_%s" % bid
		block.position = Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		_container.add_child(block)
		block.build()


func _spawn_timed_plates_and_gates(floor_num: int) -> void:
	var now_ok := int(Time.get_ticks_msec()) < int(_timed_open_until.get(floor_num, 0))
	var floor_atlas: Vector2i = _cave._get_atlas_coords(TileGeneratorScript.TileType.CAVE_FLOOR)
	for tg in scan_timed_gates(_cave.floor_layouts):
		if int(tg["floor"]) != floor_num:
			continue
		if now_ok:
			_cave.tile_map.set_cell(tg["cell"], 0, floor_atlas)
		var ring := TimedGateRing.new()
		ring.layer = self
		ring.cell = tg["cell"]
		ring.name = "TimedGate_%s" % str(tg["cell"])
		ring.position = Vector2(int(tg["cell"].x) * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, int(tg["cell"].y) * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		_container.add_child(ring)
	for tp in scan_timed_plates(_cave.floor_layouts):
		if int(tp["floor"]) != floor_num:
			continue
		var cell: Vector2i = tp["cell"]
		var pos := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		_container.add_child(_create_timed_plate_marker(pos))
		var area := Area2D.new()
		area.name = "TimedPlate_%d_%d" % [cell.x, cell.y]
		area.position = pos
		InteractGeometry.setup_trigger_collision(area, Vector2(28, 28))
		area.body_entered.connect(_on_timed_plate_entered.bind(floor_num))
		_container.add_child(area)


func _on_timed_plate_entered(body: Node2D, floor_num: int) -> void:
	if not body.has_method("set_can_move"):
		return
	var was_open := int(Time.get_ticks_msec()) < int(_timed_open_until.get(floor_num, 0))
	_timed_open_until[floor_num] = int(Time.get_ticks_msec()) + int(TIMED_PLATE_SECONDS * 1000.0)
	var sm := get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_ui("door_open")
	if not was_open and int(_cave.current_floor) == floor_num:
		rebuild_floor(floor_num)


func _spawn_mirror_lever(floor_num: int) -> void:
	for mr in scan_mirror_levers(_cave.floor_layouts):
		if int(mr["floor"]) != floor_num:
			continue
		var mid: String = str(mr["id"])
		var cell: Vector2i = mr["cell"]
		var pos := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		_container.add_child(_create_mirror_marker(pos, bool(_mirror_state.get(mid, false))))
		var trigger := MirrorTrigger.new()
		trigger.mirror_id = mid
		trigger.layer = self
		trigger.position = pos
		InteractGeometry.setup_trigger_collision(trigger, Vector2(28, 28))
		trigger.add_to_group("interactables")
		_container.add_child(trigger)


## Public so MirrorTrigger.interact() can call it.
func toggle_mirror(mirror_id: String) -> void:
	if _cave == null:
		return
	_mirror_state[mirror_id] = not bool(_mirror_state.get(mirror_id, false))
	_save_round2_state()
	var sm := get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_ui("door_open")
	rebuild_floor(int(_cave.current_floor))


## Public so PushBlock can call it once it lands on its target. Permanent -- opening a
## block gate never re-locks, matching every other lock in this file.
func mark_block_on_target(block_id: String) -> void:
	if bool(_block_pushed.get(block_id, false)):
		return
	_block_pushed[block_id] = true
	_save_round2_state()
	var sm := get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_ui("door_open")
	if _cave and is_instance_valid(_cave):
		Toast.show_success(_cave, "The pylon hums to life.")
	rebuild_floor(int(_cave.current_floor))


## True if `cell` is open for `block_id` to move into: inside the floor, not a wall/lava/lock, and
## not occupied by another block.
func _block_dest_open(floor_num: int, cell: Vector2i) -> bool:
	var ch := _char_at(_cave.floor_layouts, floor_num, cell)
	if ch == "" or ch == "M" or ch == "l":
		return false
	for bp in block_puzzles(_cave.floor_layouts):
		if int(bp["floor"]) != floor_num:
			continue
		var occupied: Vector2i = bp["target_cell"] if bool(_block_pushed.get(str(bp["id"]), false)) else bp["block_cell"]
		if occupied == cell:
			return false
	return true


## Procedural stone block -- no letters.
func _create_timed_plate_marker(pos: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos
	var bg := ColorRect.new()
	bg.size = Vector2(22, 22)
	bg.position = Vector2(-11, -11)
	bg.color = Color(0.85, 0.42, 0.18, 0.9)
	marker.add_child(bg)
	return marker


func _create_mirror_marker(pos: Vector2, active: bool) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos
	var bg := ColorRect.new()
	bg.size = Vector2(20, 24)
	bg.position = Vector2(-10, -20)
	bg.color = Color(0.55, 0.2, 0.7, 0.9) if active else Color(0.3, 0.1, 0.4, 0.9)
	marker.add_child(bg)
	return marker


## Lever-style interactable for the mirror toggle.
class MirrorTrigger extends Area2D:
	var mirror_id: String = ""
	var layer: DungeonMechanics = null

	func interact(_player: Node2D) -> void:
		if layer and is_instance_valid(layer):
			layer.toggle_mirror(mirror_id)


## Countdown ring over a timed gate -- pure visual, no letters; ticks down while the window is open.
class TimedGateRing extends Node2D:
	var layer: DungeonMechanics = null
	var cell: Vector2i = Vector2i.ZERO
	var _arc: ColorRect = null

	func _ready() -> void:
		_arc = ColorRect.new()
		_arc.size = Vector2(6, 26)
		_arc.position = Vector2(-3, -13)
		_arc.color = Color(1.0, 0.75, 0.3, 0.9)
		add_child(_arc)

	func _process(_delta: float) -> void:
		if layer == null or not is_instance_valid(layer):
			return
		var until: int = int(layer._timed_open_until.get(int(layer._cave.current_floor), 0))
		var remaining: float = max(0.0, float(until - Time.get_ticks_msec()) / 1000.0)
		visible = remaining > 0.0
		if visible:
			_arc.size.x = lerp(1.0, 6.0, remaining / TIMED_PLATE_SECONDS)


## Pushable block: walking into it from the correct side shoves it one tile toward its
## target plate/pylon; once it touches the target the linked gate opens permanently.
class PushBlock extends StaticBody2D:
	var block_id: String = ""
	var layer: DungeonMechanics = null
	var cell: Vector2i = Vector2i.ZERO
	var target_cell: Vector2i = Vector2i.ZERO
	var _pushing: bool = false

	func build() -> void:
		collision_layer = 1
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(28, 28)
		shape.shape = rect
		add_child(shape)
		var body := ColorRect.new()
		body.size = Vector2(28, 28)
		body.position = Vector2(-14, -14)
		body.color = Color(0.5, 0.42, 0.32, 1.0)
		add_child(body)
		var detector := Area2D.new()
		detector.collision_layer = InteractGeometry.LAYER_INTERACTABLE
		detector.collision_mask = InteractGeometry.MASK_PLAYER
		var dshape := CollisionShape2D.new()
		var drect := RectangleShape2D.new()
		drect.size = Vector2(36, 36)
		dshape.shape = drect
		detector.add_child(dshape)
		detector.body_entered.connect(_on_body_entered)
		add_child(detector)

	func _on_body_entered(body: Node2D) -> void:
		if _pushing or cell == target_cell or not body.has_method("set_can_move"):
			return
		if layer == null or not is_instance_valid(layer):
			return
		var delta: Vector2 = body.global_position - global_position
		var push_dir: Vector2i
		if abs(delta.x) > abs(delta.y):
			push_dir = Vector2i(1, 0) if delta.x < 0 else Vector2i(-1, 0)
		else:
			push_dir = Vector2i(0, 1) if delta.y < 0 else Vector2i(0, -1)
		var dest: Vector2i = cell + push_dir
		if not layer._block_dest_open(int(layer._cave.current_floor), dest):
			return
		_pushing = true
		cell = dest
		var tile: int = int(layer._cave.TILE_SIZE)
		var tween := create_tween()
		tween.tween_property(self, "position", Vector2(dest.x * tile + tile / 2, dest.y * tile + tile / 2), 0.15)
		tween.finished.connect(func():
			_pushing = false
			if cell == target_cell:
				layer.mark_block_on_target(block_id)
		)
