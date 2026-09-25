extends GutTest

## Interiors added after the original locations.json pass declare _get_display_name()
## and have no locations.json entry. The area banner, the save toast, and the save
## slot all share SaveSystem.location_display_name, which title-cased the map key
## ("Harmonia Cartographer", "Maple Garage Sale") and never asked the script.

const GdSource = preload("res://test/unit/helpers/gd_source.gd")
const INTERIOR_DIR := "res://src/maps/interiors"
const SCRATCH_SLOT := 95

var _loop: Node = null
var _map_before := ""
var _toast_parents: Array = []


func before_each() -> void:
	_map_before = str(MapSystem.current_map_id) if MapSystem else ""


func after_each() -> void:
	if MapSystem:
		MapSystem.current_map_id = _map_before
	if SaveSystem and SaveSystem.save_exists(SCRATCH_SLOT):
		SaveSystem.delete_save(SCRATCH_SLOT)
	_free_toasts()


func after_all() -> void:
	if _loop and is_instance_valid(_loop):
		_loop.free()
		_loop = null


func _gameloop() -> Node:
	if _loop == null:
		_loop = load("res://src/GameLoop.gd").new()
	return _loop


func _declares_display_name(path: String) -> bool:
	var code := str(GdSource.split(FileAccess.get_file_as_string(path)).get("code", ""))
	for raw in code.split("\n"):
		if raw.strip_edges().begins_with("func _get_display_name("):
			return true
	return false


func _json_map_ids() -> Dictionary:
	var file := FileAccess.open("res://data/locations.json", FileAccess.READ)
	assert_not_null(file, "locations.json must be readable")
	var json := JSON.new()
	assert_eq(json.parse(file.get_as_text()), OK, "locations.json must parse")
	file.close()
	var data: Variant = json.data
	assert_true(data is Dictionary, "locations.json root must be a dict")
	var ids := {}
	for key in data:
		var entry: Variant = (data as Dictionary)[key]
		if entry is Dictionary:
			ids[str((entry as Dictionary).get("map_id", key))] = true
	return ids


func _authored_rooms() -> Array:
	var dir := DirAccess.open(INTERIOR_DIR)
	assert_not_null(dir, "interior scripts must be listable")
	var rooms: Array = []
	var seen := {}
	for file_name in dir.get_files():
		if not str(file_name).ends_with(".gd"):
			continue
		var path := "%s/%s" % [INTERIOR_DIR, file_name]
		if not _declares_display_name(path):
			continue
		var script: Variant = load(path)
		assert_true(script is Script, "%s must load" % path)
		var node: Node = (script as Script).new()
		assert_not_null(node, "%s must instantiate without entering the tree" % path)
		var area := str(node.call("_get_area_id")).strip_edges()
		var label := str(node.call("_get_display_name")).strip_edges()
		node.free()
		assert_ne(area, "", "%s must declare a map id" % path)
		assert_ne(label, "", "%s must declare a display name" % path)
		assert_false(seen.has(area), "two interior scripts claim map id %s" % area)
		seen[area] = label
		rooms.append({"path": path, "area": area, "name": label})
	return rooms


func _toast_text(place: String) -> String:
	var parent := Node.new()
	parent.name = "ToastProbe"
	add_child(parent)
	_toast_parents.append(parent)
	Toast.show_save(parent, place)
	var text := ""
	for child in parent.get_children():
		text = _first_label(child, text)
	_toast_parents.erase(parent)
	parent.free()
	Toast._active_layers = (Toast._active_layers as Array).filter(func(layer): return is_instance_valid(layer))
	return text


func _first_label(node: Node, found: String) -> String:
	if found != "":
		return found
	if node is Label and str((node as Label).text) != "":
		return str((node as Label).text)
	for child in node.get_children():
		found = _first_label(child, found)
		if found != "":
			return found
	return ""


func _free_toasts() -> void:
	for node in _toast_parents:
		if is_instance_valid(node):
			node.free()
	_toast_parents.clear()
	Toast._active_layers = (Toast._active_layers as Array).filter(func(layer): return is_instance_valid(layer))


