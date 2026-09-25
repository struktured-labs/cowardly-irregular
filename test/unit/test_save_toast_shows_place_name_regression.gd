extends GutTest

## The area banner and the save slot read locations.json. The save toast
## title-cased the map key, so a crystal in the Chapel said "Harmonia Chapel"
## and a save in The Vertex said "Vertex Village".

const GdSource = preload("res://test/unit/helpers/gd_source.gd")
const LOCATIONS := "res://data/locations.json"
const GAMELOOP := "res://src/GameLoop.gd"


func _locations() -> Dictionary:
	var f := FileAccess.open(LOCATIONS, FileAccess.READ)
	assert_not_null(f, "locations.json must be readable")
	var json := JSON.new()
	assert_eq(json.parse(f.get_as_text()), OK, "locations.json must parse")
	f.close()
	var data: Variant = json.data
	assert_true(data is Dictionary, "locations.json root must be a dict")
	return data


func _handler_code() -> String:
	var code: String = str(GdSource.split(FileAccess.get_file_as_string(GAMELOOP)).get("code", ""))
	var at: int = code.find("func _on_any_save_completed(")
	assert_gt(at, -1, "PRECONDITION: _on_any_save_completed must exist in the code half")
	if at < 0:
		return ""
	var nxt: int = code.find("\nfunc ", at + 1)
	return code.substr(at, (nxt - at) if nxt > at else 800)


## Every authored place. A walk that resolved nothing would pass the toast arm below.
func test_every_authored_place_name_survives_the_resolver() -> void:
	var data := _locations()
	var checked := 0
	var key_would_lie: Array[String] = []
	for key in data:
		var entry: Variant = data[key]
		if not (entry is Dictionary):
			continue
		var map_id: String = str((entry as Dictionary).get("map_id", key))
		var authored: String = str((entry as Dictionary).get("name", ""))
		assert_ne(authored, "", "%s must name the place" % key)
		var resolved: String = SaveSystem.location_display_name(map_id)
		assert_eq(resolved, authored,
			"location_display_name(%s) must be the authored place, not a fallback" % map_id)
		checked += 1
		var as_key: String = map_id.capitalize()
		if as_key != authored:
			key_would_lie.append("%s → toast would say '%s', the place is '%s'" % [map_id, as_key, authored])
	assert_gt(checked, 20, "CONTROL: the walk must cover the location corpus, got %d" % checked)
	assert_gt(key_would_lie.size(), 12,
		"CONTROL: title-casing the map key must still be the wrong words for a real set of places")
	# Named members, so a walk that only counted cannot hide a miss.
	assert_true(key_would_lie.has("vertex_village → toast would say 'Vertex Village', the place is 'The Vertex'"),
		"The Vertex is the discriminator: %s" % " | ".join(key_would_lie))
	assert_true(key_would_lie.has("harmonia_chapel → toast would say 'Harmonia Chapel', the place is 'Chapel'"),
		"the Chapel is the discriminator: %s" % " | ".join(key_would_lie))
	assert_true(key_would_lie.has("maple_heights_arcade → toast would say 'Maple Heights Arcade', the place is 'Glitch City Arcade'"),
		"Glitch City Arcade is the discriminator: %s" % " | ".join(key_would_lie))


## The toast is the surface. The resolver already knew the names; this handler did not ask it.
func test_the_save_toast_asks_for_the_place_name() -> void:
	var body := _handler_code()
	assert_true(body.contains("Toast.show_save(self, location)"),
		"CONTROL: the extracted handler must still be the toast, got: %s" % body)
	assert_true(body.contains("current_map_id"),
		"CONTROL: the handler must still read the live map")
	assert_false(body.contains(".capitalize()"),
		"the save toast still title-cases the map key. Saving in The Vertex says 'Vertex Village', the Chapel says 'Harmonia Chapel', the arcade says 'Maple Heights Arcade'.")
	assert_true(body.contains("_get_location_display_name("),
		"the toast must use the same place-name lookup as the area banner and the save slot")
