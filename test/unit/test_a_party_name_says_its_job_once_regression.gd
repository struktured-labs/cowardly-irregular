extends GutTest

## Regression (cowir-story 22355, demo QC): W1 calls the party by class title, so the battle panel read
## "Fighter (Fighter)" for all five. The job is said once when it IS the name; a W2 title still shows.

const UI_PATH := "res://src/battle/BattleUIManager.gd"


func test_a_w1_member_named_for_its_job_says_it_once() -> void:
	assert_eq(BattleUIManager.name_with_job("Fighter", "Fighter"), "Fighter")
	assert_eq(BattleUIManager.name_with_job("Fighter", "Fighter", " Lv.14"), "Fighter (Lv.14)", "the level survives the dedupe")
	assert_eq(BattleUIManager.name_with_job("Cleric", "cleric"), "Cleric", "case does not make two words")


func test_a_world_title_still_shows_beside_the_name() -> void:
	assert_eq(BattleUIManager.name_with_job("Fighter", "Security Guard"), "Fighter (Security Guard)")
	assert_eq(BattleUIManager.name_with_job("Fighter", "Security Guard", " Lv.3"), "Fighter (Security Guard Lv.3)")
	assert_eq(BattleUIManager.name_with_job("Mira", "Fighter"), "Mira (Fighter)", "a renamed member keeps the job")


func test_the_predicate_is_the_one_rule_other_surfaces_ask() -> void:
	assert_true(BattleUIManager.job_is_name("Fighter", " fighter "), "trim and case")
	assert_false(BattleUIManager.job_is_name("Fighter", "Security Guard"))
	assert_false(BattleUIManager.job_is_name("Mira", "Fighter"))


func test_every_party_label_in_the_panel_goes_through_the_helper() -> void:
	var src := FileAccess.get_file_as_string(UI_PATH)
	assert_gt(src.length(), 0, "read %s" % UI_PATH)
	var reaches := 0
	for line in src.split("\n"):
		if "name_label.text" in line and "combatant_name" in line:
			reaches += 1
			assert_true("name_with_job(" in line, "a party label formats the job by hand: %s" % line.strip_edges())
	assert_eq(reaches, 2, "the build and the refresh each set the party label once")
