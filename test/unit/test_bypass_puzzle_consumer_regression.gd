extends GutTest

## Skiptrotter's Bypass Puzzle fix (2026-07-09): the ability armed
## meta_auto_solve_puzzle_pending with NO consumer anywhere — 20 MP for a
## flag nothing read (the tick-404 class, on the job whose whole thesis is
## skipping challenges). First consumer: the chicken roundup. With the flag
## armed, the next catch concedes the entire 7-hen puzzle and consumes the
## charge.

const ChickenScript := preload("res://src/exploration/QuestChicken.gd")


func _clear_chicken_flags() -> void:
	for cid in ChickenScript.ALL_CHICKEN_IDS:
		GameState.story_flags.erase("chicken_caught_" + cid)
	GameState.story_flags.erase(ChickenScript.ALL_CAUGHT_FLAG)
	GameState.game_constants.erase("meta_auto_solve_puzzle_pending")


func before_each() -> void:
	_clear_chicken_flags()


func after_each() -> void:
	_clear_chicken_flags()


func test_armed_bypass_concedes_the_whole_roundup() -> void:
	GameState.game_constants["meta_auto_solve_puzzle_pending"] = true
	var hen = ChickenScript.new()
	hen.chicken_id = str(ChickenScript.ALL_CHICKEN_IDS[0])
	add_child_autofree(hen)
	hen._catch()

	for cid in ChickenScript.ALL_CHICKEN_IDS:
		assert_true(GameState.get_story_flag("chicken_caught_" + cid),
			"bypass must mark %s caught" % cid)
	assert_true(GameState.get_story_flag(ChickenScript.ALL_CAUGHT_FLAG),
		"the all-caught flag fires — the quest step completes")
	assert_false(bool(GameState.game_constants.get("meta_auto_solve_puzzle_pending", false)),
		"the charge is CONSUMED — one cast, one puzzle")


func test_unarmed_catch_stays_a_single_chicken() -> void:
	var hen = ChickenScript.new()
	hen.chicken_id = str(ChickenScript.ALL_CHICKEN_IDS[0])
	add_child_autofree(hen)
	hen._catch()
	var caught := 0
	for cid in ChickenScript.ALL_CHICKEN_IDS:
		if GameState.get_story_flag("chicken_caught_" + cid):
			caught += 1
	assert_eq(caught, 1, "no bypass -> one hen at a time, as designed")
	assert_false(GameState.get_story_flag(ChickenScript.ALL_CAUGHT_FLAG), "roundup incomplete")
