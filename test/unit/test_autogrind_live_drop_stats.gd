extends GutTest

## Regression coverage for live-autogrind drop-stats parity.
## The headless path (drop-parity fix) merges rolled drops into items_gained; the
## LIVE path routed drops to inventory via BattleManager but forwarded only gold,
## so total_items_gained reported 0 items in live tiers while headless counted
## correctly — same session, different tier, different stats. Source-inspection
## pins the wiring; the stats-accumulation behavior itself is exercised directly
## against AutogrindSystem.


func test_live_path_merges_battle_manager_drops() -> void:
	var src: String = load("res://src/GameLoop.gd").source_code
	var fn_start := src.find("func _on_autogrind_battle_ended")
	assert_true(fn_start >= 0, "_on_autogrind_battle_ended must exist")
	var fn_end := src.find("\nfunc ", fn_start + 20)
	if fn_end < 0:
		fn_end = src.length()
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("get_battle_results"),
		"live autogrind path must read BattleManager.get_battle_results() to pick up rolled drops")
	assert_true(body.contains("item_drops"),
		"live autogrind path must merge item_drops into items_gained — otherwise live tiers report 0 items while headless counts correctly")


func test_on_battle_victory_accumulates_merged_drops() -> void:
	# End-to-end for the stats side: a merged items_gained dict (gold + drops)
	# must land in total_items_gained without the gold key polluting item counts.
	var system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(system)
	system.is_grinding = true
	system.current_region_id = ""
	system.total_items_gained.clear()
	system._grind_stats = {
		"start_time": 0.0, "total_exp": 0, "total_gold": 0,
		"total_jp": 0, "total_encounters": 0, "elapsed_seconds": 0.0
	}
	system.on_battle_victory(100, {"gold": 500, "potion": 2, "rare_gem": 1})
	assert_eq(int(system.total_items_gained.get("potion", 0)), 2,
		"merged drop quantities must accumulate in total_items_gained")
	assert_eq(int(system.total_items_gained.get("rare_gem", 0)), 1)
	assert_false(system.total_items_gained.has("gold"),
		"gold is a reward channel, not an item — the tick-343 filter must keep it out of item counts")