extends SceneTree

## A W1 boss's signature in a REAL battle: the boss's own sheet, the real party, its boss backdrop and Mode 7 floor,
## the title card and camera push, then the sequence. cowir-main 2026-11-02: the fx_clip stage undersold it.
##   tools/boss_signature_shots.sh [boss_id ...]   (default: every W1 boss with an fx_signature)
## Args: --boss=<monster id> --speed=<engine time_scale, default 0.375>. Recorded by the wrapper with --write-movie.

func _init() -> void:
	var boss_id := "chancellor_mordaine"
	var speed := 0.375
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boss="):
			boss_id = a.get_slice("=", 1)
		elif a.begins_with("--speed="):
			speed = float(a.get_slice("=", 1))
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("[BOSSSHOT] FAIL: no GameState")
		quit(1)
		return
	if "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var hints = load("res://src/ui/TutorialHints.gd")
	for id in (hints.HINTS.keys() if hints and ("HINTS" in hints) else []):
		gs.game_constants["tutorial_" + str(id)] = true
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	await gl._start_battle_async([boss_id], true)
	var scene: Node = _find(root)
	if scene == null:
		print("[BOSSSHOT] FAIL: no BattleScene")
		quit(1)
		return
	# The boss battle starts after its transition and intro: wait for BattleManager to hold the boss, not a fixed time.
	var bm = root.get_node("BattleManager")
	var deadline := Time.get_ticks_msec() + 25000
	while bm.enemy_party.size() == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.0, true, false, true).timeout
	var boss = bm.enemy_party[0] if bm.enemy_party.size() > 0 else null
	if boss == null:
		print("[BOSSSHOT] FAIL: no boss in the enemy party")
		quit(1)
		return
	var sig := ""
	var entry = scene._load_monsters_data().get(boss_id, {})
	if entry is Dictionary:
		sig = str(entry.get("fx_signature", ""))
	if sig == "":
		print("[BOSSSHOT] FAIL: %s has no fx_signature" % boss_id)
		quit(1)
		return
	scene._set_battle_time_scale(speed)
	# The capture lands mid-selection; the open command menu would sit over the spectacle.
	if scene._command_menu:
		scene._command_menu.close_win98_menu()
	var ability: Dictionary = root.get_node("JobSystem").get_ability(sig)
	var targets: Array = []
	if str(ability.get("target_type", "")) in ["self"]:
		targets = [boss]
	else:
		for m in bm.player_party:
			if m.is_alive:
				targets.append(m)
		if str(ability.get("target_type", "")).begins_with("single") and targets.size() > 1:
			targets = [targets[0]]
	print("[BOSSSHOT] %s casts %s (%s) at %d target(s), speed %s" % [boss_id, sig, str(ability.get("name", "")), targets.size(), str(speed)])
	scene._on_action_executing(boss, {"type": "ability", "ability_id": sig, "targets": targets})
	var total: float = 0.55 + float(scene.sequence_total("sig_" + boss_id)) + 0.6
	# The menu watchdog re-opens a closed menu on purpose (so a battle cannot wedge), so hide it every frame instead.
	var until := Time.get_ticks_msec() + int((total / maxf(Engine.time_scale, 0.01) + 0.8) * 1000.0)
	while Time.get_ticks_msec() < until:
		var menu = scene.get("active_win98_menu")
		if menu != null and is_instance_valid(menu) and menu.has_method("set_chain_visible"):
			menu.set_chain_visible(false)
		await process_frame
	print("[BOSSSHOT] done %s" % boss_id)
	quit(0)


func _find(n: Node) -> Node:
	if n.get_script() and str(n.get_script().resource_path).ends_with("BattleScene.gd"):
		return n
	for c in n.get_children():
		var f := _find(c)
		if f:
			return f
	return null
