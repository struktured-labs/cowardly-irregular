extends SceneTree

## One demo-reel boss segment for the Indie Hall video (cowir-main 22251), on cowir-deploy's camera contract (22265):
## boots GameLoop, applies the shared demo prep, raises the party to --level, enters the boss floor, walks up to the
## REAL BossTrigger and confirms there (the intro cutscene plays as in the game), then hands every press to
## DemoBattlePlayer. Ends after the victory is confirmed: `[DEMO] segment done`, quit 0. A KO prints `[DEMO] KO`.
##   godot -s tools/demo_boss_segment.gd -- --boss=rat_king|pyrroth|mordaine [--level=N]

const BOSSES := {
	"rat_king": {"map": "whispering_cave", "floor": 6, "read": 2, "level": 14, "flags": []},
	"pyrroth": {"map": "fire_dragon_cave", "floor": 5, "read": 3, "level": 20, "flags": []},
	"mordaine": {"map": "castle_harmonia", "floor": 4, "read": 7, "level": 22,
		"flags": ["cutscene_flag_world1_throne_room_approach_complete"]},
}
const PREP_PATH := "res://tools/demo_prep.gd"


func _beat(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _beat(0.08)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _init() -> void:
	var boss := "rat_king"
	var level := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boss="):
			boss = a.get_slice("=", 1)
		elif a.begins_with("--level="):
			level = int(a.get_slice("=", 1))
	if not BOSSES.has(boss):
		print("[DEMO] ABORT unknown boss '%s'" % boss)
		quit(1)
		return
	var spec: Dictionary = BOSSES[boss]
	if level < 0:
		level = int(spec["level"])
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	var prep = load(PREP_PATH) if ResourceLoader.exists(PREP_PATH) else null
	if prep:
		prep.apply(root, gl)
	for f in spec["flags"]:
		gs.game_constants[f] = true
	# Raise the party the way the game would have: job level, the kit unlocked through it, full HP/MP.
	var js = root.get_node("JobSystem")
	for m in gl.party:
		m.job_level = level
		js.learn_abilities_for_level(m, level)
		m.recalculate_stats()
		m.current_hp = m.max_hp
		m.current_mp = m.max_mp
		m.is_alive = true
	# The spotlight LOCK routes a member's turn to AI until that member's duel counts as won (autogrind 22348): unlock
	# all five starters the game's own way, then check the four inputs of the routing gate per member (controller 22351).
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		gl._set_cutscene_flag_and_mirror("cutscene_flag_spotlight_unlocked_" + job)
	if gl.has_method("_reconcile_spotlight_locks"):
		gl._reconcile_spotlight_locks()
	var ab = root.get_node_or_null("AutobattleSystem")
	var bm = root.get_node("BattleManager")
	bm.is_autobattle_enabled = false
	var routed_to_ai: Array = []
	for m in gl.party:
		var cid: String = str(m.combatant_name).to_lower().replace(" ", "_")
		if ab and ab.is_autobattle_enabled(cid):
			ab.set_autobattle_enabled(cid, false)
		var row := "global=%s char=%s locked=%s trust=%s" % [bm.is_autobattle_enabled, ab.is_autobattle_enabled(cid) if ab else false, m.autobattle_locked, m.player_trust]
		print("[DEMO] route %s: %s" % [m.combatant_name, row])
		if bm.is_autobattle_enabled or (ab and ab.is_autobattle_enabled(cid)) or m.autobattle_locked or m.player_trust:
			routed_to_ai.append(str(m.combatant_name))
	if not routed_to_ai.is_empty():
		print("[DEMO] ABORT these members would be played by AI, not by hand: %s" % str(routed_to_ai))
		quit(1)
		return
	print("[DEMO] party at level %d: %s" % [level, ", ".join(gl.party.map(func(m): return "%s %d/%d" % [m.combatant_name, m.max_hp, m.max_mp]))])
	gl._current_cave_floor = int(spec["floor"])
	gl._set_current_map_id(str(spec["map"]))
	# Settle every story beat the arrival would fire, BEFORE the map loads (the check reads _current_map_id).
	if prep and prep.has_method("clear_pending_story"):
		var cleared: Array = prep.clear_pending_story(gl)
		if cleared.size() > 0 and str(cleared[-1]).begins_with("ABORT:"):
			print("[DEMO] ABORT %s" % str(cleared[-1]))
			quit(1)
			return
	await gl._start_exploration()
	await _beat(1.0)
	var scene = gl.get("current_scene")
	var trigger: Node = scene.find_child("BossTrigger", true, false) if scene else null
	var player: Node2D = scene.get("player") if scene else null
	if trigger == null or player == null:
		print("[DEMO] ABORT no BossTrigger/player on %s floor %d" % [spec["map"], spec["floor"]])
		quit(1)
		return
	var still_pending := str(gl._get_pending_story_cutscene())
	if still_pending != "":
		print("[DEMO] ABORT story beat pending on arrival: %s" % still_pending)
		quit(1)
		return
	# Stand a step south of the trigger, a human beat, then confirm: the interact path a player takes.
	player.global_position = (trigger as Node2D).global_position + Vector2(0, 30)
	await _beat(1.6)
	var player_node: Node = load("res://tools/demo_battle_player.gd").new()
	player_node.intro_read_lines = int(spec["read"])
	player_node.victory_hold = 9.6
	root.add_child(player_node)
	await _press("ui_accept")
	# The press starts the boss through the cave's own trigger; it registers the pending defeat at once. Never start it
	# a second time (a fallback interact() wedged the first Rat King take on a double start).
	var started := false
	for i in 100:
		await _beat(0.1)
		if not (gs.get("pending_boss_defeat") as Dictionary).is_empty() or gl.get("current_state") == gl.LoopState.BATTLE:
			started = true
			break
	if not started:
		print("[DEMO] ABORT the confirm press did not start the boss at %s" % str((trigger as Node2D).global_position))
		quit(1)
		return
	# Watch the fight: a KO is a failed take, the battle's end is the segment's end.
	var kos: Array = []
	var in_battle := false
	var t := 0.0
	while t < 900.0:
		await _beat(0.25)
		t += 0.25
		var state = gl.get("current_state")
		if state == gl.LoopState.BATTLE:
			in_battle = true
			for m in gl.party:
				if not m.is_alive and not (m.combatant_name in kos):
					kos.append(m.combatant_name)
					print("[DEMO] KO %s" % m.combatant_name)
		elif in_battle and state == gl.LoopState.EXPLORATION:
			break
	await _beat(1.5)
	var missing: Array = player_node.missing_menu_members(gl.party)
	print("[DEMO] %s at level %d: KOs %s · played by hand %s · %.0f s" % [boss, level, str(kos), str(player_node.played.keys()), t])
	if not missing.is_empty():
		print("[DEMO] ASSERT FAIL: %s never got a command menu (autobattle or a spotlight lock played them)" % str(missing))
		print("[DEMO] segment done")
		quit(1)
		return
	print("[DEMO] segment done")
	quit(0 if in_battle else 1)
