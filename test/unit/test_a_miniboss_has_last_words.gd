extends GutTest
## 2026-11-24 (cowir-story): nine minibosses (cave_troll, shadow_knight, the six miniboss_* encounter pools, treasure_mimic) were
## spawned as is_boss with their monsters.json dialogue, yet carried no low_hp or defeat line, and six had no intro: the fight's
## three speaking beats said nothing. Every miniboss row must carry all three.

const TRIGGERS := ["intro", "low_hp", "defeat"]


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


func test_every_miniboss_speaks_at_all_three_beats() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var monsters: Dictionary = parsed if parsed is Dictionary else {}
	var judged := 0
	var silent: Array = []
	for id in monsters:
		var row: Variant = monsters[id]
		if not (row is Dictionary) or not bool((row as Dictionary).get("miniboss", false)):
			continue
		judged += 1
		for t in TRIGGERS:
			if not _has_lines((row as Dictionary).get("dialogue", {}), t):
				silent.append("%s: no %s" % [id, t])
	assert_gt(judged, 8, "CONTROL: the miniboss rows were found")
	assert_eq(silent, [], "minibosses with nothing to say at one of their beats")
