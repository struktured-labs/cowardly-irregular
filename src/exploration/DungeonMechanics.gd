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
