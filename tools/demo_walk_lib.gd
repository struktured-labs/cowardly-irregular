extends RefCounted

## Demo walker (cowir-main 22262): real ui_* InputActions via Input.parse_input_event (OverworldPlayer reads Input.get_vector), paced in video time.

const PREP_PATH := "res://tools/demo_prep.gd"
const DIRS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const ARRIVE_PX := 5.0

var tree: SceneTree
var gl: Node
var _held := ""


func _init(t: SceneTree) -> void:
	tree = t


func say(msg: String) -> void:
	print("[DEMO] walk: " + msg)


func beat(s: float) -> void:
	await tree.create_timer(s, true, false, true).timeout


func _send(action: String, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)


func hold(action: String) -> void:
	if action == _held:
		return
	if _held != "":
		_send(_held, false)
	_held = action
	if action != "":
		_send(action, true)


func release_all() -> void:
	hold("")
	for a in DIRS + ["ui_accept", "ui_cancel", "dash"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func tap(action: String, s: float = 0.12) -> void:
	release_all()
	_send(action, true)
	await beat(s)
	_send(action, false)
	await beat(0.06)


## Boot GameLoop onto map_id at spawn, with the shared demo prep applied; false = abort the segment.
func boot(map_id: String, spawn: String) -> bool:
	await tree.process_frame
	await tree.process_frame
	var root := tree.root
	gl = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await tree.process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await tree.process_frame
	gl._create_party()
	var prep = load(PREP_PATH) if ResourceLoader.exists(PREP_PATH) else null
	if prep:
		prep.apply(root, gl)
	else:
		say("WARNING no %s — applying the minimum myself" % PREP_PATH)
		_minimal_prep(root)
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	for m in ["overworld", "harmonia_village", map_id]:
		if not settle_story(m):
			return false
	gl._set_current_map_id(map_id)
	gl._spawn_point = spawn
	await gl._start_exploration()
	for i in 10:
		await tree.process_frame
	var ilm = root.get_node("InputLockManager")
	if ilm.is_locked():
		print("[DEMO] ABORT input locked after boot: %s" % str(ilm.get_active_locks()))
		return false
	say("booted on %s at '%s' (player %s)" % [map_id, spawn, str(player().global_position) if player() else "?"])
	return true


## Mark each beat pending on `m` complete by its OWN completion flag (logged), so nothing plays over the walk; false = abort.
func settle_story(m: String) -> bool:
	var gs = tree.root.get_node("GameState")
	var real: String = gl._current_map_id
	gl._current_map_id = m
	var ok := true
	for i in 16:
		var id := str(gl._get_pending_story_cutscene())
		if id == "":
			break
		var flag: String = str(gl._CUTSCENE_COMPLETION_FLAGS.get(id, ""))
		if id.contains("_spotlight_") and gs.game_constants.get(flag, false):
			flag = "cutscene_flag_spotlight_unlocked_" + id.get_slice("_spotlight_", 1).get_slice("_", 0)
		if flag == "" or gs.game_constants.get(flag, false):
			print("[DEMO] ABORT pending story cutscene '%s' on %s has no settable completion flag" % [id, m])
			ok = false
			break
		gs.game_constants[flag] = true
		say("settled '%s' on %s via %s" % [id, m, flag])
	gl._current_map_id = real
	return ok


func _minimal_prep(root: Node) -> void:
	var gs = root.get_node_or_null("GameState")
	var hints = load("res://src/ui/TutorialHints.gd")
	for id in hints.HINTS.keys():
		gs.game_constants["tutorial_" + str(id)] = true
	for f in ["cutscene_flag_chapter1_complete", "cutscene_flag_world1_harmonia_npcs_complete"]:
		gs.game_constants[f] = true
	for k in ["llm_enabled", "party_llm_dialogue_enabled", "boss_llm_strategy_enabled", "llm_rebalance_enabled"]:
		if k in gs:
			gs.set(k, false)
	var llm = root.get_node_or_null("LLMService")
	if llm and "llm_enabled" in llm:
		llm.llm_enabled = false


func scene() -> Node:
	return gl._exploration_scene if gl and is_instance_valid(gl._exploration_scene) else null


func player() -> Node2D:
	var s := scene()
	return s.get("player") if s and "player" in s else null


func map_id() -> String:
	return str(gl._current_map_id)


func in_battle() -> bool:
	return gl != null and int(gl.current_state) == int(gl.LoopState.BATTLE)


func _find(n: Node, prefix: String) -> Node:
	if str(n.name).begins_with(prefix):
		return n
	for c in n.get_children():
		var hit := _find(c, prefix)
		if hit:
			return hit
	return null


## Wait (video time) until the map id is `want` and its scene settled; false on timeout.
func wait_for_map(want: String, timeout_s: float = 12.0) -> bool:
	var t := 0.0
	while t < timeout_s:
		if map_id() == want and not gl._transition_in_progress and player() != null:
			await beat(0.3)
			return true
		await beat(0.1)
		t += 0.1
	say("timed out waiting for map '%s' (on '%s')" % [want, map_id()])
	return false


func tile() -> int:
	var s := scene()
	return int(s.TILE_SIZE) if s and "TILE_SIZE" in s else 32


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / tile()), floori(p.y / tile()))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * tile(), (c.y + 0.5) * tile())


## The step rule the scene itself enforces: a village's _can_step, else an open TileMap cell.
func can_step(a: Vector2i, b: Vector2i, blocked: Dictionary) -> bool:
	if blocked.has(b):
		return false
	var s := scene()
	if s.has_method("_can_step"):
		return s._can_step(a, b)
	if s.has_method("_is_cell_walkable"):
		return s._is_cell_walkable(b)
	var tm = s.get("tile_map")
	if tm == null:
		return true
	var td = tm.get_cell_tile_data(b)
	return td != null and td.get_collision_polygons_count(0) == 0


