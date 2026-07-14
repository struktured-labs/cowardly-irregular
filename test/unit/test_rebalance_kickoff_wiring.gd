extends GutTest

## tick 44: completes the rebalance trigger → LLM call data path.
##
## GameLoop's wipe + boss-defeat handlers now call
## _kick_off_rebalance_fetch.call_deferred after consider() succeeds.
## The deferred call runs the async request_llm_proposal so the LLM
## fetch lands by the time the player reaches the (future) review UI.
##
## Pins:
##   - Helper exists with the right signature
##   - Wipe + boss-defeat sites both call_deferred to the helper
##   - Both sites only kick off if consider() returned true (not
##     throttled) — otherwise we'd spend the LLM budget on dropped
##     considerations
##   - Helper passes recent EventLog entries for trend context

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(GAME_LOOP)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_kickoff_helper_exists_with_idx_arg() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func _kick_off_rebalance_fetch(proposal_idx: int)"),
		"_kick_off_rebalance_fetch must take a proposal_idx arg — without it the helper can't address which proposal to fill")


func test_kickoff_passes_recent_events_for_trend_context() -> void:
	# Daemon's request_llm_proposal accepts recent_events so the LLM
	# can tell "first wipe" from "tenth wipe in 20 minutes". The
	# helper must pull from EventLog.recent(N).
	var body := _body_of("_kick_off_rebalance_fetch")
	assert_true(body.contains("event_log.recent"),
		"helper must pull recent events from EventLog for trend context")
	assert_true(body.contains("request_llm_proposal"),
		"helper must call request_llm_proposal — the whole point of the kickoff")
	# Must await — the LLM call is async.
	assert_true(body.contains("await"),
		"helper must await the LLM call — without await it returns a coroutine that nobody observes")


func test_kickoff_guards_against_missing_game_state() -> void:
	# call_deferred runs on the next idle frame — could happen during
	# scene swap where GameState briefly looks weird. Defensive return
	# instead of crash.
	var body := _body_of("_kick_off_rebalance_fetch")
	assert_true(body.contains("GameState == null"),
		"helper must guard against null GameState — defensive for scene-swap timing")
	assert_true(body.contains("rebalance_daemon == null"),
		"helper must guard against null daemon")


func test_wipe_site_only_kicks_off_when_consider_succeeded() -> void:
	# consider() returns false when throttled. Without the check, a
	# throttled trigger would still spawn an LLM call for a stale
	# proposal slot — wasted spend.
	#
	# Anchor on the kickoff line; that lets us inspect the surrounding
	# context (var fired + if fired) regardless of where the trigger
	# string sits on the same line.
	var src := _read(GAME_LOOP)
	var idx := src.find("RebalanceDaemonScript.TRIGGER_PARTY_WIPE")
	assert_gt(idx, -1, "wipe trigger site must exist")
	# Window spans both before and after the trigger so var fired
	# (which appears earlier on the same line) is included.
	var window_start: int = max(0, idx - 200)
	var window: String = src.substr(window_start, 500)
	assert_true(window.contains("var fired: bool"),
		"wipe site must capture consider()'s bool result so we don't kick off on throttled calls")
	assert_true(window.contains("if fired:"),
		"wipe site must gate the kickoff on consider() succeeding")
	assert_true(window.contains("_kick_off_rebalance_fetch.call_deferred"),
		"wipe site must call_deferred the kickoff — sync wipe handler can't await directly")


func test_boss_defeat_site_only_kicks_off_when_consider_succeeded() -> void:
	var src := _read(GAME_LOOP)
	var idx := src.find("RebalanceDaemonScript.TRIGGER_BOSS_DEFEAT")
	assert_gt(idx, -1, "boss-defeat trigger site must exist")
	var window_start: int = max(0, idx - 200)
	var window: String = src.substr(window_start, 500)
	assert_true(window.contains("var fired: bool"),
		"boss-defeat site must capture consider()'s bool result")
	assert_true(window.contains("if fired:"),
		"boss-defeat site must gate the kickoff on consider() succeeding")
	assert_true(window.contains("_kick_off_rebalance_fetch.call_deferred"),
		"boss-defeat site must call_deferred the kickoff")


func test_call_deferred_uses_size_minus_one_idx() -> void:
	# The proposal we want to fill is the one consider() just appended
	# — i.e. pending.size() - 1. If a future refactor passes 0 or
	# pending.size(), we'd fill the wrong proposal (or OOB).
	var src := _read(GAME_LOOP)
	# Both sites should reference pending.size() - 1.
	var occurrences: int = 0
	var idx := 0
	while true:
		idx = src.find("pending.size() - 1", idx)
		if idx < 0:
			break
		occurrences += 1
		idx += 1
	assert_gte(occurrences, 2,
		"both kickoff sites must address the freshly-appended proposal via pending.size() - 1")
