extends RefCounted

## The demo's PREPARED STATE, shared by every segment driver (cowir-main 22268/22281). Call apply(root, gl) after
## GameLoop is in the tree and the party exists; call pending_story(gl) where the segment starts (Harmonia, the
## overworld) and ABORT the segment if it is not "" — never record over a story scene.
## Battle speed needs nothing: a fresh profile's default IS the 1.5x rung (BattleScene.DEFAULT_BATTLE_SPEED_INDEX 1).
## The LLM is off twice over: settings.json (the camera writes it before boot) AND both live fields here, because
## GameState.llm_enabled has no setter and NPCs read LLMService's own field (cowir-ai 22270).

const STORY_FLAGS := ["cutscene_flag_chapter1_complete", "cutscene_flag_world1_harmonia_npcs_complete"]


static func apply(root: Node, gl: Node) -> Dictionary:
	var gs = root.get_node_or_null("GameState")
	var out := {"hints": 0, "flags": 0, "trust_off": 0}
	if gs:
		var hints = load("res://src/ui/TutorialHints.gd")
		if hints and ("HINTS" in hints):
			for id in hints.HINTS.keys():
				gs.game_constants["tutorial_" + str(id)] = true
				out.hints += 1
		for f in STORY_FLAGS:
			gs.game_constants[f] = true
			out.flags += 1
		for k in ["llm_enabled", "party_llm_dialogue_enabled", "boss_llm_strategy_enabled", "llm_rebalance_enabled"]:
			if k in gs:
				gs.set(k, false)
		if "debug_all_pcs_unlocked" in gs:
			gs.debug_all_pcs_unlocked = false
		# the on-screen "Debug" log panel showed "[GAME] Started" in the camera smoke's frame: a hall blocker
		if "debug_log_enabled" in gs:
			gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	out["debug_overlay"] = "hidden" if dbg else "absent"
	var llm = root.get_node_or_null("LLMService")
	if llm and "llm_enabled" in llm:
		llm.llm_enabled = false
	if gl and "party" in gl:
		for m in gl.party:
			if m and is_instance_valid(m) and "player_trust" in m:
				m.player_trust = false
				out.trust_off += 1
		# PARTY LEVEL, only when the segment is run with `-- --party-level=N` (the walks: the encounter's starting-level
		# party lost 3 members to goblins + imps and hit the walk's 240 s cap). Same block as demo_boss_segment's
		# --level: job level, the kit unlocked through it, full HP/MP. The boss segment passes no such arg.
		var plv := -1
		for a in OS.get_cmdline_user_args():
			if str(a).begins_with("--party-level="):
				plv = int(str(a).get_slice("=", 1))
		var js = root.get_node_or_null("JobSystem")
		if plv > 0 and js:
			for m in gl.party:
				if not (m and is_instance_valid(m)):
					continue
				m.job_level = plv
				js.learn_abilities_for_level(m, plv)
				m.recalculate_stats()
				m.current_hp = m.max_hp
				m.current_mp = m.max_mp
				m.is_alive = true
			print("[DEMO] prep: party raised to level %d" % plv)
		# SPOTLIGHT LOCKS: a W1 member is autobattle_locked until cutscene_flag_spotlight_unlocked_<job>, and a locked
		# member's turn goes to the AI, so the command menu never opens for the player. walk_to_encounter showed it: one
		# Fighter pick a round and four members on autopilot (cowir-sfx 22347, cowir-autogrind 22348). Unlock every
		# member's job the way a later save would, through GameLoop's own setter, then let it reconcile.
		var setter: bool = gl.has_method("_set_cutscene_flag_and_mirror")
		for m in gl.party:
			if m and is_instance_valid(m) and ("job" in m) and m.job is Dictionary and str(m.job.get("id", "")) != "":
				var f := "cutscene_flag_spotlight_unlocked_" + str(m.job.get("id"))
				if setter:
					gl._set_cutscene_flag_and_mirror(f)
				elif gs:
					gs.game_constants[f] = true
		if gl.has_method("_reconcile_spotlight_locks"):
			gl._reconcile_spotlight_locks()
		# Both autobattle toggles off too, then read the routing gate's OWN four inputs per member (BattleManager:2101-2134,
		# cowir-controller 22351): global · per character · spotlight lock · trust. Any true = that member's turn goes to AI.
		var bm = root.get_node_or_null("BattleManager")
		var abs = root.get_node_or_null("AutobattleSystem")
		if bm and "is_autobattle_enabled" in bm:
			bm.is_autobattle_enabled = false
		var locked: Array = []
		for m in gl.party:
			if not (m and is_instance_valid(m)):
				continue
			var nm := str(m.get("combatant_name") if "combatant_name" in m else m.name)
			var cid = bm._get_character_id(m) if bm and bm.has_method("_get_character_id") else nm
			if abs and abs.has_method("set_autobattle_enabled"):
				abs.set_autobattle_enabled(cid, false)
			var g: bool = bool(bm.is_autobattle_enabled) if bm and "is_autobattle_enabled" in bm else false
			var c: bool = bool(abs.is_autobattle_enabled(cid)) if abs and abs.has_method("is_autobattle_enabled") else false
			var l: bool = bool(m.autobattle_locked) if "autobattle_locked" in m else false
			var t: bool = bool(m.player_trust) if "player_trust" in m else false
			print("[DEMO] route %s: global=%s char=%s locked=%s trust=%s" % [nm, g, c, l, t])
			if g or c or l or t:
				locked.append(nm)
		out["locked"] = locked
	# FORCE DANGER, only with `-- --force-danger=S` (cowir-main 23026/23029, sfx 23027, music 23031): ONE dip, to verify the
	# danger bed hands the boss theme back where it cut (6fabbfc7f) in a real take. At the first Selection Phase after S
	# seconds of boss theme, the Fighter takes ONE real hit (take_damage, sized by the game's own damage_preview) to 20%
	# of max HP, alive; the party's own heal policy recovers him. Absent flag = no node, no hook, nothing touched.
	var fdn := arm_force_danger(root, OS.get_cmdline_user_args())
	out["force_danger"] = fdn.min_theme_s if fdn else "off"
	out["llm_service"] = llm.llm_enabled if llm and "llm_enabled" in llm else "absent"
	print("[DEMO] prep: %d hint(s) seen · %d story flag(s) · trust off on %d member(s) · LLMService.llm_enabled=%s · debug overlay %s · routed to AI: %s" % [out.hints, out.flags, out.trust_off, str(out.llm_service), out.debug_overlay, str(out.get("locked", "n/a"))])
	return out


