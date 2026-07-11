extends GutTest

## Bram shield scene wiring (struktured content request 2026-07-11; scene
## authored by cowir-story, trigger wired engine-side). First smith talk
## after chapter1 plays world1_bram_shield exactly once.

func test_bram_gate_ordering_and_flags() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var ch1 := src.find("return \"world1_chapter1\"")
	var bram := src.find("return \"world1_bram_shield\"")
	assert_gt(bram, ch1, "bram gate must come AFTER chapter1 so the opening beat wins")
	assert_true("cutscene_flag_chapter1_complete\", false) \\" in src.substr(bram - 400, 400)
		or "flags.get(\"cutscene_flag_chapter1_complete\"" in src.substr(bram - 400, 400),
		"bram gate requires chapter1 completion")
	assert_true("\"world1_bram_shield\":" in src, "completion-flag map entry exists")


func test_bram_first_talk_arms_the_flag() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldNPC.gd")
	var i := src.find("Bram Smith\" and GameState")
	assert_gt(i, -1, "Bram trigger block exists")
	var window := src.substr(i, 500)
	assert_true("talked_to_bram_smith" in window, "flag armed on first talk")
	assert_true("check_pending_cutscene" in window, "pending check fires after dialogue")


func test_scene_and_item_resolve() -> void:
	var f = FileAccess.open("res://data/cutscenes/world1_bram_shield.json", FileAccess.READ)
	assert_not_null(f, "scene file present")
	var data = JSON.parse_string(f.get_as_text())
	assert_true(data is Dictionary and (data.get("steps", []) as Array).size() > 10)
	assert_true(ItemSystem.get_item("untested_shield") != null
		and not ItemSystem.get_item("untested_shield").is_empty(),
		"granted shield resolves in ItemSystem")
