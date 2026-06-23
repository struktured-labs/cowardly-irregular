extends GutTest

## tick 43: RebalanceDaemon gains the LLM-call piece. Schema, prompt
## builder, and the async request_llm_proposal method.
##
## Tick 44+ will wire request_llm_proposal into GameLoop after
## consider() so the actual fetch fires. This tick keeps the daemon
## file changes scoped to the LLM contract.


const DAEMON_PATH := "res://src/llm/RebalanceDaemon.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_schema_has_required_fields() -> void:
	# LLMService._guard_json checks the schema's required keys exist
	# in the response. Missing any of these means the proposal can't
	# carry the LLM verdict into the apply layer.
	var src := _read(DAEMON_PATH)
	for field in ["verdict", "confidence", "deltas", "reason"]:
		assert_true(src.contains("\"" + field + "\""),
			"REBALANCE_SCHEMA must include the '%s' field — needed by the apply layer" % field)


func test_verdict_enum_is_three_states() -> void:
	# 'nudge_easier' / 'nudge_harder' / 'no_change'. Any other value
	# from the LLM gets fallback'd by _guard_json. Pin the exact set
	# so a future LLM-prompt rewrite that adds e.g. 'reset' doesn't
	# silently get accepted without an apply-layer handler.
	var src := _read(DAEMON_PATH)
	assert_true(src.contains("\"nudge_easier\""),
		"verdict enum must include 'nudge_easier'")
	assert_true(src.contains("\"nudge_harder\""),
		"verdict enum must include 'nudge_harder'")
	assert_true(src.contains("\"no_change\""),
		"verdict enum must include 'no_change'")


func test_safe_delta_band_constants_exist() -> void:
	# Apply layer (tick 44+) uses these to decide auto-apply vs review.
	# Pin literally so changes to the safety band are visible diffs.
	var src := _read(DAEMON_PATH)
	assert_true(src.contains("SAFE_DELTA_MIN"),
		"safe-delta-min constant must exist — the apply layer reads it")
	assert_true(src.contains("SAFE_DELTA_MAX"),
		"safe-delta-max constant must exist — the apply layer reads it")
	assert_true(src.contains("AUTO_APPLY_CONFIDENCE"),
		"auto-apply confidence threshold must exist")


func test_build_prompt_returns_a_real_string() -> void:
	# Pure-function: no Engine.get_main_loop, no LLMService, no async.
	# Safe to call inline in tests.
	var daemon = load(DAEMON_PATH).new()
	var prompt: String = daemon.build_prompt("party_wipe", {"map_id": "fire_dragon_cave", "survivors": 0}, [])
	assert_gt(prompt.length(), 100,
		"prompt must be substantive — under 100 chars probably means a stub leaked through")
	# Must include the trigger AND the context keys so the LLM has
	# something concrete to reason about.
	assert_true(prompt.contains("party_wipe"),
		"prompt must mention the trigger type")
	assert_true(prompt.contains("fire_dragon_cave"),
		"prompt must inject context values — without them the LLM gets a generic ask")


func test_build_prompt_lists_allowed_constants() -> void:
	# LLM must know WHICH constants it's allowed to nudge. Without an
	# explicit list, free-text constants will leak into the schema
	# response and fail the apply-layer's safelist check.
	var daemon = load(DAEMON_PATH).new()
	var prompt: String = daemon.build_prompt("manual", {}, [])
	for c in ["exp_multiplier", "gold_multiplier", "encounter_rate_modifier"]:
		assert_true(prompt.contains(c),
			"prompt must list allowed constant '%s' explicitly" % c)


func test_build_prompt_caps_delta_band() -> void:
	# Prompt instructs the LLM to stay within ±15%. Without this,
	# the LLM will sometimes propose 2x/0.5x multipliers and they all
	# get rejected by the safety band — wasted call.
	var daemon = load(DAEMON_PATH).new()
	var prompt: String = daemon.build_prompt("manual", {}, [])
	assert_true(prompt.contains("15") or prompt.contains("0.85") or prompt.contains("1.15"),
		"prompt must communicate the safe delta band (±15%% / 0.85-1.15) so the LLM doesn't waste calls on out-of-band proposals")


func test_build_prompt_includes_recent_events() -> void:
	# Recent EventLog entries give the LLM context beyond the single
	# trigger. Without them it can't tell if this is the first wipe or
	# the tenth in a session.
	var daemon = load(DAEMON_PATH).new()
	var recent: Array = [
		{"type": "boss_defeat", "summary": "Defeated Cave Rat King"},
		{"type": "party_wipe", "summary": "Party wiped in Pyrroth Cave"},
	]
	var prompt: String = daemon.build_prompt("party_wipe", {}, recent)
	assert_true(prompt.contains("RECENT EVENTS"),
		"prompt must label the recent-events section so the LLM can see the trend")
	assert_true(prompt.contains("Defeated Cave Rat King"),
		"recent event summaries must appear in the prompt verbatim")


func test_request_llm_proposal_fails_for_bad_idx() -> void:
	# Defensive: out-of-range idx must NOT crash. Caller may pass a
	# stale index if proposals were ring-dropped.
	var daemon = load(DAEMON_PATH).new()
	var ok_negative: bool = await daemon.request_llm_proposal(-1, [])
	assert_false(ok_negative, "negative idx must return false")
	var ok_oob: bool = await daemon.request_llm_proposal(99, [])
	assert_false(ok_oob, "out-of-range idx must return false")


func test_request_llm_proposal_fails_when_service_missing() -> void:
	# Test environment doesn't have LLMService autoload running.
	# request_llm_proposal must mark the proposal status and return
	# false instead of awaiting forever.
	var daemon = load(DAEMON_PATH).new()
	daemon.min_consideration_interval_sec = 0.0
	daemon.consider("party_wipe", {"map_id": "whispering_cave"})
	assert_eq(daemon.pending.size(), 1, "consider must have appended one proposal")
	var ok: bool = await daemon.request_llm_proposal(0, [])
	assert_false(ok, "request must return false when LLMService is unreachable")
	var status: String = str(daemon.pending[0].get("status", ""))
	# Either 'failed_no_tree' (when run outside SceneTree) or
	# 'failed_unavailable' (when LLMService isn't an autoload in this
	# test run). Both indicate the daemon gave up cleanly.
	assert_true(status.begins_with("failed_"),
		"proposal status must indicate why the LLM call failed — got '%s'" % status)
