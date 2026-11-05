extends SceneTree

## Demo segment: overworld gate -> Harmonia -> the fountain -> Greta -> the chapel door and back -> out the south gate.

const Lib := preload("res://tools/demo_walk_lib.gd")

var w


func _pond_is_clear() -> bool:
	for n in w.tree.get_nodes_in_group("interactables"):
		if n is Node2D and "npc_name" in n:
			var c: Vector2i = w.cell_of((n as Node2D).global_position)
			if c.x >= 16 and c.x <= 24 and c.y >= 9 and c.y <= 14:
				return false
	return true


func _init() -> void:
	w = Lib.new(self)
	if not await w.boot("overworld", "village_entrance"):
		quit(1)
		return
	await w.beat(1.5)
	await w.tap("ui_accept")
	await w.beat(0.5)
	if w.map_id() != "harmonia_village" and not w.gl._transition_in_progress:
		w.say("gate press did not enter (player %s) — taking the gate's own transition" % str(w.player().global_position))
		w.gl._on_area_transition("harmonia_village", "entrance")
	if not await w.wait_for_map("harmonia_village"):
		quit(1)
		return
	if str(w.gl._get_pending_story_cutscene()) != "":
		print("[DEMO] ABORT pending story cutscene '%s' in Harmonia" % w.gl._get_pending_story_cutscene())
		quit(1)
		return
	await w.beat(1.2)
	# The fountain: stop on the south shore and look at it — unless a villager stands in the pond (.772), then keep it off camera.
	if _pond_is_clear():
		await w.walk_route(Vector2i(20, 15), w.occupied_cells())
		await w.beat(0.5)
		await w.face("ui_up")
		await w.beat(1.8)
	else:
		w.say("a villager stands in the pond on this build — skipping the fountain beat")
	# Greta the Grey: approach from the east on her own tier, face her, read the pitch.
	var greta: Node2D = w.find_npc("Greta the Grey")
	if greta:
		await w.walk_route(Vector2i(6, 21), w.occupied_cells(greta))
		await w.walk_to_px(greta.global_position + Vector2(40, 16), 6.0)
		await w.face("ui_left")
		await w.beat(0.4)
		await w.tap("ui_accept")
		await w.beat(0.3)
		if w.dialogue_open():
			var lines: int = greta.dialogue_lines.size() if "dialogue_lines" in greta else 6
			var presses: int = await w.read_dialogue([2.6, 3.0], 0.8, lines + 2)
			w.say("Greta: %d press(es) to close" % presses)
		else:
			w.say("WARNING Greta's dialogue did not open")
	else:
		w.say("WARNING no Greta the Grey in this Harmonia")
	await w.beat(0.8)
	# The chapel door beside her: step into its approach, face it, press — the door opens and we go in.
	var door: Node2D = w.scene().get_node_or_null("Buildings/ChapelDoor")
	var door_px: Vector2 = door.global_position + Vector2(0, 36) if door else Vector2(256, 692)
	await w.walk_to_px(door_px, 6.0)
	await w.face("ui_up")
	await w.beat(0.3)
	await w.tap("ui_accept")
	if await w.wait_for_map("harmonia_chapel", 8.0):
		await w.beat(1.2)
		var in_at: Vector2 = w.player().global_position
		await w.walk_to_px(in_at + Vector2(0, -72), 3.0)
		await w.beat(1.6)
		var exit_node: Node2D = w.scene().get_node_or_null("Transitions/Exit")
		var out_px: Vector2 = exit_node.global_position if exit_node else in_at + Vector2(0, 48)
		await w.walk_to_px(Vector2(out_px.x, w.player().global_position.y), 3.0)
		await w.walk_to_px(out_px + Vector2(0, 24), 6.0, func(): return w.map_id() != "harmonia_chapel")
		if not await w.wait_for_map("harmonia_village"):
			quit(1)
			return
	else:
		w.say("WARNING the chapel door did not open")
	await w.beat(0.8)
	# Out through the south gate.
	await w.walk_route(Vector2i(19, 27), w.occupied_cells(), func(): return w.map_id() != "harmonia_village")
	if not await w.wait_for_map("overworld"):
		quit(1)
		return
	await w.beat(2.0)
	w.release_all()
	print("[DEMO] segment done")
	quit(0)