## Cells under every standing NPC/interactable body, so the route never walks into a villager.
func occupied_cells(except: Node = null) -> Dictionary:
	var out := {}
	for n in tree.get_nodes_in_group("interactables"):
		if n == except or not (n is Node2D) or not ("npc_name" in n):
			continue
		var p: Vector2 = (n as Node2D).global_position
		var cx := roundi(p.x / tile())
		var cy := roundi(p.y / tile())
		for c in [Vector2i(cx - 1, cy - 1), Vector2i(cx, cy - 1), Vector2i(cx - 1, cy), Vector2i(cx, cy)]:
			out[c] = true
	return out


## BFS from the player's cell to `goal`; returns the cell path (turn points only), or [] if unreachable.
func route(goal: Vector2i, blocked: Dictionary = {}, max_nodes: int = 40000) -> Array:
	var start := cell_of(player().global_position)
	blocked.erase(start)
	blocked.erase(goal)
	var prev := {start: start}
	var q := [start]
	var qi := 0
	while qi < q.size() and qi < max_nodes:
		var c: Vector2i = q[qi]
		qi += 1
		if c == goal:
			break
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if prev.has(n) or not can_step(c, n, blocked):
				continue
			prev[n] = c
			q.append(n)
	if not prev.has(goal):
		return []
	var path := [goal]
	while path[0] != start:
		path.push_front(prev[path[0]])
	var turns := []
	for i in path.size():
		if i == 0 or i == path.size() - 1:
			turns.append(path[i])
			continue
		var a: Vector2i = path[i] - path[i - 1]
		var b: Vector2i = path[i + 1] - path[i]
		if a != b:
			turns.append(path[i])
	return turns


## Hold one direction toward pixel `p` until within ARRIVE_PX on that axis; x first then y ("L" moves read as a person).
func walk_to_px(p: Vector2, timeout_s: float = 12.0, stop_if: Callable = Callable()) -> bool:
	var t := 0.0
	var last := player().global_position
	var still := 0.0
	for axis in [0, 1]:
		while t < timeout_s:
			if stop_if.is_valid() and stop_if.call():
				release_all()
				return true
			var pl := player()
			if pl == null:
				release_all()
				return false
			var d := p - pl.global_position
			var v: float = d.x if axis == 0 else d.y
			if absf(v) <= ARRIVE_PX:
				break
			if axis == 0:
				hold("ui_right" if v > 0 else "ui_left")
			else:
				hold("ui_down" if v > 0 else "ui_up")
			await tree.physics_frame
			var dt := 1.0 / float(Engine.physics_ticks_per_second)
			t += dt
			still = still + dt if pl.global_position.distance_to(last) < 0.2 else 0.0
			last = pl.global_position
			if still > 1.0:
				say("stuck at %s heading %s" % [str(pl.global_position), str(p)])
				release_all()
				return false
	release_all()
	return t < timeout_s


func walk_route(goal: Vector2i, blocked: Dictionary = {}, stop_if: Callable = Callable()) -> bool:
	var cells := route(goal, blocked)
	if cells.is_empty():
		say("no route to %s" % str(goal))
		return false
	say("route to %s: %d turn(s)" % [str(goal), cells.size()])
	for c in cells.slice(1):
		if not await walk_to_px(cell_center(c), 15.0, stop_if):
			return false
		if stop_if.is_valid() and stop_if.call():
			return true
	return true


## Turn to face a direction without walking off the spot (a 1-frame tap).
func face(action: String) -> void:
	_send(action, true)
	await tree.physics_frame
	await tree.physics_frame
	_send(action, false)
	await beat(0.15)


func dialogue_open() -> bool:
	var ilm = tree.root.get_node_or_null("InputLockManager")
	return ilm != null and ilm.is_locked()


## Press Confirm through an open dialogue at reading pace; returns presses used.
func read_dialogue(first_lines_s: Array, rest_s: float = 0.9, cap: int = 14) -> int:
	var n := 0
	for s in first_lines_s:
		await _typing_done()
		await beat(s)
		if not dialogue_open():
			return n
		await tap("ui_accept")
		n += 1
	while n < cap:
		await beat(rest_s)
		if not dialogue_open():
			break
		await tap("ui_accept")
		n += 1
		await beat(0.25)
	return n


func find_npc(npc_name: String) -> Node2D:
	for n in tree.get_nodes_in_group("interactables"):
		if n is Node2D and ("npc_name" in n and str(n.npc_name) == npc_name or str(n.name) == npc_name):
			return n
	return null


## Every cell reachable from the player within max_dist steps, with its step distance.
func reach(max_dist: int, blocked: Dictionary = {}) -> Dictionary:
	var start := cell_of(player().global_position)
	var dist := {start: 0}
	var q := [start]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		if dist[c] >= max_dist:
			continue
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if dist.has(n) or not can_step(c, n, blocked):
				continue
			dist[n] = dist[c] + 1
			q.append(n)
	return dist


## Wait (bounded) until no visible dialogue box is still typing its line.
func _typing_done(cap_s: float = 8.0) -> void:
	var t := 0.0
	while t < cap_s and _any_typing(tree.root):
		await beat(0.05)
		t += 0.05


func _any_typing(n: Node) -> bool:
	if n.get("_is_typing") == true and (not ("visible" in n) or n.visible):
		return true
	for c in n.get_children():
		if _any_typing(c):
			return true
	return false
