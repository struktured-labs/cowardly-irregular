extends SceneTree

## A clip of a monster death or the escape beat over a REAL battle, for --write-movie capture at a fixed fps.
## Run through tools/death_clip.sh (it owns the sandbox, xvfb, the pad jail and the encode).
## Args: --mode=compare  three goblins die at once, one per style (crt_off · pixel_dissolve · glitch_out)
##       --mode=live     the goblins die through the scene's own _on_enemy_died, so the same command clips
##                       the shipped death on an older tree (the "before") and the world's style on this one
##       --mode=flee     the party escapes (BattleScene.play_escape_beat where the tree has it)
##       --seconds=<length kept by the encode>

func _init() -> void:
	var mode := "compare"
	var seconds := 3.4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
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
	await gl._start_battle_async(["goblin", "goblin", "goblin"], true)
	var scene := _find(root)
	if scene == null:
		print("[DCLIP] FAIL: no BattleScene")
		quit(1)
		return
	for i in 30:
		await process_frame
	var menu = scene.get("active_win98_menu")
	if menu and is_instance_valid(menu):
		menu.queue_free()
		scene.active_win98_menu = null
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	## Waits in REAL (video) seconds: the battle runs below 1x, so a plain game-time timer ran ~2.7x long and
	## the encode's last-N-seconds window missed the deaths.
	await create_timer(0.6 * Engine.time_scale).timeout
	print("[DCLIP] built mode=%s" % mode)
	match mode:
		"compare":
			var styles := ["crt_off", "pixel_dissolve", "glitch_out"]
			var fx = load("res://src/battle/EnemyDeathFx.gd")
			for i in mini(styles.size(), scene.enemy_sprite_nodes.size()):
				var s = scene.enemy_sprite_nodes[i]
				if is_instance_valid(s):
					fx.play(s, styles[i])
					print("[DCLIP] enemy %d -> %s" % [i, styles[i]])
		"live":
			for i in scene.test_enemies.size():
				var e = scene.test_enemies[i]
				if is_instance_valid(e):
					e.is_alive = false
					e.current_hp = 0
				scene._on_enemy_died(i)
				await create_timer(0.35 * Engine.time_scale).timeout
			## The stagger is part of the kept window, so the clip still opens 0.6 s before the first death.
			seconds = maxf(seconds - 0.35 * scene.test_enemies.size(), 1.0)
		"flee":
			if scene.has_method("play_escape_beat"):
				scene.play_escape_beat()
				print("[DCLIP] escape beat")
			else:
				print("[DCLIP] this tree has no escape beat (the before)")
	await create_timer(seconds * Engine.time_scale).timeout
	print("[DCLIP] done")
	quit(0)


func _find(node: Node) -> Node:
	if node.has_method("_on_advance_queue_changed"):
		return node
	for child in node.get_children():
		var hit := _find(child)
		if hit:
			return hit
	return null
