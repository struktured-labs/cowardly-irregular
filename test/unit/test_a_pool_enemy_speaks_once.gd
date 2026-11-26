extends GutTest
## 2026-11-25 (cowir-story; main ruling 27530): four abstract pool enemies carried monsters.json dialogue that no spawn path showed
## (only boss/miniboss/elite fights load it). Ruling: a pool enemy's intro (and low_hp) plays once, in the battle of its first
## sighting. This pins WHICH pool rows speak, so adding a pool intro is a deliberate act, not a drift; battle's file owns the runtime.

const SPEAKING_POOL := ["empty_set", "forgotten_variable", "null_entity", "the_absence"]


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func test_the_pool_rows_that_speak_are_exactly_the_pinned_set() -> void:
	var monsters := _json("res://data/monsters.json")
	var elites: Array = (_json("res://data/field_elites.json").get("per_world", {}) as Dictionary).values()
	var judged := 0
	var speaking: Array = []
	for id in monsters:
		var row: Variant = monsters[id]
		if not (row is Dictionary):
			continue
		var r := row as Dictionary
		if bool(r.get("boss", false)) or bool(r.get("miniboss", false)) or bool(r.get("field_elite", false)) or elites.has(id):
			continue
		if bool(r.get("autogrind_spawned", false)):
			continue  ## a grind meta-boss speaks into the console feed, never on a pool sighting
		judged += 1
		var dlg: Variant = r.get("dialogue")
		if dlg is Dictionary and not (dlg as Dictionary).is_empty():
			speaking.append(str(id))
	speaking.sort()
	assert_gt(judged, 40, "CONTROL: the ordinary pool rows were read")
	assert_eq(speaking, SPEAKING_POOL, "pool enemies that speak on first sighting; add one here deliberately")


## 2026-11-25 (cowir-story): the first-sighting fight carries intro AND low_hp (battle 5525639f2), and three of four had no low_hp.
func test_every_pinned_pool_enemy_has_an_intro_and_a_wounded_line() -> void:
	var monsters := _json("res://data/monsters.json")
	for id in SPEAKING_POOL:
		var dlg: Dictionary = (monsters.get(id, {}) as Dictionary).get("dialogue", {})
		for t in ["intro", "low_hp"]:
			var lines: Variant = dlg.get(t, [])
			assert_true(lines is Array and (lines as Array).size() > 0, "%s speaks its %s in its first-sighting fight" % [id, t])
