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


## 2026-11-26 (cowir-story): a beaten meta-boss's `defeat` lines follow its Victory row in the console feed, read before on_battle_ended clears the data.
func test_a_beaten_meta_boss_has_last_words_in_the_console() -> void:
	var bosses := _grind_bosses()
	var gl: Script = load("res://src/GameLoop.gd")
	for id in bosses:
		var dlg: Variant = bosses[id].get("dialogue", {})
		var want: Array = (dlg as Dictionary).get("defeat", []) if dlg is Dictionary else []
		assert_gt(want.size(), 0, "%s has last words" % id)
		var data: Dictionary = {"id": id, "name": str(bosses[id].get("name", id)), "is_meta_boss": true, "dialogue": dlg}
		var lines: Array = gl.meta_boss_defeat_lines([data])
		assert_eq(lines.size(), want.size(), "%s: every last word reaches the console feed" % id)
		for i in mini(lines.size(), want.size()):
			assert_true(str(lines[i]).contains(str(want[i])), "%s last word %d is its own" % [id, i])
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var read_at := src.find("meta_boss_defeat_lines([_autogrind_controller._current_meta_boss_data])")
	assert_gt(read_at, 0, "CONTROL: the battle-end handler reads the boss's last words")
	assert_lt(read_at, src.find("_autogrind_controller.on_battle_ended(victory", read_at - 1), "read BEFORE on_battle_ended clears the meta-boss data")
	assert_gt(src.find("for line in last_words:", read_at), read_at, "and they are appended to the console feed")



## The headless tier never builds a console scene, so both beats are written around its HEADLESS row instead.
func test_a_headless_meta_boss_fight_speaks_too() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var start := src.find("func _resolve_headless_battle(")
	assert_gt(start, 0, "CONTROL: the headless resolver was found")
	var body := src.substr(start, src.find("\nfunc ", start + 1) - start)
	var call := body.find("_autogrind_controller.on_battle_ended(victory")
	assert_gt(call, 0, "CONTROL: the headless resolver forwards to the controller")
	var intro := body.find("meta_boss_intro_lines(enemy_data)")
	var last := body.find("meta_boss_defeat_lines(enemy_data)")
	assert_true(intro > 0 and intro < call, "the headless intro is read before on_battle_ended")
	assert_true(last > 0 and last < call, "the headless last words are read before on_battle_ended")
	assert_gt(body.find("append_array(boss_intro)"), call, "the intro is written to the feed")
	assert_gt(body.find("append_array(last_words)"), call, "the last words are written to the feed")
