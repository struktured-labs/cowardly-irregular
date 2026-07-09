extends GutTest

## Feature 2026-07-05: the victory results announced stat gains (v3.33.0) but not
## NEW ABILITIES unlocked by a level-up. end_battle now collects each combatant's
## ability_learned emissions during the EXP award (learn_abilities_for_level
## fires one per newly-unlocked spell) into char_result.learned_abilities, and
## BattleResultsDisplay renders "✦ Learned: Fire" under the stat gains.


func test_battle_manager_collects_learned_abilities() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("\"learned_abilities\": learned_abilities"),
		"char_result must carry the learned-abilities list")
	assert_true(src.contains("ability_learned.connect(_collect_learned)"),
		"end_battle must capture ability_learned emissions during the exp award")
	assert_true(src.contains("ability_learned.disconnect(_collect_learned)"),
		"the collector must disconnect after the award — no leaked signal connection across battles")


func test_results_display_renders_and_sizes_learned_line() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	assert_true(src.contains("cr.get(\"learned_abilities\", [])"),
		"the results row must read learned_abilities")
	assert_true(src.contains("Learned:"),
		"learned abilities must render as a 'Learned:' line")
	assert_gt(src.find("char_height_total += 18  # learned-abilities line"), -1,
		"panel height must account for the learned-abilities line so it doesn't clip")


func test_ability_learned_signal_collection_pattern() -> void:
	# The capture mechanism: a lambda connected to ability_learned appends each id.
	var c := Combatant.new()
	autofree(c)
	assert_true(c.has_signal("ability_learned"), "Combatant must expose the ability_learned signal")
	var collected: Array[String] = []
	var collector := func(aid: String): collected.append(aid)
	c.ability_learned.connect(collector)
	c.ability_learned.emit("fire")
	c.ability_learned.emit("blizzard")
	assert_eq(collected, ["fire", "blizzard"] as Array[String],
		"the collector captures each emitted ability id, in order")
