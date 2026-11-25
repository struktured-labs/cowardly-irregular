extends GutTest
## 2026-11-25 (cowir-story): meta_knight is boss-flagged and Castle Harmonia F3 rolls it (meta_knight@L23), so it fought as a boss, silent.
## Every boss/miniboss row a pool or a floor table can roll must speak at
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


## Live spawn sources: data/enemy_pools.json, and the dungeon floor tables' "<id>@L<n>" / "@elite" strings. NOT GameLoop's
## common_enemies arrays, which are _prewarm_area_sprites lists (battle/overworld 27608-27609).
func _collect(x: Variant, out: Dictionary) -> void:
	if x is String:
		out[(x as String).split("@")[0]] = true
	elif x is Array:
		for y in x:
			_collect(y, out)
	elif x is Dictionary:
		for k in x:
			if not str(k).begins_with("_"):
				_collect(x[k], out)


func _pool_ids() -> Dictionary:
	var out := {}
	_collect(JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json")), out)
	var floor_id := RegEx.new()
	floor_id.compile('"([a-z0-9_]+)@(?:L[0-9]+|elite)"')
	for f in DirAccess.get_files_at("res://src/maps/dungeons/"):
		if f.ends_with(".gd"):
			for m in floor_id.search_all(FileAccess.get_file_as_string("res://src/maps/dungeons/" + f)):
				out[m.get_string(1)] = true
	return out


func test_every_boss_a_pool_or_floor_rolls_speaks() -> void:
	var pool := _pool_ids()
	assert_gt(pool.size(), 60, "CONTROL: the pools and floor tables were read")
	assert_true(pool.has("meta_knight"), "CONTROL: Castle Harmonia F3's meta_knight@L23 is seen")
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
	assert_gt(judged, 30, "CONTROL: the rollable bosses were judged (minibosses, Masterites, meta_knight)")
	assert_eq(silent, [], "pool bosses with nothing to say at one of their beats")
