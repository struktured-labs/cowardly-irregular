extends SceneTree

## Demo segment: leave Harmonia's gate along the road, step into the grass, walk until a natural encounter starts.

const Lib := preload("res://tools/demo_walk_lib.gd")
const BUDGET_S := 120.0
const LEVEL := 10

var w
var _player: Node = null


## Raise the party the way battle's demo_boss_segment --level does: job level, its kit, full HP/MP (idempotent).
func _level_party(level: int) -> void:
	var js = root.get_node("JobSystem")
	for m in w.gl.party:
		m.job_level = level
		js.learn_abilities_for_level(m, level)
		m.recalculate_stats()
		m.current_hp = m.max_hp
		m.current_mp = m.max_mp
		m.is_alive = true
	w.say("party at level %d: %s" % [level, ", ".join(w.gl.party.map(func(m): return "%s %d/%d" % [m.combatant_name, m.max_hp, m.max_mp]))])


## Unlock all five starters the game's own way and check every input of the AI-routing gate per member (battle 8ec249ca9 / controller 22351).
func _hand_routed() -> bool:
	var gl: Node = w.gl
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		gl._set_cutscene_flag_and_mirror("cutscene_flag_spotlight_unlocked_" + job)
	if gl.has_method("_reconcile_spotlight_locks"):
		gl._reconcile_spotlight_locks()
	var ab = root.get_node_or_null("AutobattleSystem")
	var bm = root.get_node("BattleManager")
	bm.is_autobattle_enabled = false
	var to_ai: Array = []
	for m in gl.party:
		var cid: String = str(m.combatant_name).to_lower().replace(" ", "_")
		if ab and ab.is_autobattle_enabled(cid):
			ab.set_autobattle_enabled(cid, false)
		var char_on: bool = ab.is_autobattle_enabled(cid) if ab else false
		print("[DEMO] route %s: global=%s char=%s locked=%s trust=%s" % [m.combatant_name, bm.is_autobattle_enabled, char_on, m.autobattle_locked, m.player_trust])
		if bm.is_autobattle_enabled or char_on or m.autobattle_locked or m.player_trust:
			to_ai.append(str(m.combatant_name))
	if not to_ai.is_empty():
		print("[DEMO] ABORT these members would be played by AI, not by hand: %s" % str(to_ai))
		return false
	return true


func _fired() -> bool:
	return w.in_battle() or bool(w.gl.get("_battle_transition_starting"))


func _init() -> void:
	w = Lib.new(self)
	if not await w.boot("overworld", "village_entrance"):
		quit(1)
		return
	_level_party(LEVEL)
	if not _hand_routed():
		quit(1)
		return
	var gs = root.get_node_or_null("GameState")
	if gs and "encounter_rate_multiplier" in gs:
		gs.encounter_rate_multiplier = 2.0
	await w.beat(1.5)
	var s: Node = w.scene()
	var t0 := Time.get_ticks_msec()
	var walked := 0
	var visited := {}
	while not _fired() and walked < 12:
		var dist: Dictionary = w.reach(18)
		var want := "." if walked == 0 else "g"
		var best := Vector2i(-1, -1)
		var best_score := -INF
		for c in dist:
			var ch: String = s.biome_char_at(c.x, c.y) if s.has_method("biome_char_at") else "g"
			if ch != want or visited.has(c):
				continue
			var dv: int = dist[c]
			if dv < 6:
				continue
			var score: float = -absf(dv - 10.0) + randf()
			if score > best_score:
				best_score = score
				best = c
		if best.x < 0:
			w.say("no '%s' cell in reach; widening to any walkable" % want)
			want = ""
			for c in dist:
				if dist[c] >= 8 and not visited.has(c):
					best = c
					break
		if best.x < 0:
			break
		visited[best] = true
		w.say("leg %d -> %s ('%s')" % [walked + 1, str(best), want])
		await w.walk_route(best, {}, _fired)
		walked += 1
		if not _fired():
			await w.beat(randf_range(0.2, 0.6))
	w.release_all()
	if not _fired():
		print("[DEMO] ABORT no encounter after %d legs" % walked)
		quit(1)
		return
	for i in 300:
		if w.in_battle():
			break
		await w.beat(0.1)
	w.say("encounter after %d leg(s), %.1fs wall" % [walked, (Time.get_ticks_msec() - t0) / 1000.0])
	const PLAYER_PATH := "res://tools/demo_battle_player.gd"
	if ResourceLoader.exists(PLAYER_PATH):
		_player = load(PLAYER_PATH).new()
		root.add_child(_player)
		w.say("DemoBattlePlayer plays the fight")
		var t := 0.0
		while not w.in_battle() and t < 15.0:
			await w.beat(0.5)
			t += 0.5
		while w.in_battle() and t < 240.0:
			await w.beat(0.5)
			t += 0.5
		w.say("battle over after %.0fs of video, back on '%s'" % [t, w.map_id()])
	await w.beat(2.5)
	if _player and _player.has_method("missing_menu_members"):
		var missing: Array = _player.missing_menu_members(w.gl.party)
		w.say("played by hand %s" % str(_player.played.keys() if "played" in _player else []))
		if not missing.is_empty():
			print("[DEMO] ASSERT FAIL: %s never got a command menu (autobattle or a spotlight lock played them)" % str(missing))
			print("[DEMO] segment done")
			quit(1)
			return
	print("[DEMO] segment done")
	quit(0)
