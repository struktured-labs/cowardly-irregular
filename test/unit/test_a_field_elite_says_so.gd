extends GutTest
## 2026-11-24 (cowir-story): field elites never spoke. BattleEnemySpawner keeps dialogue only for boss/miniboss rows, and an elite is
## neither, so unassuming_dog's monsters.json intro was dead text. Elite lines live in field_elites.json `elite_lines.<species id>`, keyed on
## the elite spawn, never on monsters.json (brass_golem etc. are also ordinary pool enemies). Every per_world elite needs them, unless
## its monster row already speaks as a boss (optimization_itself), where a second set would speak twice.

const TRIGGERS := ["intro", "low_hp", "defeat"]


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


func _speaks_as_boss(row: Variant) -> bool:
	return row is Dictionary and (bool(row.get("boss", false)) or bool(row.get("miniboss", false))) \
		and _has_lines(row.get("dialogue", {}), "intro")


func test_every_field_elite_has_its_lines() -> void:
	var elites := _json("res://data/field_elites.json")
	var monsters := _json("res://data/monsters.json")
	var per_world: Dictionary = elites.get("per_world", {})
	var lines: Dictionary = elites.get("elite_lines", {})
	assert_gt(per_world.size(), 4, "CONTROL: the per-world roster was read")
	var judged := 0
	var exempt := 0
	var silent: Array = []
	for world in per_world:
		var monster_id := str(per_world[world])
		if _speaks_as_boss(monsters.get(monster_id)):
			exempt += 1
			assert_false(lines.has(monster_id), "%s (%s) already speaks as a boss; elite lines would speak twice" % [world, monster_id])
			continue
		judged += 1
		for t in TRIGGERS:
			if not _has_lines(lines.get(monster_id, {}), t):
				silent.append("%s (%s): no %s" % [world, monster_id, t])
	assert_gt(judged, 3, "CONTROL: most elites are judged, not exempted")
	assert_eq(exempt, 1, "CONTROL: exactly optimization_itself is exempt today")
	assert_eq(silent, [], "field elites with nothing to say")


func test_no_elite_line_lives_on_a_pool_monster_row() -> void:
	## An ordinary pool enemy that is also an elite must not carry the elite's words in monsters.json.
	var elites := _json("res://data/field_elites.json")
	var monsters := _json("res://data/monsters.json")
	var judged := 0
	var leaked: Array = []
	for world in elites.get("per_world", {}):
		var monster_id := str(elites["per_world"][world])
		var row: Variant = monsters.get(monster_id)
		if _speaks_as_boss(row):
			continue
		judged += 1
		if row is Dictionary and (row as Dictionary).get("dialogue") is Dictionary and not ((row as Dictionary)["dialogue"] as Dictionary).is_empty():
			leaked.append(monster_id)
	assert_gt(judged, 3, "CONTROL: the non-boss elites were read")
	assert_eq(leaked, [], "elite words belong in field_elites.json, not on a row ordinary spawns share")
