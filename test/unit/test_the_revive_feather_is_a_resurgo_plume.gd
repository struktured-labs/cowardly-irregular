extends GutTest

## struktured 2026-10-04: "phoenix down is not an acceptable item name. we need alternatives" -> "Resurgo Plume is good for now"
## (Latin like the spells: resurgo, "I rise again"). Display name only: the id stays phoenix_down so saves and inventories keep working.


func test_the_item_keeps_its_id_and_shows_the_new_name() -> void:
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	assert_true(items.has("phoenix_down"), "the id stays phoenix_down: saves and inventories key on it")
	assert_eq(str(items["phoenix_down"].get("name", "")), "Resurgo Plume", "players see Resurgo Plume")
	assert_eq(str(ItemSystem.get_item("phoenix_down").get("name", "")), "Resurgo Plume", "the loaded item reads the new name")


func test_no_player_visible_string_says_phoenix_down() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for root in ["res://data", "res://src"]:
		for path in _files(root):
			scanned += 1
			var text := FileAccess.get_file_as_string(path)
			var ln := 0
			for line in text.split("\n"):
				ln += 1
				var code := line.strip_edges()
				if code.begins_with("#"):
					continue
				if code.find("#") > -1 and path.ends_with(".gd"):
					code = code.substr(0, code.find("#"))
				if code.to_lower().contains("phoenix down"):
					offenders.append("%s:%d" % [path.get_file(), ln])
	assert_gt(scanned, 100, "SCOPE: the walk reached data and src")
	assert_eq(offenders, [] as Array[String], "players must not read 'Phoenix Down' anywhere: %s" % [offenders])


func _files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := root + "/" + n
		if d.current_is_dir():
			out.append_array(_files(p))
		elif n.ends_with(".gd") or n.ends_with(".json"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out
