extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")

## Before/after proof for the pixel battle numbers (struktured 2026-11-02: "more pixel 16 bit esque"). A real battle
## through GameLoop, then every popup kind spawned through the battle's own BattleResultsDisplay at the real sprites,
## captured across the motion. Same script on any tree, so main gives the "before". Run via damage_number_shots.sh.
## Writes <out>/seq_NN.png (default res://tmp/damage_numbers).

const TIMES := [0.03, 0.08, 0.14, 0.22, 0.35, 0.55]


func _init() -> void:
	await process_frame
	await process_frame
	var out := "res://tmp/damage_numbers"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("[SHOT] FAIL: no GameState")
		quit(1)
		return
	gs.current_world = 1
	var hints = load("res://src/ui/TutorialHints.gd")
	for id in (hints.HINTS.keys() if hints and ("HINTS" in hints) else []):
		gs.game_constants["tutorial_" + str(id)] = true
	DirAccess.make_dir_recursive_absolute(out)
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	await gl._start_battle_async(["goblin", "goblin", "goblin"], true)
	var scene: Node = _find(root)
	if scene == null:
		print("[SHOT] FAIL: no BattleScene")
		quit(1)
		return
	await create_timer(1.0, true, false, true).timeout
	_hide_menus(root)
	var rd = scene._results_display
	var bm: Node = root.get_node("BattleManager")
	var e: Array = bm.enemy_party
	var p: Array = scene.party_members
	rd.spawn_damage_number(rd._get_combatant_sprite_position(e[0]), 12, false, false)
	rd.spawn_damage_number(rd._get_combatant_sprite_position(e[1]), 248, false, true)
	rd.spawn_miss_number(rd._get_combatant_sprite_position(e[2]))
	rd.spawn_damage_number(rd._get_combatant_sprite_position(p[0]), 64, false, false)
	rd.spawn_damage_number(rd._get_combatant_sprite_position(p[1]), 35, true, false)
	rd.spawn_damage_number(rd._get_combatant_sprite_position(p[2]), 18, true, false, "mp")
	rd.spawn_damage_number(rd._get_combatant_sprite_position(p[3]), 1, true, false, "ap")
	rd.spawn_banner(rd._get_combatant_sprite_position(p[4]), "IMMUNE")
	var ok := true
	var t0 := Time.get_ticks_msec()
	for f in TIMES.size():
		var wait_ms: int = int(TIMES[f] * 1000.0) - (Time.get_ticks_msec() - t0)
		if wait_ms > 0:
			await create_timer(wait_ms / 1000.0, true, false, true).timeout
		ok = ShotGuard.save_or_refuse(root.get_viewport().get_texture().get_image(), ProjectSettings.globalize_path(out + "/seq_%02d.png" % f)) and ok
	print("[SHOT] numbers spawned 8 · frames %d · ok %s" % [TIMES.size(), ok])
	quit(0 if ok else 1)


func _find(n: Node) -> Node:
	if n.get_script() and str(n.get_script().resource_path).ends_with("BattleScene.gd"):
		return n
	for c in n.get_children():
		var r := _find(c)
		if r:
			return r
	return null


func _hide_menus(n: Node) -> void:
	for c in n.get_children():
		if c is Control and (c.name.contains("Menu") or c.name.contains("Command")):
			c.visible = false
		_hide_menus(c)