static func pending_story(gl: Node) -> String:
	if gl and gl.has_method("_get_pending_story_cutscene"):
		return str(gl._get_pending_story_cutscene())
	return "<no _get_pending_story_cutscene>"


## Clear every story beat pending on THIS map (call it after arriving: _get_pending_story_cutscene reads the current
## map). Uses GameLoop's own _mark_story_cutscene_complete, so the flag mirror and spotlight locks stay consistent.
## Returns the ids it cleared, or ["ABORT:<why>"] when an id has no completion flag or the chain does not converge.
static func clear_pending_story(gl: Node, max_steps: int = 20) -> Array:
	var cleared: Array = []
	if not (gl and gl.has_method("_get_pending_story_cutscene") and gl.has_method("_mark_story_cutscene_complete")):
		return ["ABORT:GameLoop lacks the story API"]
	var table: Dictionary = gl.get("_CUTSCENE_COMPLETION_FLAGS") if "_CUTSCENE_COMPLETION_FLAGS" in gl else {}
	for _i in range(max_steps):
		var id := str(gl._get_pending_story_cutscene())
		if id == "":
			return cleared
		if not table.has(id):
			return cleared + ["ABORT:%s has no completion flag" % id]
		if cleared.size() > 0 and cleared[-1] == id:
			return cleared + ["ABORT:%s came back after being cleared (its gate reads another flag)" % id]
		# A W1 spotlight's gate tests cutscene_flag_spotlight_unlocked_<job> (set by winning its duel), not the table's
		# ..._watched_<job>, so marking it complete alone loops forever (cowir-cutscenes 22328). A skipped duel = an
		# unlocked PC, which a save at that point would have anyway; _mark_story_cutscene_complete then reconciles locks.
		if id.begins_with("world1_spotlight_") and gl.has_method("_set_cutscene_flag_and_mirror"):
			var job := id.split("_")[2]
			gl._set_cutscene_flag_and_mirror("cutscene_flag_spotlight_unlocked_%s" % job)
		gl._mark_story_cutscene_complete(id)
		print("[DEMO] cleared %s" % id)
		cleared.append(id)
	return cleared + ["ABORT:story chain did not converge in %d steps" % max_steps]


