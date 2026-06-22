extends GutTest

## A player whose save predates the reached_cave_floor_3 / chapter3
## flag-setters can defeat the Rat King but still see the chapter-1
## quest log stuck at 'Descend deeper into the Whispering Cave'
## (yellow / active). Reported in playtest 2026-06.
##
## Fix: WhisperingCave's pending_boss_defeat spec now back-fills the
## prereq flags that the boss fight logically implies. The next victory
## self-heals the save — no manual intervention needed.

const WHISPERING_CAVE := "res://src/maps/dungeons/WhisperingCave.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_rat_king_defeat_spec_backfills_floor_flag() -> void:
	var src := _read(WHISPERING_CAVE)
	var idx := src.find("pending_boss_defeat = {")
	assert_gt(idx, -1, "WhisperingCave must declare pending_boss_defeat")
	var brace_end := src.find("}", idx)
	assert_gt(brace_end, -1, "pending_boss_defeat spec must be a complete dict literal")
	var spec := src.substr(idx, brace_end - idx)
	assert_true(spec.contains("\"reached_cave_floor_3\""),
		"rat king defeat must back-fill reached_cave_floor_3 so saves predating the floor-3 setter self-heal")


func test_rat_king_defeat_spec_backfills_chapter3_complete() -> void:
	var src := _read(WHISPERING_CAVE)
	var idx := src.find("pending_boss_defeat = {")
	var brace_end := src.find("}", idx)
	var spec := src.substr(idx, brace_end - idx)
	assert_true(spec.contains("\"cutscene_flag_chapter3_complete\""),
		"rat king defeat must back-fill cutscene_flag_chapter3_complete so the chapter-3 quest line goes green even if the cave-intro was skipped or pre-dated by save")


func test_rat_king_keeps_original_flags() -> void:
	# Back-fill must be ADDITIVE — don't drop the existing rat king flags.
	var src := _read(WHISPERING_CAVE)
	var idx := src.find("pending_boss_defeat = {")
	var brace_end := src.find("}", idx)
	var spec := src.substr(idx, brace_end - idx)
	assert_true(spec.contains("\"cutscene_flag_rat_king_defeated\""),
		"original rat king cutscene flag must still be in the spec")
	assert_true(spec.contains("\"rat_king_defeated\""),
		"original rat king story flag must still be in the spec")
	assert_true(spec.contains("\"cave_rat_king_defeated\""),
		"original dungeon flag must still be set")
