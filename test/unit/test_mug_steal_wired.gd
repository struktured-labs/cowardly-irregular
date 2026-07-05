extends GutTest

## Bugfix 2026-07-05: mug ("Attack and steal in one action", type=physical,
## success_rate=0.4) only ATTACKED — the physical path never reads success_rate
## and had no steal logic, so mug's steal half was entirely dead (same
## authored-but-unreached class as smoke_bomb's escape / flee's game-over). mug
## now carries a `steals` flag and the physical dispatch arm rolls a gold steal
## per target after the hit (with equipment steal_bonus, capped at 100%).


func test_mug_data_flags_steal() -> void:
	var a = JobSystem.get_ability("mug")
	assert_false(a.is_empty(), "mug must resolve")
	assert_eq(str(a.get("type", "")), "physical", "mug is a physical attack (the path that skipped the steal)")
	assert_true(bool(a.get("steals", false)), "mug must flag steals=true so the physical arm rolls a steal")
	assert_true(a.has("success_rate"), "mug authors the steal success_rate")


func test_physical_dispatch_wires_the_steal() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var arm: int = src.find("\"physical\":")
	assert_gt(arm, -1, "the physical dispatch arm must exist")
	var block: String = src.substr(arm, 900)
	assert_true(block.contains("ability.get(\"steals\""),
		"the physical arm must check the steals flag")
	assert_true(block.contains("add_gold"),
		"a flagged steal must actually award stolen gold")
