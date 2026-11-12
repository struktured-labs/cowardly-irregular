extends SceneTree

## A clip of one ability cast over a REAL battle, for --write-movie capture at a fixed fps: the mage's (or any job's)
## cast through BattleManager's own execution path, so the clip shows what a player sees and hears.
## Run through tools/cast_clip.sh (it owns the sandbox, xvfb, the pad jail and the encode).
## Args: --ability=<id> --job=<caster job, default mage> --foes=<n, default 3> --level=<party level, default 16>
##       --seconds=<length kept by the encode> --speed=<engine time_scale, default: the game's own>

func _init() -> void:
	var ability := "fire"
	var job := "mage"
	var foes := 3
	var level := 16
	var seconds := 3.4
	var speed := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ability="):
			ability = a.get_slice("=", 1)
		elif a.begins_with("--job="):
			job = a.get_slice("=", 1)
		elif a.begins_with("--foes="):
			foes = int(a.get_slice("=", 1))
		elif a.begins_with("--level="):
			level = int(a.get_slice("=", 1))
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--speed="):
			speed = float(a.get_slice("=", 1))
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
	var js = root.get_node("JobSystem")
	var caster: Combatant = null
	for m in gl.party:
		m.job_level = level
		js.learn_abilities_for_level(m, level)
		m.recalculate_stats()
		m.current_hp = m.max_hp
		m.current_mp = m.max_mp
		if m.job and str(m.job.get("id", "")) == job:
			caster = m
	if caster == null:
		print("[CCLIP] FAIL: no %s in the party" % job)
		quit(1)
		return
	var ids: Array = []
	for i in foes:
		ids.append("goblin")
	await gl._start_battle_async(ids, true)
	var scene := _find(root)
	if scene == null:
		print("[CCLIP] FAIL: no BattleScene")
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
	if speed > 0.0:
		Engine.time_scale = speed
	var bm = root.get_node("BattleManager")
	## Foes that survive the cast, so the clip shows the hit and not three deaths on top of it.
	for e in bm.enemy_party:
		e.max_hp = 999999
		e.current_hp = 999999
	var data: Dictionary = js.get_ability(ability)
	var targets: Array = bm.enemy_party.duplicate() if str(data.get("target_type", "")) == "all_enemies" else [bm.enemy_party[0]]
	if str(data.get("target_type", "")) in ["self", "single_ally", "all_allies"]:
		targets = [caster] if str(data.get("target_type", "")) != "all_allies" else bm.player_party.duplicate()
	## An ally spell is filmed on ANOTHER member, so the light is seen to travel; a revive on a member felled for the shot.
	if str(data.get("target_type", "")) in ["single_ally", "dead_ally"]:
		for m in bm.player_party:
			if m != caster:
				targets = [m]
				break
		if str(data.get("target_type", "")) == "dead_ally":
			(targets[0] as Combatant).current_hp = 1
			(targets[0] as Combatant).take_damage(999999)
			await create_timer(1.2 * Engine.time_scale).timeout
		elif ability in ["cure", "cura", "regen", "esuna"]:
			(targets[0] as Combatant).current_hp = maxi(1, int((targets[0] as Combatant).max_hp * 0.3))
			if ability == "esuna":
				(targets[0] as Combatant).add_status("poison", 3)
	await create_timer(0.6 * Engine.time_scale).timeout
	print("[CCLIP] built ability=%s caster=%s targets=%d time_scale=%.3f sequence=%s" % [ability, caster.combatant_name, targets.size(), Engine.time_scale, str(data.get("vfx", ""))])
	## A typed array: assigning a fresh untyped one is a script error that aborts this function (and the clip times out).
	bm.execution_order.clear()
	bm.execution_order.append({"type": "ability", "combatant": caster, "ability_id": ability, "targets": targets, "speed": 99})
	bm.current_state = bm.BattleState.EXECUTION_PHASE
	bm._execute_next_action()
	await create_timer(seconds * Engine.time_scale).timeout
	print("[CCLIP] done")
	quit(0)


func _find(node: Node) -> Node:
	if node.has_method("_on_advance_queue_changed"):
		return node
	for child in node.get_children():
		var hit := _find(child)
		if hit:
			return hit
	return null
