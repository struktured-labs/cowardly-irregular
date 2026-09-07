extends GutTest

## Hidden passages (2026-07-01, cowir-main brief msg 2080).
##
## Pins the "secrets" group contract that content_radar's show_secrets
## lane consumes (mirror of the "treasure" contract): group registration
## in _ready, public _is_discovered, story-flag persistence keyed
## "secret_<passage_id>". Plus the placement surfaces: W1 overworld
## H-markers and DragonCave's H-parser lane.

const HiddenPassageScript := preload("res://src/exploration/HiddenPassage.gd")


func after_each() -> void:
	GameState.set_story_flag("secret_test_passage", false)


func test_registers_in_secrets_group_with_discovered_field() -> void:
	var p = HiddenPassageScript.new()
	p.passage_id = "test_passage"
	add_child_autofree(p)
	await get_tree().process_frame
	assert_true(p.is_in_group("secrets"),
		"HiddenPassage must join the 'secrets' group — content_radar contract")
	assert_true("_is_discovered" in p,
		"radar lane reads _is_discovered, mirror of TreasureChest._is_opened")
	assert_false(p._is_discovered)


func test_discovery_persists_via_story_flag() -> void:
	var p = HiddenPassageScript.new()
	p.passage_id = "test_passage"
	add_child_autofree(p)
	await get_tree().process_frame
	p._discover()
	assert_true(p._is_discovered)
	assert_true(GameState.get_story_flag("secret_test_passage"),
		"discovery must persist as secret_<passage_id> story flag")
	# A fresh instance on the same id starts discovered (revealed ghost).
	var p2 = HiddenPassageScript.new()
	p2.passage_id = "test_passage"
	add_child_autofree(p2)
	await get_tree().process_frame
	assert_true(p2._is_discovered, "already-found passage starts revealed")


func test_w1_overworld_places_passages_with_pocket_chests() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	assert_true(src.contains("w1_ice_hollow"), "W1 NW ice passage placed")
	assert_true(src.contains("w1_magma_vault"), "W1 SE magma passage placed")
	assert_true(src.contains("w1_secret_ice_hollow"), "ice pocket has its chest")
	assert_true(src.contains("w1_secret_magma_vault"), "magma pocket has its chest")
	assert_true(src.contains("\"H\": return TileGeneratorScript.TileType.PATH"),
		"H map char must parse walkable — the sprite provides the wall look")


func test_dragon_cave_parses_h_markers_into_passages() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/DragonCave.gd")
	assert_true(src.contains("_place_hidden_passages"),
		"DragonCave must place passages from H markers")
	assert_true(src.contains("secret_%d"),
		"H markers register secret_ spawn keys (mirror of treasure_)")
	for cave in ["FireDragonCave", "IceDragonCave"]:
		var cave_src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % cave)
		assert_true(cave_src.contains("H"), "%s must author at least one H alcove" % cave)
		var re := RegEx.new()
		re.compile("\"[M.TBUDX]*H[M.TBUDX]*\"")
		assert_not_null(re.search(cave_src), "%s layout rows must contain an H marker" % cave)
