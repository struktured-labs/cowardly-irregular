extends GutTest

## struktured's logs: "[REBALANCE] throttled (0s since last) — trigger=boss_defeat", 11 times across sessions against 4
## considered. A boss win grants EXP, someone levels, the level_up claims the window, and the boss_defeat landing in it
## was dropped. party_wipe and boss_defeat now throttle only against EACH OTHER; routine triggers still respect every window.

const RD := preload("res://src/llm/RebalanceDaemon.gd")


func _daemon():
	var d = RD.new()
	d.min_consideration_interval_sec = 999.0
	return d


func test_a_boss_win_after_its_level_up_is_considered() -> void:
	var d = _daemon()
	assert_true(d.consider(RD.TRIGGER_LEVEL_UP, {"member": "Mage"}), "FIXTURE: the victory's level_up goes first")
	assert_true(d.consider(RD.TRIGGER_BOSS_DEFEAT, {"boss": "fire_dragon"}),
		"THE DEFECT: the boss win was throttled by its own level_up")


func test_a_wipe_after_a_door_is_considered() -> void:
	var d = _daemon()
	assert_true(d.consider(RD.TRIGGER_AREA_ENTERED, {}), "FIXTURE: a door was walked through")
	assert_true(d.consider(RD.TRIGGER_PARTY_WIPE, {}), "a wipe right after is still considered")


func test_a_wipe_streak_is_still_throttled() -> void:
	var d = _daemon()
	assert_true(d.consider(RD.TRIGGER_PARTY_WIPE, {}), "FIXTURE: the first wipe")
	assert_false(d.consider(RD.TRIGGER_PARTY_WIPE, {}), "a second wipe inside the window is refused (no 10-call streak)")
	assert_false(d.consider(RD.TRIGGER_BOSS_DEFEAT, {}), "and so is a boss win: significant triggers share one window")


func test_routine_triggers_still_wait_on_everything() -> void:
	var d = _daemon()
	assert_true(d.consider(RD.TRIGGER_BOSS_DEFEAT, {}), "FIXTURE: a boss win")
	assert_false(d.consider(RD.TRIGGER_LEVEL_UP, {}), "a level_up right after is throttled, as before")
	assert_false(d.consider(RD.TRIGGER_AREA_ENTERED, {}), "and a door is too")
