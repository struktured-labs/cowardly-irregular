extends SceneTree

## A real battle with a named enemy trio, for name-label occlusion work. Run through
## tools/enemy_label_shots.sh (sandboxed). Args: <label> [monster ids...] (default slime bat goblin).
## Writes tmp/enemy_labels/<label>.png plus a 2x crop band across the enemy row.

const OUT := "res://tmp/enemy_labels"


func _init() -> void:
	await process_frame
	await process_frame
	var args := OS.get_cmdline_user_args()
	var label: String = args[0] if args.size() > 0 else "shot"
	var ids: Array = []
	for i in range(1, args.size()):
		ids.append(str(args[i]))
	if ids.is_empty():
		ids = ["slime", "bat", "goblin"]
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var hints = load("res://src/ui/TutorialHints.gd")
	if gs and hints and ("HINTS" in hints):
		for id in hints.HINTS.keys():
			gs.game_constants["tutorial_" + str(id)] = true
	DirAccess.make_dir_recursive_absolute(OUT)
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	await gl._start_battle_async(ids, true)
	var scene := _find(root)
	if scene == null:
		print("[SHOT] FAIL: no BattleScene")
		quit(1)
		return
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	for i in 120:
		await process_frame
	var menu = scene.get("active_win98_menu")
	if menu and is_instance_valid(menu):
		menu.visible = false
	await create_timer(0.6).timeout
	await _save("%s/%s.png" % [OUT, label])
	for i in scene.enemy_sprite_nodes.size():
		var s = scene.enemy_sprite_nodes[i]
		if not is_instance_valid(s):
			continue
		var lbl = s.get_node_or_null("NameLabel")
		print("[SHOT] %d %s sprite_pos=%s scale=%s z=%d | label='%s' z=%d gpos=%s" % [
			i, str(scene.test_enemies[i].combatant_name), str(s.global_position), str(s.scale), s.z_index,
			str(lbl.text) if lbl else "-", lbl.z_index if lbl else -1, str(lbl.global_position) if lbl else "-"])
	print("[SHOT] done %s" % label)
	quit(0)


func _save(path: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] SCREEN %s %dx%d" % [path, img.get_width(), img.get_height()])


func _find(node: Node) -> Node:
	if node.has_method("_on_advance_queue_changed"):
		return node
	for child in node.get_children():
		var hit := _find(child)
		if hit:
			return hit
	return null
