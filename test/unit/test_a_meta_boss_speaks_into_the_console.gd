extends GutTest
## 2026-11-26 (cowir-story): the autogrind meta-bosses (adaptive_slime, permadeath_reaper) never spoke: their monsters.json rows had no lines,
## and build_meta_boss_enemy_data built an inline dict without `dialogue`. The intro goes to the console FEED, never a panel (main 28102).


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _grind_bosses() -> Dictionary:
	var out := {}
	var monsters := _json("res://data/monsters.json")
	for id in monsters:
		if monsters[id] is Dictionary and bool(monsters[id].get("autogrind_spawned", false)):
			out[id] = monsters[id]
	return out


func test_every_grind_meta_boss_has_an_intro() -> void:
	var bosses := _grind_bosses()
	assert_gt(bosses.size(), 1, "CONTROL: the autogrind roster was read")
	var silent: Array = []
	for id in bosses:
		var dlg: Variant = bosses[id].get("dialogue", {})
		var lines: Array = (dlg as Dictionary).get("intro", []) if dlg is Dictionary else []
		if lines.filter(func(l): return str(l).strip_edges() != "").is_empty():
			silent.append(id)
	assert_eq(silent, [], "autogrind meta-bosses that arrive in silence")


func test_the_built_boss_carries_its_intro_to_the_console() -> void:
	var bosses := _grind_bosses()
	var seen := {}
	for _i in 200:
		for collapse in [false, true]:
			var data: Dictionary = AutogrindSystem.build_meta_boss_enemy_data(collapse)
			seen[str(data.get("id", ""))] = data
	for id in bosses:
		assert_true(seen.has(id), "CONTROL: %s was built by the real builder" % id)
		if not seen.has(id):
			continue
		var dlg: Variant = bosses[id].get("dialogue", {})
		var want: Array = (dlg as Dictionary).get("intro", []) if dlg is Dictionary else []
		var lines: Array = load("res://src/GameLoop.gd").meta_boss_intro_lines([seen[id]])
		assert_gt(lines.size(), 0, "%s: its intro reaches the console feed" % id)
		assert_eq(lines.size(), want.size(), "%s: every intro line reaches the console feed" % id)
		for i in mini(lines.size(), want.size()):
			assert_true(str(lines[i]).contains(str(want[i])), "%s line %d is its own words" % [id, i])


func test_an_ordinary_grind_enemy_logs_nothing() -> void:
	## CONTROL for the filter: a pool enemy that carries lines is not a meta-boss and stays out of the feed.
	var pool := {"id": "slime", "name": "Slime", "dialogue": {"intro": ["hi"]}}
	assert_eq(load("res://src/GameLoop.gd").meta_boss_intro_lines([pool]), [], "only a meta or collapse boss speaks into the feed")
