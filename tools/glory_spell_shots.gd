extends SceneTree

## A party's tier-3 glory spell in a REAL battle (batch 2): the real party against three goblins, the mage's level and
## Magic set so the cast lands at a chosen intensity tier, then the spell through the real dispatch.
##   tools/glory_spell_shots.sh [spell ...]   (default: firaga blizzaga thundaga, each at low, mid and high)
## Args: --spell=<ability id> --tier=low|mid|high --speed=<engine time_scale, default 0.375>.

const TIERS := {"low": [1, 12.0], "mid": [24, 120.0], "high": [58, 941.0]}


func _init() -> void:
	var spell := "firaga"
	var tier := "high"
	var speed := 0.375
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spell="):
			spell = a.get_slice("=", 1)
		elif a.begins_with("--tier="):
			tier = a.get_slice("=", 1)
		elif a.begins_with("--speed="):
			speed = float(a.get_slice("=", 1))
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("[GLORYSHOT] FAIL: no GameState")
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
	await gl._start_battle_async(["goblin", "goblin", "goblin"], true)
	var scene: Node = _find(root)
	if scene == null:
		print("[GLORYSHOT] FAIL: no BattleScene")
		quit(1)
		return
	var bm = root.get_node("BattleManager")
	var deadline := Time.get_ticks_msec() + 25000
	while bm.enemy_party.size() == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.0, true, false, true).timeout
	var caster = null
	for m in bm.player_party:
		if m.job is Dictionary and str(m.job.get("id", "")) == "mage":
			caster = m
	if caster == null and bm.player_party.size() > 0:
		caster = bm.player_party[0]
	if caster == null or bm.enemy_party.is_empty():
		print("[GLORYSHOT] FAIL: no caster or no foes")
		quit(1)
		return
	var lv: Array = TIERS.get(tier, TIERS["high"])
	caster.job_level = int(lv[0])
	caster.magic = int(lv[1])
	var ability: Dictionary = root.get_node("JobSystem").get_ability(spell)
	var got: Dictionary = scene.cast_intensity(caster, ability)
	scene._set_battle_time_scale(speed)
	bm.current_state = bm.BattleState.PROCESSING_ACTION
	if scene._command_menu:
		scene._command_menu.close_win98_menu()
	await create_timer(0.6, true, false, true).timeout
	var targets: Array = []
	for e in bm.enemy_party:
		if e.is_alive:
			targets.append(e)
	print("[GLORYSHOT] %s casts %s (%s) at %d foe(s), %s: tier %d k %.2f, speed %s" % [caster.combatant_name, spell, str(ability.get("name", "")), targets.size(), tier, int(got["tier"]), float(got["k"]), str(speed)])
	scene._on_action_executing(caster, {"type": "ability", "ability_id": spell, "targets": targets})
	var total: float = 0.55 + float(scene.sequence_total("glory_" + spell)) + 0.6
	await create_timer(total / maxf(Engine.time_scale, 0.01) + 0.8, true, false, true).timeout
	print("[GLORYSHOT] done %s %s" % [spell, tier])
	quit(0)


func _find(n: Node) -> Node:
	if n.get_script() and str(n.get_script().resource_path).ends_with("BattleScene.gd"):
		return n
	for c in n.get_children():
		var f := _find(c)
		if f:
			return f
	return null
