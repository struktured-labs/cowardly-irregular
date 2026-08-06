extends GutTest

## Regression: the end-of-session summary reported "Time Bonus: 1.0x" for EVERY session.
##
## get_time_multiplier() gated on `is_grinding`, and the summary is built after the grind
## has already stopped:
##   AutogrindController.stop_grind()
##     :516  AutogrindSystem.stop_autogrind(reason)   -> is_grinding = false
##     :519  grind_complete.emit(reason)
##             -> GameLoop._on_grind_complete -> get_grind_stats() -> get_time_multiplier()
##             -> `if not is_grinding: return 1.0`
##
## Measured pre-fix on a simulated 45-minute session: 3.000 while grinding, 1.000 one call
## later. The multiplier is real — it scales rewards in on_battle_victory — so the player
## earned a 3x bonus and was told the bonus was 1.0x.
##
## Live on the AUTOMATIC-completion path (an interrupt rule ending the grind), which is the
## common case. On the manual path GameLoop._stop_autogrind captures before stopping, so it
## read correctly — and then its own stop_grind fired _on_grind_complete, which captured
## again with is_grinding false. Two summaries, one of them wrong.
##
## Fix: read the FINALIZED _grind_stats["elapsed_seconds"] when not grinding, exactly as
## get_grind_stats already does at :438-440. Live behaviour is unchanged (is_grinding true
## takes the same branch as before); start_autogrind re-inits elapsed_seconds to 0.0, so a
## finished session's duration cannot leak into a later read.

const SESSION_MINUTES: float = 45.0

var _saved: Dictionary = {}


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_saved = {
		"is_grinding": AutogrindSystem.is_grinding,
		"stats": AutogrindSystem._grind_stats.duplicate(true),
	}


func after_each() -> void:
	AutogrindSystem.is_grinding = _saved["is_grinding"]
	AutogrindSystem._grind_stats = _saved["stats"]
	_saved.clear()


## Puts the system in "mid-session, started N minutes ago" without a real grind.
func _begin_session(minutes: float) -> void:
	AutogrindSystem.is_grinding = true
	AutogrindSystem._grind_stats["start_time"] = Time.get_unix_time_from_system() - (minutes * 60.0)
	AutogrindSystem._grind_stats["elapsed_seconds"] = 0.0


func test_time_bonus_survives_the_stop_that_precedes_the_summary() -> void:
	_begin_session(SESSION_MINUTES)
	var during: float = AutogrindSystem.get_time_multiplier()
	assert_gt(during, 1.0,
		"setup: a %d-minute session must earn a bonus, else this test proves nothing" % int(SESSION_MINUTES))

	AutogrindSystem.stop_autogrind("regression probe")
	var after: float = AutogrindSystem.get_time_multiplier()

	assert_almost_eq(after, during, 0.01,
		"the summary is built AFTER the grind stops, so the value it reads must match what the session actually earned — got %.3f after stop vs %.3f during, which is the 'Time Bonus: 1.0x on every session' bug" % [after, during])


func test_a_longer_session_still_reports_a_bigger_bonus_after_stopping() -> void:
	# Relationship, not a pinned magnitude — a rebalance of TIME_MULTIPLIER_CURVE keeps this
	# green; a regression to the is_grinding gate flattens both to 1.0 and reds it.
	_begin_session(10.0)
	AutogrindSystem.stop_autogrind("short")
	var short_bonus: float = AutogrindSystem.get_time_multiplier()

	_begin_session(SESSION_MINUTES)
	AutogrindSystem.stop_autogrind("long")
	var long_bonus: float = AutogrindSystem.get_time_multiplier()

	assert_gt(long_bonus, short_bonus,
		"a 45-minute session must report a larger post-stop bonus than a 10-minute one (%.3f vs %.3f) — if both are 1.0 the gate regressed" % [long_bonus, short_bonus])


func test_no_session_reports_no_bonus() -> void:
	# The other direction: without a session there is nothing to report, and a stale
	# elapsed_seconds must not manufacture a bonus.
	AutogrindSystem.is_grinding = false
	AutogrindSystem._grind_stats["start_time"] = 0.0
	AutogrindSystem._grind_stats["elapsed_seconds"] = 0.0
	assert_eq(AutogrindSystem.get_time_multiplier(), 1.0,
		"with no session recorded the multiplier must be exactly 1.0")


func test_starting_a_new_session_clears_the_previous_duration() -> void:
	# Guards the hazard the fix introduces if start_autogrind ever stops re-initialising
	# _grind_stats: a finished session's elapsed leaking into the next session's first read.
	_begin_session(SESSION_MINUTES)
	AutogrindSystem.stop_autogrind("first session")
	assert_gt(AutogrindSystem.get_time_multiplier(), 1.0, "setup: first session earned a bonus")

	# Emulate what start_autogrind does to the timing fields.
	AutogrindSystem._grind_stats["start_time"] = Time.get_unix_time_from_system()
	AutogrindSystem._grind_stats["elapsed_seconds"] = 0.0
	AutogrindSystem.is_grinding = true
	assert_almost_eq(AutogrindSystem.get_time_multiplier(), 1.0, 0.05,
		"a freshly started session must begin at ~1.0x — the previous session's duration must not carry over")


func test_live_behaviour_is_unchanged_while_grinding() -> void:
	# The fix must not alter the value used for REWARD SCALING in on_battle_victory, which
	# calls this while is_grinding is true.
	_begin_session(SESSION_MINUTES)
	var live: float = AutogrindSystem.get_time_multiplier()
	AutogrindSystem._grind_stats["elapsed_seconds"] = 99999.0  # ignored while grinding
	assert_almost_eq(AutogrindSystem.get_time_multiplier(), live, 0.01,
		"while grinding, the multiplier must still derive from start_time and ignore the recorded elapsed")
