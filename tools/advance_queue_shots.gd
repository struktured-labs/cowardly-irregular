extends SceneTree

## Frames of the Advance queue cards over a REAL battle: the live menu with 0, 2 and 4 actions queued,
## then one undo. Run through tools/advance_queue_shots.sh (sandboxed). Arg: an output label.
## Writes tmp/advance_queue/<label>_q0.png, _q2, _q4, _undo.

const OUT := "res://tmp/advance_queue"


func _init() -> void:
	await process_frame
	await process_frame
	var label: String = "shot"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		label = args[0]
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
	await gl._start_battle_async(["goblin", "goblin"], true)
	var scene := _find(root)
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	var menu = null
	for i in 400:
		await process_frame
		menu = scene.get("active_win98_menu")
		if menu and is_instance_valid(menu) and menu.visible:
			break
	if menu == null or not is_instance_valid(menu):
		print("[SHOT] FAIL: no command menu")
		quit(1)
		return
	menu.set_max_queue_size(5)
	await create_timer(0.6).timeout
	await _save("%s/%s_q0.png" % [OUT, label])
	var entries := [
		{"id": "attack_0", "data": {"target_idx": 0, "action": "attack"}, "label": "Goblin A"},
		{"id": "ability_fire_enemy_1", "data": {"ability_id": "fire", "target_idx": 1, "target_type": "enemy"}, "label": "Goblin B"},
		{"id": "item_potion_ally_2", "data": {"item_id": "potion", "target_idx": 2, "target_type": "ally"}, "label": "Rogue"},
		{"id": "ability_fire_enemy_0", "data": {"ability_id": "fire", "target_idx": 0, "target_type": "enemy"}, "label": "Goblin A"},
	]
	for i in entries.size():
		menu._queue_current_action(entries[i])
		await create_timer(0.35).timeout
		if i == 1:
			await _save("%s/%s_q2.png" % [OUT, label])
	await create_timer(0.3).timeout
	await _save("%s/%s_q4.png" % [OUT, label])
	menu._undo_last_action()
	await create_timer(0.4).timeout
	await _save("%s/%s_undo.png" % [OUT, label])
	## A lower PC's menu (the Cleric's sits ~y 300+): the cascade has room to grow up-right there.
	menu._cancel_all_queued()
	await create_timer(0.3).timeout
	menu.position.y = 330.0
	await process_frame
	for e in entries:
		menu._queue_current_action(e)
		await create_timer(0.3).timeout
	await create_timer(0.3).timeout
	await _save("%s/%s_lower_q4.png" % [OUT, label])
	## Part 2: commit the lowered menu's queue and catch the run mid-execution.
	menu._confirm_turn_with_queue()
	var waited := 0.0
	while waited < 20.0:
		var rc = scene.get_node_or_null("AdvanceRunCards")
		if rc and rc.is_running():
			break
		await create_timer(0.1).timeout
		waited += 0.1
	print("[SHOT] run live after %.1fs" % waited)
	for k in 3:
		await create_timer(0.35).timeout
		await _save("%s/%s_run%d.png" % [OUT, label, k])
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
