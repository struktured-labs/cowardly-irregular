extends SceneTree

## Before/after frames of the post-battle results (VictoryOverlay) over a REAL battle, with fixed
## results so two runs are comparable: five members, two level-ups (one learns an ability), one KO,
## gold + items + a bonus. Run through tools/victory_card_shots.sh (sandboxed). Arg: an output label.
## Writes tmp/victory_card/<label>_entering.png (mid-entrance) and <label>_settled.png.

const OUT := "res://tmp/victory_card"


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
	if scene == null:
		print("[SHOT] FAIL: no BattleScene")
		quit(1)
		return
	for i in 30:
		await process_frame
	## As at a real win: the battle is over, the foes are gone, no menu and no watchdog respawning one.
	var bm = root.get_node("BattleManager")
	bm.current_state = bm.BattleState.VICTORY
	var menu = scene.get("active_win98_menu")
	if menu and is_instance_valid(menu):
		menu.queue_free()
		scene.active_win98_menu = null
	for s in scene.enemy_sprite_nodes:
		if is_instance_valid(s):
			s.visible = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	await process_frame
	var names: Array = []
	var jobs: Array = []
	for m in scene.party_members:
		names.append(m.combatant_name)
		jobs.append(str(m.job.get("id", "fighter")) if m.job is Dictionary else "fighter")
	var cr: Array = []
	for i in names.size():
		var d := {"name": names[i], "job_name": jobs[i], "is_alive": true, "exp_gained": 209,
			"job_exp_before": 40 + 15 * i, "exp_to_next": 100 * (i + 2), "leveled_up": false,
			"job_level": i + 2, "job_exp": 0}
		if i == 0:
			d["leveled_up"] = true
			d["job_level"] = 11
			d["job_exp"] = 30
			d["stat_gains"] = {"HP": 46, "MP": 2, "ATK": 5, "DEF": 3, "SPD": 2}
		if i == 2:
			d["leveled_up"] = true
			d["job_level"] = 6
			d["job_exp"] = 120
			d["stat_gains"] = {"HP": 22, "MP": 9, "MAG": 4}
			d["learned_abilities"] = ["fira"]
		if i == 3:
			d["is_alive"] = false
			d["exp_gained"] = 0
		cr.append(d)
	var results := {"char_results": cr, "total_gold": 75,
		"item_drops": [{"item": "potion", "name": "Potion", "qty": 2}],
		"bonuses": [{"type": "one_shot", "multiplier": 3.0}], "injuries": []}
	var overlay = load("res://src/battle/VictoryOverlay.gd").new()
	overlay.name = "VictoryResults"
	scene.add_child(overlay)
	overlay.build(results, scene)
	await create_timer(0.9).timeout
	await _save("%s/%s_entering.png" % [OUT, label])
	await create_timer(0.55).timeout
	await _save("%s/%s_cascade.png" % [OUT, label])
	await create_timer(4.0).timeout
	await _save("%s/%s_settled.png" % [OUT, label])
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
