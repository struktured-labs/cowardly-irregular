extends GutTest

## Every boss trigger logged "[BOSS] Starting Cave Rat King battle!" — before Pyrroth, before Mordaine, before all of
## them. Play logs are a bug source, and that line sent readers to the wrong cave. The cave that builds the trigger
## now tells it which boss it starts.

const BossTriggerScript := preload("res://src/maps/dungeons/BossTrigger.gd")
const TRIGGER_PATH := "res://src/maps/dungeons/BossTrigger.gd"
const BUILDERS := ["res://src/maps/dungeons/DragonCave.gd", "res://src/maps/dungeons/WhisperingCave.gd"]


func test_the_label_is_whatever_the_cave_said() -> void:
	var t = BossTriggerScript.new()
	t.boss_for_log = "fire_dragon"
	assert_eq(t.boss_label(), "fire_dragon", "the label is the cave's own boss")
	t.boss_for_log = "chancellor_mordaine"
	assert_eq(t.boss_label(), "chancellor_mordaine", "and it follows what it was told, not a constant")
	t.free()


func test_an_untold_trigger_does_not_claim_a_boss() -> void:
	var t = BossTriggerScript.new()
	assert_eq(t.boss_label(), "unnamed boss", "nobody told it, so it names nobody — never the Rat King by default")
	t.free()


func test_the_log_line_is_built_from_the_label() -> void:
	var src := FileAccess.get_file_as_string(TRIGGER_PATH)
	assert_true(src.contains("\"[BOSS] Starting %s battle!\" % boss_label()"), "the start line is derived")
	assert_false(src.contains("Starting Cave Rat King battle"), "and the fixed name is gone")


func test_every_cave_that_builds_a_trigger_names_its_boss() -> void:
	for path in BUILDERS:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.count("BossTriggerScript.new()"), 0, "CONTROL: %s builds a boss trigger" % path.get_file())
		assert_eq(src.count("boss_area.boss_for_log = "), src.count("BossTriggerScript.new()"),
			"%s tells every trigger it builds which boss it starts" % path.get_file())
