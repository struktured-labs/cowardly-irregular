extends GutTest

## Save slots titled the map id ("Suburban Overworld", "Vertex Village") while the
## area banner reads locations.json ("Suburbia", "The Vertex"). The baked
## location_name is that title-case string, so old files keep lying until the
## read path derives the name from the stored map id.

const SCRATCH_SLOT := 97


func after_each() -> void:
	if SaveSystem and SaveSystem.save_exists(SCRATCH_SLOT):
		SaveSystem.delete_save(SCRATCH_SLOT)


func _place_name(map_id: String) -> String:
	var f := FileAccess.open("res://data/locations.json", FileAccess.READ)
	assert_not_null(f, "locations.json must be readable")
	var json := JSON.new()
	assert_eq(json.parse(f.get_as_text()), OK, "locations.json must parse")
	f.close()
	var data: Variant = json.data
	assert_true(data is Dictionary, "locations.json root must be a dict")
	for key in data:
		var entry: Variant = (data as Dictionary)[key]
		if entry is Dictionary and str((entry as Dictionary).get("map_id", key)) == map_id:
			return str((entry as Dictionary).get("name", ""))
	return ""


func test_a_save_names_the_place_the_banner_uses() -> void:
	var cases := {
		"suburban_overworld": "Suburbia",
		"steampunk_overworld": "Cogsworth Junction",
		"industrial_overworld": "The Efficiency District",
		"futuristic_overworld": "The Network",
		"abstract_overworld": "The Remainder",
		"vertex_village": "The Vertex",
		"maple_heights_village": "Maple Heights",
	}
	var prev := ""
	if MapSystem and "current_map_id" in MapSystem:
		prev = str(MapSystem.current_map_id)
	for map_id in cases:
		var expected: String = str(cases[map_id])
		assert_eq(_place_name(map_id), expected, "locations.json names %s" % map_id)
		MapSystem.current_map_id = map_id
		var shown: String = SaveSystem._current_location_display_name()
		assert_eq(shown, expected,
			"saving in %s must label the slot '%s', not the title-cased id '%s'" % [map_id, expected, map_id.capitalize()])
	if MapSystem and "current_map_id" in MapSystem:
		MapSystem.current_map_id = prev


func test_an_unlisted_map_still_falls_back_to_a_readable_id() -> void:
	var prev := str(MapSystem.current_map_id)
	MapSystem.current_map_id = "harmonia_village"
	assert_eq(SaveSystem._current_location_display_name(), "Harmonia Village",
		"a map with no locations.json entry still gets a readable title-cased label")
	MapSystem.current_map_id = prev


func test_a_baked_title_case_location_does_not_outrank_the_stored_map() -> void:
	var payload := {
		"metadata": {"location_name": "Vertex Village", "save_time": 1},
		"map": {"current_map_id": "vertex_village"},
		"game_state": {"player_party": []},
	}
	assert_true(SaveSystem._write_save_file(SCRATCH_SLOT, payload), "scratch slot must write")
	var info: Dictionary = SaveSystem.get_save_info(SCRATCH_SLOT)
	assert_eq(str(info.get("location_name", "")), "The Vertex",
		"an old save that baked 'Vertex Village' must show The Vertex — the map id is what was stored")