## The hook apply() arms, separate so a test can drive it without apply()'s GameState writes. No flag = null, and
## nothing is added to the tree.
static func arm_force_danger(root: Node, args: Array) -> Node:
	var fd := force_danger_seconds(args)
	if fd <= 0.0:
		return null
	var node := ForceDanger.new()
	node.name = "DemoForceDanger"
	node.min_theme_s = fd
	root.add_child(node)
	print("[DEMO] force-danger: armed, the Fighter to 20%% at the first Selection Phase after %.0f s of boss theme" % fd)
	return node


## -1.0 unless the args carry `--force-danger=S` with S > 0.
static func force_danger_seconds(args: Array) -> float:
	for a in args:
		if str(a).begins_with("--force-danger="):
			var v := float(str(a).get_slice("=", 1))
			return v if v > 0.0 else -1.0
	return -1.0


## The one-shot dip, judged by THE THEME'S OWN CLOCK (cowir-main 23059): the boss bed's playback position, read from
## SoundManager's playing music player while the current track is a boss_ bed. Not summed `delta` (BattleScene scales it
## by Engine.time_scale, 0.375 at the demo rung: cowir-music 23055) and not the wall clock (the camera is Movie Maker,
## where wall time is not video time: cowir-battle 23057). A danger break pauses the position and a resume continues it.
class ForceDanger extends Node:
	const TARGET := 0.20
	var min_theme_s := 30.0
	var done := false
	## where the position comes from: the live bed by default; a test injects a Callable returning seconds
	var position_source: Callable = Callable()

	func _ready() -> void:
		var bm = get_node_or_null("/root/BattleManager")
		if bm and bm.has_signal("selection_phase_started"):
			bm.selection_phase_started.connect(_on_selection)

	## seconds into the boss bed, or -1.0 when no boss_ bed is the current, playing track
	func theme_position() -> float:
		if position_source.is_valid():
			return float(position_source.call())
		var sm = get_node_or_null("/root/SoundManager")
		if not (sm and str(sm.get("_current_music")).begins_with("boss_")):
			return -1.0
		for k in ["_music_player", "_music_player_b"]:
			var p = sm.get(k)
			if p and p is AudioStreamPlayer and p.playing and not p.stream_paused:
				return p.get_playback_position()
		return -1.0

	func _on_selection() -> void:
		if done:
			return
		var pos := theme_position()
		if pos < min_theme_s:
			print("[DEMO] force-danger: Selection Phase at %.1f s of boss theme (< %.0f), deferring" % [pos, min_theme_s])
			return
		done = true
		var bm = get_node_or_null("/root/BattleManager")
		var f = null
		for m in (bm.player_party if bm and "player_party" in bm else []):
			if m and is_instance_valid(m) and m.is_alive and m.job is Dictionary and str(m.job.get("id", "")) == "fighter":
				f = m
				break
		if f == null:
			print("[DEMO] force-danger: no living Fighter in the party, nothing touched")
			return
		var target := int(floor(f.max_hp * TARGET))
		var need: int = f.current_hp - target
		if need <= 0:
			print("[DEMO] force-danger: %s already at %d / %d, nothing touched" % [f.combatant_name, f.current_hp, f.max_hp])
			return
		# the LARGEST raw hit whose real damage (damage_preview, the same owner take_damage uses) is <= need: never a KO
		var hi := need
		while f.damage_preview(hi, false) <= need and hi < (1 << 24):
			hi *= 2
		var lo := 0
		while lo < hi:
			var mid := (lo + hi + 1) / 2
			if f.damage_preview(mid, false) <= need:
				lo = mid
			else:
				hi = mid - 1
		var before: int = f.current_hp
		f.take_damage(lo, false)
		print("[DEMO] force-danger: %s %d -> %d / %d (%.0f%%) at %.1f s of boss theme" % [f.combatant_name, before, f.current_hp, f.max_hp, 100.0 * f.current_hp / max(1, f.max_hp), pos])
