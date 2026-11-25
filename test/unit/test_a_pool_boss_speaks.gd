extends GutTest
## 2026-11-25 (cowir-story): meta_knight is boss-flagged yet sits in steampunk's common pool (GameLoop common_enemies) and Castle
## Harmonia F3, so it fought as a boss with no line at any beat. Every boss/miniboss row named in a common_enemies pool must speak at
## intro and low_hp, when it loses (monsters.json defeat or boss_dialogue victory_lines) and when it wipes (defeat_lines).

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _has_lines(entry: Variant, key: String) -> bool:
	if not (entry is Dictionary):
		return false
	var lines: Variant = (entry as Dictionary).get(key, [])
	if not (lines is Array):
		return false
	for l in lines:
		if l is String and not (l as String).strip_edges().is_empty():
			return true
	return false


func _pool_ids() -> Dictionary:
	var out := {}
	var line := RegEx.new()
	line.compile('common_enemies\\s*=\\s*\\[([^\\]]*)\\]')
	var id := RegEx.new()
	id.compile('"([a-z0-9_]+)"')
	for m in line.search_all(FileAccess.get_file_as_string("res://src/GameLoop.gd")):
		for i in id.search_all(m.get_string(1)):
			out[i.get_string(1)] = true
	return out


func test_every_boss_in_a_common_pool_speaks() -> void:
	var pool := _pool_ids()
	assert_gt(pool.size(), 15, "CONTROL: the common pools were read")
	var monsters := _json("res://data/monsters.json")
	var dialogue := _json("res://data/boss_dialogue.json")
	var judged := 0
	var silent: Array = []
	for id in pool:
		var row: Variant = monsters.get(id)
		if not (row is Dictionary) or not (bool(row.get("boss", false)) or bool(row.get("miniboss", false))):
			continue
		judged += 1
		var persona := str(row.get("boss_llm_persona_id", "")) if str(row.get("boss_llm_persona_id", "")) != "" else str(id)
		var bd: Variant = dialogue.get(persona, {})
		for t in ["intro", "low_hp"]:
			if not _has_lines(row.get("dialogue", {}), t):
				silent.append("%s: no %s" % [id, t])
		if not (_has_lines(row.get("dialogue", {}), "defeat") or _has_lines(bd, "victory_lines")):
			silent.append("%s: no line when it loses" % id)
		if not _has_lines(bd, "defeat_lines"):
			silent.append("%s: no wipe line" % id)
	assert_gt(judged, 5, "CONTROL: the pool bosses were judged (dragons, Masterites, meta_knight)")
	assert_eq(silent, [], "pool bosses with nothing to say at one of their beats")