func _fn_body(path: String, signature: String) -> String:
	var code := str(GdSource.code_of(path))
	var at := code.find(signature)
	assert_gt(at, -1, "PRECONDITION: %s must exist in %s" % [signature, path])
	if at < 0:
		return ""
	var nxt := code.find("\nfunc ", at + signature.length())
	var nxt_static := code.find("\nstatic func ", at + signature.length())
	if nxt < 0 or (nxt_static > at and (nxt < 0 or nxt_static < nxt)):
		nxt = nxt_static
	return code.substr(at, (nxt - at) if nxt > at else 1200)


## Every interior that declares a display name. The banner, the toast, and the slot must use it.
func test_banner_toast_and_slot_use_each_interior_scripts_name() -> void:
	var rooms := _authored_rooms()
	assert_gt(rooms.size(), 20, "CONTROL: the walk must reach the later interiors, not only the original dozen")
	var listed := _json_map_ids()
	var gl := _gameloop()
	var changed: Array[String] = []
	var saw_garage := false
	var saw_attic := false
	for room in rooms:
		var area := str(room["area"])
		var authored := str(room["name"])
		var titled := area.replace("_", " ").capitalize()
		var banner := str(gl._get_location_display_name(area))
		assert_eq(banner, authored,
			"the area banner for %s title-cases the key as '%s' instead of the script's '%s'" % [area, titled, authored])
		if area == "interior":
			assert_ne(str(gl._get_transition_type(area)), "interior",
				"the base scaffold's id is not a room the player enters")
		else:
			assert_eq(str(gl._get_transition_type(area)), "interior",
				"%s must take the interior banner, which prints this name with no extra words" % area)
		MapSystem.current_map_id = area
		assert_eq(SaveSystem._current_location_display_name(), authored,
			"a save made in %s must bake the script's name" % area)
		var payload := {
			"metadata": {"location_name": titled, "save_time": 1},
			"map": {"current_map_id": area},
			"game_state": {"player_party": []},
		}
		assert_true(SaveSystem._write_save_file(SCRATCH_SLOT, payload), "scratch save for %s must write" % area)
		var info: Dictionary = SaveSystem.get_save_info(SCRATCH_SLOT)
		assert_eq(str(info.get("location_name", "")), authored,
			"an old save that baked '%s' must show '%s' on the slot" % [titled, authored])
		assert_eq(_toast_text(banner), "Game Saved ✓ — " + authored,
			"the save toast in %s must name the room the script declares" % area)
		if area == "maple_garage_sale":
			saw_garage = true
			assert_eq(authored, "The Perpetual Garage Sale",
				"CONTROL: MapleGarageSaleInterior must still declare this name")
			assert_ne(authored, titled, "CONTROL: title-casing the garage-sale key is the bug")
		if area == "harmonia_cartographer":
			saw_attic = true
			assert_eq(authored, "Cartographer's Attic",
				"CONTROL: HarmoniaCartographerInterior must still declare this name")
			assert_ne(authored, titled, "CONTROL: title-casing the attic key is the bug")
		if authored != titled and not listed.has(area):
			changed.append("%s: '%s' → '%s'" % [area, titled, authored])
	assert_true(saw_garage, "the walk must include the perpetual garage sale")
	assert_true(saw_attic, "the walk must include the cartographer's attic")
	assert_gt(changed.size(), 10,
		"CONTROL: a title-cased key is still the wrong words for the later rooms: %s" % " | ".join(changed))
	print("Shown names that change: %s" % " | ".join(changed))
	# The loop is not in the tree. Leaving it until after_all counts as an orphan.
	_loop.free()
	_loop = null


