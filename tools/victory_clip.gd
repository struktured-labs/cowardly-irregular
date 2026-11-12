extends SceneTree

## A clip of the victory beat (VictoryOverlay) over a REAL battle, for --write-movie capture at a fixed fps.
## Run through tools/victory_clip.sh (it owns the sandbox, xvfb, the pad jail and the encode).
## Args: --rank=<one-shot rank, e.g. S; empty for none> --boss (bill a boss: the BOSS grade) --seconds=<length>
## --text_size=<Text Size multiplier, e.g. 2.0> --foes=<how many goblins, default 1>

func _init() -> void:
	var rank := ""
	var boss := false
	var seconds := 3.4
	var text_size := 1.0
	var foes := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rank="):
			rank = a.get_slice("=", 1)
		elif a == "--boss":
			boss = true
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--text_size="):
			text_size = float(a.get_slice("=", 1))
		elif a.begins_with("--foes="):
			foes = clampi(int(a.get_slice("=", 1)), 1, 5)
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	if gs and "text_size_scale" in gs:
		gs.text_size_scale = text_size
	var hints = load("res://src/ui/TutorialHints.gd")
	if gs and hints and ("HINTS" in hints):
		for id in hints.HINTS.keys():
			gs.game_constants["tutorial_" + str(id)] = true
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	var roster: Array = []
	for i in foes:
		roster.append("goblin")
	await gl._start_battle_async(roster, true)
	var scene := _find(root)
	if scene == null:
		print("[VCLIP] FAIL: no BattleScene")
		quit(1)
		return
	for i in 30:
		await process_frame
	var bm = root.get_node("BattleManager")
	bm.current_state = bm.BattleState.VICTORY
	var menu = scene.get("active_win98_menu")
	if menu and is_instance_valid(menu):
		menu.queue_free()
		scene.active_win98_menu = null
	for e in scene.test_enemies:
		if boss and is_instance_valid(e):
			e.set_meta("is_boss", true)
			e.set_meta("monster_type", "cave_rat_king")
			e.combatant_name = "Cave Rat King"
	for s in scene.enemy_sprite_nodes:
		if is_instance_valid(s):
			s.visible = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	await process_frame
	var cr: Array = []
	for m in scene.party_members:
		cr.append({"name": m.combatant_name, "job_name": str(m.job.get("id", "fighter")) if m.job is Dictionary else "fighter",
			"is_alive": true, "exp_gained": 120, "job_exp_before": 30, "exp_to_next": 200, "leveled_up": false,
			"job_level": 3, "job_exp": 150})
	var bonuses: Array = []
	if rank != "":
		bonuses.append({"type": "one_shot", "rank": rank, "multiplier": 3.0})
	## As at a real win: the victory bed (and the boss stinger over it) starts BEFORE the overlay, so the letter ticks
	## key to what the player hears. Without this the clip carried the battle bed and untransposed ticks (cowir-music 23641).
	scene.play_victory_music(boss)
	for i in 6:
		await process_frame
	var sm = root.get_node_or_null("SoundManager")
	var under := ""
	if sm and sm._music_player and sm._music_player.stream:
		under = str(sm._music_player.stream.resource_path).get_file().get_basename()
	print("[VCLIP] under=%s" % under)
	var overlay = load("res://src/battle/VictoryOverlay.gd").new()
	overlay.name = "VictoryResults"
	scene.add_child(overlay)
	overlay.build({"char_results": cr, "total_gold": 40, "item_drops": [], "bonuses": bonuses, "injuries": []}, scene)
	print("[VCLIP] built rank=%s boss=%s grade=%d flourish=%s complete=%s time_scale=%.3f" % [rank, boss,
		overlay._victory_grade(), overlay.wants_flourish(scene), overlay.is_complete(), Engine.time_scale])
	## Frames, not a game-time timer: under --fixed-fps 30 a frame is 1/30 s of VIDEO, whatever the battle speed.
	for i in int(round(seconds * 30.0)):
		await process_frame
	print("[VCLIP] done")
	quit(0)


func _find(node: Node) -> Node:
	if node.has_method("_on_advance_queue_changed"):
		return node
	for child in node.get_children():
		var hit := _find(child)
		if hit:
			return hit
	return null
