extends GutTest

## tick 70 regression: every interior map_id must have an entry in
## locations.json whose `name` matches the interior script's
## _get_display_name() return value.
##
## Original silent gap (caught in tick 70 audit): None of the 12
## interior map_ids were registered in locations.json. GameLoop's
## _get_location_display_name fell back to map_id.replace("_"," ").capitalize(),
## producing labels like "Vertex threshold" / "Harmonia chapel" / "Node prime
## daemon lounge" instead of the flavorful names each interior script declares.
## Each interior already had a perfectly good _get_display_name() that was
## simply never reached by the location label.

const LOCATIONS_PATH := "res://data/locations.json"


## Expected pairs: [interior_script_path, expected_display_name].
## Both the locations.json `name` and the interior's _get_display_name()
## must return this exact string.
const INTERIOR_NAMES: Array[Array] = [
	["res://src/maps/interiors/HarmoniaChapelInterior.gd",        "Chapel"],
	["res://src/maps/interiors/HarmoniaLibraryInterior.gd",       "Library"],
	["res://src/maps/interiors/EldertreeHollowTreeInterior.gd",   "The Hollow"],
	["res://src/maps/interiors/FrostholdWardenHutInterior.gd",    "Warden's Hut"],
	["res://src/maps/interiors/SandriftGlassmakerInterior.gd",    "Glassmaker's Workshop"],
	["res://src/maps/interiors/GrimhollowWitchHutInterior.gd",    "Witch's Hut"],
	["res://src/maps/interiors/IronhavenWatchtowerInterior.gd",   "Storm Watchtower"],
	["res://src/maps/interiors/MapleHeightsArcadeInterior.gd",    "Glitch City Arcade"],
	["res://src/maps/interiors/BrasstonClockworkLoftInterior.gd", "Clockwork Loft"],
	["res://src/maps/interiors/RivetRowUnionHallInterior.gd",     "Local 8743 Union Hall"],
	["res://src/maps/interiors/NodePrimeDaemonLoungeInterior.gd", "Daemon Lounge"],
	["res://src/maps/interiors/VertexThresholdInterior.gd",       "The Threshold"],
]


## Each pair's map_id is the interior's _get_area_id() — by convention
## also the key under which the entry must appear in locations.json.
const INTERIOR_MAP_IDS: Array[String] = [
	"harmonia_chapel",
	"harmonia_library",
	"eldertree_hollow",
	"frosthold_warden_hut",
	"sandrift_glassmaker",
	"grimhollow_witch_hut",
	"ironhaven_watchtower",
	"maple_heights_arcade",
	"brasston_clockwork_loft",
	"rivet_row_union_hall",
	"node_prime_daemon_lounge",
	"vertex_threshold",
]


func _load_locations() -> Dictionary:
	var f := FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	assert_not_null(f, "locations.json must be readable")
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	var err: int = json.parse(text)
	assert_eq(err, OK, "locations.json must parse as valid JSON")
	var data = json.data
	assert_true(data is Dictionary, "locations.json must be a top-level dict")
	return data


func test_every_interior_map_id_registered_in_locations_json() -> void:
	var data := _load_locations()
	for map_id in INTERIOR_MAP_IDS:
		assert_true(data.has(map_id),
			"locations.json must have key '%s' — without it, GameLoop._get_location_display_name falls back to title-cased map_id ('Node prime daemon lounge') instead of the flavorful name" % map_id)


func test_locations_json_names_match_interior_get_display_name() -> void:
	# Pin the locations.json `name` field literally — must match the
	# value each interior's _get_display_name() returns. If someone
	# renames either side without the other, the label desyncs.
	var data := _load_locations()
	for entry in INTERIOR_NAMES:
		var script_path: String = entry[0]
		var expected_name: String = entry[1]
		var src := FileAccess.get_file_as_string(script_path)
		assert_ne(src, "", "Expected %s to be readable" % script_path)
		assert_true(src.contains("return \"" + expected_name + "\""),
			"%s _get_display_name() must return %s — locations.json names this entry the same way" % [script_path, expected_name])
		# And the locations.json side must agree.
		var map_id: String = script_path.get_file().get_basename().replace("Interior", "").to_snake_case()
		# Map_id deriv-from-class-name is fragile (HarmoniaChapelInterior -> harmonia_chapel, fine, but
		# RivetRowUnionHallInterior -> rivet_row_union_hall, fine). Instead, look up by name field directly.
		var found := false
		for key in data:
			var loc = data[key]
			if loc is Dictionary and loc.get("type") == "interior" and loc.get("name") == expected_name:
				found = true
				break
		assert_true(found,
			"locations.json must have an interior entry with name == %s — matches %s _get_display_name()" % [expected_name, script_path])


func test_interior_entries_have_required_fields() -> void:
	# Every interior must have id/name/type/map_id at minimum. Other
	# fields (has_shop, encounter_rate, etc.) are optional but if
	# we're going to pretend interiors are first-class locations we
	# need the basics.
	var data := _load_locations()
	for map_id in INTERIOR_MAP_IDS:
		var loc = data.get(map_id)
		assert_true(loc is Dictionary, "%s entry must be a dict" % map_id)
		assert_eq(loc.get("type"), "interior",
			"%s must have type 'interior' so callers can filter by it" % map_id)
		assert_eq(loc.get("map_id"), map_id,
			"%s entry must have map_id matching the key — _get_location_display_name iterates and matches on this field" % map_id)
		assert_true(loc.has("name") and loc["name"] is String and loc["name"] != "",
			"%s must have a non-empty name field" % map_id)
		assert_true(loc.has("description") and loc["description"] is String and loc["description"] != "",
			"%s must have a non-empty description" % map_id)
