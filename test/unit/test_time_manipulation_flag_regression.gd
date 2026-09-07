extends GutTest

## tick 466: monsters.json top-level time_manipulation flag now
## actually surfaces a "TEMPORAL ANOMALY" warning at battle start.
##
## Pre-tick monsters.json authored:
##   time_phantom: time_manipulation = true
##   description: "A meta-boss that exists between save states.
##                  Can rewind its own actions."
## but no code path read the field. The boss's abilities (
## rewind_turn, time_stop, temporal_strike, future_sight) were
## already wired, but the flag itself gave players no signal that
## the boss they're facing CAN manipulate time — same pattern as
## the pre-tick-420 silent very_dangerous / extremely_dangerous
## warnings.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_start_battle_reads_flag() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the flag read alongside the danger warnings.
	var idx: int = src.find("bool(data_t.get(\"time_manipulation\", false))")
	assert_gt(idx, -1,
		"start_battle must read time_manipulation flag from monster data")


func test_emits_temporal_anomaly_line() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("⧗ TEMPORAL ANOMALY"),
		"a TEMPORAL ANOMALY battle-log line must be emitted")


func test_announce_breaks_after_first_match() -> void:
	# Pin the early-break so multi-time-manipulator parties don't
	# spam duplicate lines.
	var src := _read(BATTLE_MANAGER_PATH)
	var idx: int = src.find("bool(data_t.get(\"time_manipulation\", false))")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("break"),
		"loop must break after the first announce so duplicates don't fire")


func test_announce_runs_alongside_danger_tier() -> void:
	# Pin that the time_manipulation block sits AFTER the max_danger
	# emit (so both lines fire if a time-manipulator is also
	# extremely_dangerous).
	var src := _read(BATTLE_MANAGER_PATH)
	var danger_idx: int = src.find("match max_danger:")
	var time_idx: int = src.find("bool(data_t.get(\"time_manipulation\", false))")
	assert_gt(danger_idx, -1)
	assert_gt(time_idx, -1)
	assert_lt(danger_idx, time_idx,
		"time_manipulation announce must come AFTER the max_danger match — both lines should fire when applicable")


func test_announce_fires_before_battle_started() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var time_idx: int = src.find("⧗ TEMPORAL ANOMALY")
	# Find the battle_started.emit() that follows the danger banner.
	var started_idx: int = src.find("battle_started.emit()", time_idx)
	assert_gt(time_idx, -1)
	assert_gt(started_idx, -1)
	assert_lt(time_idx, started_idx,
		"time_manipulation announce must fire BEFORE battle_started.emit so listeners see the warning context")


func test_data_still_authors_time_manipulation() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var found: bool = false
	for mid in data.keys():
		var entry: Dictionary = data[mid]
		if bool(entry.get("time_manipulation", false)):
			found = true
			break
	assert_true(found,
		"monsters.json must still author time_manipulation=true on at least one monster")