func test_the_three_surfaces_read_that_lookup() -> void:
	var lookup := _fn_body("res://src/save/SaveSystem.gd", "static func location_display_name(")
	var json_at := lookup.find("_locations_json_name(")
	var script_at := lookup.find("_interior_script_display_name(")
	assert_gt(json_at, -1, "PRECONDITION: a locations.json miss is what opens the script fallback")
	assert_gt(script_at, json_at,
		"the interior script name is the fallback after locations.json, before the title-cased key")
	assert_true(lookup.contains("if from_json != null:"),
		"a locations.json entry must win even when an interior script also names the map")
	var json_fn := _fn_body("res://src/save/SaveSystem.gd", "static func _locations_json_name(")
	assert_true(json_fn.contains("locations.json"),
		"PRECONDITION: the first lookup still reads locations.json")
	var banner_fn := _fn_body("res://src/GameLoop.gd", "func _get_location_display_name(")
	assert_true(banner_fn.contains("SaveSystem.location_display_name("),
		"the area banner must use the shared place-name lookup")
	var transition := _fn_body("res://src/GameLoop.gd", "func _on_area_transition(")
	assert_true(transition.contains("var display_name = _get_location_display_name(target_map)"),
		"the area transition must name the destination with that lookup")
	assert_true(transition.contains("_area_interior_transition_in(display_name)"),
		"an interior transition must hand that name to the room banner")
	var interior_banner := _fn_body("res://src/GameLoop.gd", "func _area_interior_transition_in(")
	assert_true(interior_banner.contains("lbl.text = location_name"),
		"the interior banner prints the place name on its own, with no title-cased key beside it")
	var toast := _fn_body("res://src/GameLoop.gd", "func _on_any_save_completed(")
	assert_true(toast.contains("_get_location_display_name("),
		"the save toast must use the same lookup as the banner")
	assert_true(toast.contains("Toast.show_save(self, location)"),
		"the save toast must show the resolved place")
	var slot := _fn_body("res://src/save/SaveSystem.gd", "func get_save_info(")
	assert_true(slot.contains("location_display_name(map_id)"),
		"the save slot must re-read the place from the stored map id")
	var screen := GdSource.code_of("res://src/ui/SaveScreen.gd")
	assert_true(screen.contains('save_info.get("location_name"'),
		"the slot panel must print the location_name the slot info computed")
	assert_true(screen.contains("loc_label.text = location"),
		"the slot panel's location line is that string")


func test_locations_json_still_wins_and_unnamed_maps_stay_readable() -> void:
	assert_eq(SaveSystem.location_display_name("vertex_village"), "The Vertex",
		"a listed place keeps its locations.json name")
	assert_eq(SaveSystem.location_display_name("harmonia_chapel"), "Chapel",
		"an interior that is already listed keeps that entry")
	assert_eq(SaveSystem.location_display_name("suburban_overworld"), "Suburbia",
		"overworld places stay on locations.json")
	assert_eq(SaveSystem.location_display_name("tavern_interior"), "Tavern Interior",
		"a room with no authored display name stays a readable key")
	assert_eq(SaveSystem.location_display_name("inn_interior"), "Inn Interior",
		"the inn does not declare a display name, so the key remains the label")
	assert_eq(SaveSystem.location_display_name("shop_interior_item"), "Shop Interior Item",
		"shop interiors do not declare a display name")
	assert_eq(SaveSystem.location_display_name("not_a_real_clearing"), "Not A Real Clearing",
		"a map nobody authored still gets a readable title-cased label")
	var payload := {
		"metadata": {"location_name": "Vertex Village", "save_time": 1},
		"map": {"current_map_id": "vertex_village"},
		"game_state": {"player_party": []},
	}
	assert_true(SaveSystem._write_save_file(SCRATCH_SLOT, payload), "scratch slot must write")
	var info: Dictionary = SaveSystem.get_save_info(SCRATCH_SLOT)
	assert_eq(str(info.get("location_name", "")), "The Vertex",
		"an old save that baked the title-cased key still shows the locations.json name")


func test_overworld_zone_popups_keep_their_own_names() -> void:
	assert_eq(str(ZoneNamePopup.ZONE_NAMES.get("suburban_overworld", "")), "The Mundane Sprawl",
		"the overworld zone popup is a separate naming system")
	assert_ne(SaveSystem.location_display_name("suburban_overworld"), "The Mundane Sprawl",
		"the place-name lookup must not adopt the zone popup's words")
	var code := GdSource.code_of("res://src/exploration/ZoneNamePopup.gd")
	assert_false(code.contains("location_display_name"),
		"the zone popup must not start reading the interior/location lookup")
