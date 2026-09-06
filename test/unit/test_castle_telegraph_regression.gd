extends GutTest

## struktured 2026-09-06: "I dont see castle harmonia but I beat the rat king so thats also
## confusing (on map I dont see it). did u move it?" — Nothing moved. His own 2026-08-22
## spine ruling gates the castle behind all five W1 bosses; what was broken was every surface
## still telling the OLD story: quest log promised a revealed castle, the tracker/objective
## marker pointed SOUTH at a portal that doesn't exist until Mordaine falls, and the minimap
## could not render a castle at all (castle_entrance drew as an unlabeled green village dot).

const MM_SRC := "res://src/exploration/OverworldMinimap.gd"
const OW_SRC := "res://src/exploration/OverworldScene.gd"


func _minimap():
	return load(MM_SRC)


func test_minimap_knows_what_a_castle_is() -> void:
	var mm = _minimap()
	assert_true(mm.DOT_COLORS.has("castle"), "the goal of W1 deserves its own marker color")
	assert_eq(str(mm.SHORT_NAMES.get("castle_entrance", "")), "Castle",
		"castle_entrance must be labeled — unlabeled dots read as noise")


func test_castle_dot_type_beats_the_generic_entrance_arm() -> void:
	var mm = _minimap()
	var inst = mm.new()
	assert_eq(inst._get_dot_type("castle_entrance"), "castle",
		"pre-fix the generic 'entrance' arm claimed it first and painted it village-green")
	assert_eq(inst._get_dot_type("village_entrance"), "village", "CONTROL: villages unchanged")
	assert_eq(inst._get_dot_type("fire_dragon_cave"), "dragon", "CONTROL: dragons unchanged")
	inst.free()


func test_legend_includes_the_castle() -> void:
	var src := FileAccess.get_file_as_string(MM_SRC)
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true(src.contains('["Castle", DOT_COLORS["castle"]]'),
		"a marker the legend cannot explain is a mystery dot")
	assert_true(src.contains('"castle_harmonia_entrance"'),
		"the alias key must be skipped or the castle draws two stacked dots")


func test_objective_marker_routes_through_the_spine_not_the_portal() -> void:
	var src := FileAccess.get_file_as_string(OW_SRC)
	var i: int = src.find("func _get_objective_position(")
	assert_gt(i, -1, "CONTROL: the objective fn must exist")
	var e: int = src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, e - i)
	var portal_at: int = body.find("steampunk_portal")
	var mordaine_at: int = body.find("cutscene_flag_world1_mordaine_defeated")
	assert_gt(mordaine_at, -1, "portal marker must be Mordaine-gated")
	assert_gt(portal_at, mordaine_at, "the portal return must sit UNDER the Mordaine check — pre-fix rat_king alone sent the player south to a portal that does not exist yet")
	assert_true(body.contains("w1_spine_remaining"), "post-Rat-King the marker must follow the spine")
	assert_true(body.contains("castle_entrance"), "and end at the castle once every seal breaks")


func test_tracker_and_quest_log_tell_the_spine_story() -> void:
	var tracker := FileAccess.get_file_as_string("res://src/exploration/QuestTracker.gd")
	assert_false(tracker.contains('"flag": "rat_king_defeated", "text": "Find the portal'),
		"the tracker must not send a post-Rat-King player hunting a portal that is Mordaine-gated")
	assert_true(tracker.contains("dragon seals"), "it must name the actual next goal")
	var qlog := FileAccess.get_file_as_string("res://src/ui/QuestLog.gd")
	assert_false(qlog.contains("A castle reveals itself on the horizon"),
		"the log must not promise an open castle the spine gate keeps shut")
