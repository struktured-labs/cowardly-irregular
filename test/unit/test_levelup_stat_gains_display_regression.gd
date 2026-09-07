extends GutTest

## Feature 2026-07-04: the victory results showed "LEVEL UP!" but not
## WHICH stats grew — the classic satisfying RPG payoff was missing.
## BattleManager now snapshots the six core stats before gain_job_exp
## (which recalcs on a level-up) and diffs them into char_results.
## stat_gains; BattleResultsDisplay renders "HP +N  ATK +N" under the
## LEVEL UP! banner. This pins the capture + display wiring and the
## premise (a level-up actually raises stats).


func test_leveling_up_actually_raises_a_stat() -> void:
	# Premise: there ARE gains to display. recalculate_stats scales base
	# stats by job level (+4%/level), so crossing a level raises max_hp.
	var c := Combatant.new()
	add_child_autofree(c)  # recalc's autoload lookups need a tree
	c.combatant_name = "Grower"
	c.base_max_hp = 100
	c.max_hp = 100
	c.job_level = 1
	c.job_exp = 95
	c.recalculate_stats()
	var before := c.max_hp
	c.gain_job_exp(100)  # crosses the level-1 threshold (job_level*100)
	assert_gt(c.job_level, 1, "setup: must actually level up")
	assert_gt(c.max_hp, before, "a level-up must raise max_hp — otherwise there's nothing to show")


func test_battle_manager_captures_stat_gains() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("var pre_stats :="),
		"end_battle must snapshot stats before gain_job_exp")
	assert_true(src.contains("\"stat_gains\": stat_gains"),
		"char_results must carry the computed stat gains")
	# gains only populate on an actual level-up
	var idx: int = src.find("var stat_gains: Dictionary = {}")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 300)
	assert_true(window.contains("if leveled_up:"),
		"stat gains must be computed only when the combatant leveled up")


func test_results_display_renders_and_sizes_the_gain_line() -> void:
	# 2026-08-18 revamp: the surface moved to VictoryOverlay's per-character cards.
	var src: String = FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	assert_true(src.contains("cr.get(\"stat_gains\", {})"),
		"the card gains line must read stat_gains")
	assert_true(src.contains("%s +%d"),
		"gains must render as 'STAT +N'")
	assert_true(src.contains("gains.clip_text = true"),
		"gains ride ONE clipped line per card — the compact-layout rule's successor")
