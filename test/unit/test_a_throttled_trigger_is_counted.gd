extends GutTest

## struktured's .760 preview log: 45 of 7,481 lines were "[REBALANCE] throttled …", five at a time when the party levelled
## together. The first throttled trigger in a window is still printed; the rest are counted and reported once, by the next
## consideration. The throttle itself is unchanged (test_rebalance_daemon_scaffold pins it).

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")


func test_a_burst_is_counted() -> void:
	var d = DAEMON.new()
	d.min_consideration_interval_sec = 999.0
	assert_true(d.consider("level_up", {"member": "Fighter"}), "FIXTURE: the first trigger is considered")
	for member in ["Cleric", "Mage", "Rogue", "Bard"]:
		assert_false(d.consider("level_up", {"member": member}), "a trigger inside the window is still refused")
	assert_eq(d.throttled_since_last, 4, "the four refused triggers are counted, not lost")


func test_the_count_starts_over_at_the_next_consideration() -> void:
	var d = DAEMON.new()
	d.min_consideration_interval_sec = 999.0
	d.consider("level_up", {})
	d.consider("level_up", {})
	d.consider("level_up", {})
	assert_eq(d.throttled_since_last, 2, "FIXTURE: two were throttled")
	d._last_consideration_ts = 1
	assert_true(d.consider("area_entered", {}), "once the window has passed, the next trigger is considered")
	assert_eq(d.throttled_since_last, 0, "and the count it reported starts over")
