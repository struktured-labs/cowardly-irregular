extends SceneTree

## Demo segment: leave Harmonia's gate along the road, step into the grass, walk until a natural encounter starts.

const Lib := preload("res://tools/demo_walk_lib.gd")
const BUDGET_S := 120.0

var w


func _fired() -> bool:
	return w.in_battle() or bool(w.gl.get("_battle_transition_starting"))


func _init() -> void:
	w = Lib.new(self)
	if not await w.boot("overworld", "village_entrance"):
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
		root.add_child(load(PLAYER_PATH).new())
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
	print("[DEMO] segment done")
	quit(0)
