extends Node
class_name DungeonPuzzleLayer

## Reusable, additive puzzle vocabulary for DragonCave subclasses (struktured 2026-09-06).
## Chars: a-f portals (twin found by 2 occurrences, or a portal_links override), S pressure plate (auto), L lever (interact).
## switch_effects[id]: {"flip":[[x,y],...]} | {"reveal":"portal_c"} | {"trap":"encounter"|"warp"}; ids come from scan_switches.
## Switches persist in GameState.game_constants[cave_id + "_switches"]; static scan_*/*_destination fns are the single source of truth the solver test also uses.

const PORTAL_CHARS := ["a", "b", "c", "d", "e", "f"]
const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")

var _cave: Node = null
var _container: Node2D = null
var _active: Dictionary = {}   ## switch_id -> true
var _revealed: Dictionary = {} ## reveal key ("portal_c", "stairs_up", ...) -> true


## ---- static / pure data helpers (shared with the solver test) ----

static func scan_portals(floor_layouts: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var floors: Array = floor_layouts.keys()
	floors.sort()
	for f in floors:
		var rows: Array = floor_layouts[f]
		for y in range(rows.size()):
			var row: String = rows[y]
			for x in range(row.length()):
				var ch := row[x]
				if ch in PORTAL_CHARS:
					if not out.has(ch):
						out[ch] = []
					(out[ch] as Array).append({"floor": int(f), "cell": Vector2i(x, y)})
	return out


static func scan_switches(floor_layouts: Dictionary) -> Array:
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
				if ch == "S" or ch == "L":
					out.append({
						"id": "sw%d" % idx,
						"floor": int(f),
						"cell": Vector2i(x, y),
						"kind": "plate" if ch == "S" else "lever",
					})
					idx += 1
	return out


## Empty Array = every portal id resolves to exactly 2 endpoints.
static func validate_portal_pairs(floor_layouts: Dictionary, portal_links: Dictionary) -> Array:
	var errors: Array = []
	var occ := scan_portals(floor_layouts)
	for ch in occ:
		var n: int = (occ[ch] as Array).size()
		if n == 2:
			continue
		if n == 1 and portal_links.has(ch):
			continue
		errors.append("portal '%s' has %d occurrence(s) in floor_layouts and no portal_links override" % [ch, n])
	return errors


## The OTHER endpoint of the portal standing at (from_floor, from_cell), or {} if none.
static func portal_destination(floor_layouts: Dictionary, portal_links: Dictionary, from_floor: int, from_cell: Vector2i) -> Dictionary:
	var ch := _char_at(floor_layouts, from_floor, from_cell)
	if ch == "" or not (ch in PORTAL_CHARS):
		return {}
	var occ: Array = scan_portals(floor_layouts).get(ch, [])
	for entry in occ:
		if int(entry["floor"]) == from_floor and (entry["cell"] as Vector2i) == from_cell:
			continue
		return entry
	if portal_links.has(ch):
		var link: Dictionary = portal_links[ch]
		if link.has("cell"):
			var c: Array = link["cell"]
			return {"floor": int(link.get("floor", from_floor)), "cell": Vector2i(int(c[0]), int(c[1]))}
	return {}


## portal_char -> the reveal key that unlocks it, derived from switch_effects.
static func gated_portal_chars(switch_effects: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for sw_id in switch_effects:
		var reveal = (switch_effects[sw_id] as Dictionary).get("reveal", "")
		if reveal is String and (reveal as String).begins_with("portal_"):
			out[(reveal as String).substr(7)] = reveal
	return out


static func is_walkable(floor_layouts: Dictionary, switch_effects: Dictionary, floor_num: int, cell: Vector2i, active: Dictionary) -> bool:
	var ch := _char_at(floor_layouts, floor_num, cell)
	if ch == "":
		return false
	if ch != "M":
		return true
	for sw_id in switch_effects:
		if not bool(active.get(sw_id, false)):
			continue
		for pair in (switch_effects[sw_id] as Dictionary).get("flip", []):
			if int(pair[0]) == cell.x and int(pair[1]) == cell.y:
				return true
	return false


## Whether the portal sitting at (floor_num, cell) can be used given `active` switches.
static func portal_usable(switch_effects: Dictionary, floor_layouts: Dictionary, floor_num: int, cell: Vector2i, active: Dictionary) -> bool:
	var ch := _char_at(floor_layouts, floor_num, cell)
	if ch == "":
		return false
	var gated := gated_portal_chars(switch_effects)
	if not gated.has(ch):
		return true
	var reveal_key: String = gated[ch]
	for sw_id in switch_effects:
		var eff: Dictionary = switch_effects[sw_id]
		if str(eff.get("reveal", "")) == reveal_key and bool(active.get(sw_id, false)):
			return true
	return false


static func _char_at(floor_layouts: Dictionary, floor_num: int, cell: Vector2i) -> String:
	var rows: Array = floor_layouts.get(floor_num, [])
	if cell.y < 0 or cell.y >= rows.size():
		return ""
	var row: String = rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


## ---- instance / scene wiring ----

func attach(cave: Node) -> void:
	_cave = cave
	_container = Node2D.new()
	_container.name = "PuzzleLayerNodes"
	cave.add_child(_container)
	_load_persisted_state()


func _load_persisted_state() -> void:
	_active.clear()
	_revealed.clear()
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _cave == null:
		return
	var key: String = str(_cave.cave_id) + "_switches"
	var saved: Dictionary = gs.game_constants.get(key, {})
	for k in saved:
		_active[str(k)] = bool(saved[k])
	var effects: Dictionary = _cave.switch_effects
	for k in _active:
		if not _active[k] or not effects.has(k):
			continue
		var reveal = (effects[k] as Dictionary).get("reveal", "")
		if reveal is String and reveal != "":
			_revealed[reveal] = true


func _save_persisted_state() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _cave == null:
		return
	gs.game_constants[str(_cave.cave_id) + "_switches"] = _active.duplicate()


## Wraps the player between opposite edges on a wrap_floors floor -- "infinite directions".
func _process(_delta: float) -> void:
	if _cave == null or _cave.player == null or not is_instance_valid(_cave.player):
		return
	if not (int(_cave.current_floor) in (_cave.wrap_floors as Array)):
		return
	var w: float = float(_cave.MAP_WIDTH * _cave.TILE_SIZE)
	var h: float = float(_cave.MAP_HEIGHT * _cave.TILE_SIZE)
	var p: Vector2 = _cave.player.position
	var wrapped := Vector2(fposmod(p.x, w), fposmod(p.y, h))
	if wrapped != p:
		_cave.player.position = wrapped
		if _cave.camera:
			_cave.camera.reset_smoothing()
		var sm := get_node_or_null("/root/SoundManager")
		if sm:
			sm.play_ui("portal_enter")


## Clears and respawns every puzzle-layer node for floor_num from persisted state -- called on floor entry and after any switch fires.
func rebuild_floor(floor_num: int) -> void:
	if _cave == null or _container == null:
		return
	for c in _container.get_children():
		c.queue_free()
	_consume_bypass_puzzle()
	_apply_flip_tiles(floor_num)
	_spawn_portals(floor_num)
	_spawn_switches(floor_num)


## Skiptrotter's Bypass Puzzle resolves every non-trap switch dungeon-wide, same shape as QuestChicken's bypass; traps are untouched.
func _consume_bypass_puzzle() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not bool(gs.game_constants.get("meta_auto_solve_puzzle_pending", false)):
		return
	var effects: Dictionary = _cave.switch_effects
	if effects.is_empty():
		return
	gs.game_constants["meta_auto_solve_puzzle_pending"] = false
	var solved := false
	for sw_id in effects:
		var eff: Dictionary = effects[sw_id]
		if eff.has("trap") or bool(_active.get(sw_id, false)):
			continue
		_active[sw_id] = true
		var reveal = eff.get("reveal", "")
		if reveal is String and reveal != "":
			_revealed[reveal] = true
		solved = true
	if solved:
		_save_persisted_state()
		if _cave and is_instance_valid(_cave):
			Toast.show_warning(_cave, "The puzzle concedes. Every honest switch in the warren has already been thrown.")


func _apply_flip_tiles(floor_num: int) -> void:
	var effects: Dictionary = _cave.switch_effects
	var floor_atlas: Vector2i = _cave._get_atlas_coords(TileGeneratorScript.TileType.CAVE_FLOOR)
	for sw_id in effects:
		if not bool(_active.get(sw_id, false)):
			continue
		for pair in (effects[sw_id] as Dictionary).get("flip", []):
			_cave.tile_map.set_cell(Vector2i(int(pair[0]), int(pair[1])), 0, floor_atlas)


func _spawn_portals(floor_num: int) -> void:
	var occ: Dictionary = scan_portals(_cave.floor_layouts)
	for ch in occ:
		for entry in (occ[ch] as Array):
			if int(entry["floor"]) != floor_num:
				continue
			var cell: Vector2i = entry["cell"]
			var usable := portal_usable(_cave.switch_effects, _cave.floor_layouts, floor_num, cell, _active)
			var pos := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
			var marker := _create_portal_marker(pos, ch)
			marker.visible = usable
			_container.add_child(marker)
			if not usable:
				continue
			var area := Area2D.new()
			area.name = "Portal_%s_%d_%d" % [ch, cell.x, cell.y]
			area.position = pos
			InteractGeometry.setup_trigger_collision(area, Vector2(24, 24))
			area.body_entered.connect(_on_portal_body_entered.bind(ch, floor_num, cell))
			_container.add_child(area)


func _on_portal_body_entered(body: Node2D, ch: String, from_floor: int, from_cell: Vector2i) -> void:
	if not body.has_method("set_can_move"):
		return
	var dest := portal_destination(_cave.floor_layouts, _cave.portal_links, from_floor, from_cell)
	if dest.is_empty():
		return
	var cell: Vector2i = dest["cell"]
	var landing := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
	_cave.puzzle_warp_to(int(dest["floor"]), landing)


func _spawn_switches(floor_num: int) -> void:
	for sw in scan_switches(_cave.floor_layouts):
		if int(sw["floor"]) != floor_num:
			continue
		var sw_id: String = sw["id"]
		var cell: Vector2i = sw["cell"]
		var pos := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
		var thrown: bool = bool(_active.get(sw_id, false))
		_container.add_child(_create_switch_marker(pos, str(sw["kind"]), thrown))
		if thrown:
			continue  # one-shot: already used
		if sw["kind"] == "plate":
			var area := Area2D.new()
			area.name = "Plate_%s" % sw_id
			area.position = pos
			InteractGeometry.setup_trigger_collision(area, Vector2(28, 28))
			area.body_entered.connect(_on_plate_entered.bind(sw_id))
			_container.add_child(area)
		else:
			var lever := LeverTrigger.new()
			lever.name = "Lever_%s" % sw_id
			lever.switch_id = sw_id
			lever.layer = self
			lever.position = pos
			InteractGeometry.setup_trigger_collision(lever, Vector2(28, 28))
			lever.add_to_group("interactables")
			_container.add_child(lever)


func _on_plate_entered(body: Node2D, sw_id: String) -> void:
	if body.has_method("set_can_move"):
		activate_switch(sw_id)


## Public so LeverTrigger.interact() and plate body_entered can both call it.
func activate_switch(switch_id: String) -> void:
	if _cave == null or bool(_active.get(switch_id, false)):
		return
	var effects: Dictionary = (_cave.switch_effects as Dictionary).get(switch_id, {})
	_active[switch_id] = true
	var sm := get_node_or_null("/root/SoundManager")
	if effects.has("flip"):
		if sm:
			sm.play_ui("door_open")
	if effects.has("reveal"):
		_revealed[str(effects["reveal"])] = true
		if sm:
			sm.play_ui("portal_activate")
	var trap := str(effects.get("trap", ""))
	if trap == "encounter":
		if sm:
			sm.play_ui("surprised_chime")
		var es := get_node_or_null("/root/EncounterSystem")
		if es:
			es.forced_encounter_next_step = true
	elif trap == "warp":
		if sm:
			sm.play_ui("surprised_chime")
	_save_persisted_state()
	rebuild_floor(int(_cave.current_floor))
	if trap == "warp":
		_trap_warp_player()


func _trap_warp_player() -> void:
	var occ: Dictionary = scan_portals(_cave.floor_layouts)
	var all_entries: Array = []
	for ch in occ:
		all_entries.append_array(occ[ch] as Array)
	if all_entries.is_empty():
		return
	var pick: Dictionary = all_entries[randi() % all_entries.size()]
	var cell: Vector2i = pick["cell"]
	var landing := Vector2(cell.x * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2, cell.y * int(_cave.TILE_SIZE) + int(_cave.TILE_SIZE) / 2)
	_cave.puzzle_warp_to(int(pick["floor"]), landing)


## Procedural "glowing vial" marker -- one portal char, one hue, deterministic.
func _create_portal_marker(pos: Vector2, ch: String) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos
	var hue: float = float(ch.unicode_at(0) % 6) / 6.0
	var tint := Color.from_hsv(hue, 0.65, 0.95, 0.85)
	var bg := ColorRect.new()
	bg.size = Vector2(20, 26)
	bg.position = Vector2(-10, -22)
	bg.color = tint
	marker.add_child(bg)
	var label := Label.new()
	label.text = ch.to_upper()
	label.position = Vector2(-6, -20)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	marker.add_child(label)
	marker.ready.connect(func():
		var tween := marker.create_tween()
		tween.set_loops()
		tween.tween_property(bg, "modulate:a", 0.5, 0.6)
		tween.tween_property(bg, "modulate:a", 1.0, 0.6)
	)
	return marker


func _create_switch_marker(pos: Vector2, kind: String, thrown: bool) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos
	var bg := ColorRect.new()
	bg.size = Vector2(24, 24)
	bg.position = Vector2(-12, -12)
	bg.color = Color(0.35, 0.35, 0.35, 0.8) if thrown else Color(0.75, 0.65, 0.15, 0.9)
	marker.add_child(bg)
	var label := Label.new()
	label.text = "P" if kind == "plate" else "L"
	label.position = Vector2(-5, -11)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.BLACK if not thrown else Color.WHITE)
	marker.add_child(label)
	return marker


## Lever = requires interact(), unlike a pressure plate's auto-trigger.
class LeverTrigger extends Area2D:
	var switch_id: String = ""
	var layer: DungeonPuzzleLayer = null

	func interact(_player: Node2D) -> void:
		if layer and is_instance_valid(layer):
			layer.activate_switch(switch_id)
