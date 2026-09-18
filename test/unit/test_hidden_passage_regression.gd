extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

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
	# 2026-09-10 (cowir-overworld): ice_hollow was authored off the map and magma_vault's wall sealed
	# nothing; the Sunken Ring is the authored W1 secret now, the magma chest stays as an open find.
	assert_true(src.contains("w1_sunken_ring"), "W1 Sunken Ring passage placed")
	assert_true(src.contains("w1_secret_sunken_ring"), "Sunken Ring pocket has its chest")
	assert_true(src.contains("w1_secret_magma_vault"), "magma chest survives as an ordinary find")
	assert_true(src.contains("\"H\": return TileGeneratorScript.TileType.PATH"),
		"H map char must parse walkable — the sprite provides the wall look")


func test_dragon_cave_parses_h_markers_into_passages() -> void:
	## ⛔ A BARE SYMBOL MATCHED ITS OWN DEFINITION. Deleting the CALL — so no dungeon places any
	## H-marker passage and every dungeon secret is unreachable — left this GREEN. Measured 2026-09-17.
	var src: String = GdSource.code_of("res://src/maps/dungeons/DragonCave.gd")
	assert_ne(src, "", "CONTROL: DragonCave.gd must read back as code")
	var setup_body: String = _body_of(src, "func _setup_transitions_for_floor")
	assert_ne(setup_body, "", "CONTROL: DragonCave must declare _setup_transitions_for_floor")
	assert_true(setup_body.contains("_place_hidden_passages("),
		"_setup_transitions_for_floor must CALL _place_hidden_passages() — without the call the H markers parse and no passage is ever placed")
	assert_true(src.contains("secret_%d"),
		"H markers register secret_ spawn keys (mirror of treasure_)")
	for cave in ["FireDragonCave", "IceDragonCave"]:
		var cave_src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % cave)
		assert_true(cave_src.contains("H"), "%s must author at least one H alcove" % cave)
		var re := RegEx.new()
		re.compile("\"[M.TBUDX]*H[M.TBUDX]*\"")
		assert_not_null(re.search(cave_src), "%s layout rows must contain an H marker" % cave)


## The body of `header`'s function, or "" when absent — a whole-file `contains` cannot tell a CALL
## from the DEFINITION it is named after.
func _body_of(src: String, header: String) -> String:
	var i: int = src.find(header)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > i else -1)
