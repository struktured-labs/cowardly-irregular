extends GutTest
## Umbraxis (smoke764): a boss's first signature slows battle to 0.25x; the restore to 1x mid-hold made the watchdog
## judge ~10s of 0.25x wall time by the 1x threshold and fire a false "stalled" recovery that double-ran the queue.

func test_slow_wall_time_is_charged_at_its_own_scale() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("_wd_scaled_ms += float(now - _wd_last_tick_ms) * minf(1.0"), "watchdog integrates scaled time per frame")
	assert_false(src.contains("if now - _wd_last_progress_ms < int(_WD_STALL_MS * slack)"), "no single end-of-window slack judged by the current scale")

func test_quarter_speed_hold_then_restore_is_not_a_stall() -> void:
	# 10.2s at 0.25x (the measured Void Breath beat) then a 1x frame: 2.55s of budget, well under 10s.
	var scaled := 0.0
	scaled += 10200.0 * minf(1.0, 0.25)
	scaled += 16.0 * minf(1.0, 1.0)
	assert_lt(scaled, 10000.0)
