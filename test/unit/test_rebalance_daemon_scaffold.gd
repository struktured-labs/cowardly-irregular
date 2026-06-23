extends GutTest

## tick 41: scaffold for the rebalance daemon (user directive 2026-06-22
## — "the game needs to be constantly attempting to rebalance itself
## using the llm as guidance").
##
## This tick is the SCAFFOLD only. consider() logs what it WOULD
## propose without calling the LLM yet. Later ticks add the LLM call,
## the structured-output schema, the safe-apply layer, and the player-
## review UI.
##
## Pins:
##   - RebalanceDaemon class exists with the right shape
##   - consider() throttles repeat calls (the daemon shouldn't burn
##     LLM budget when the player wipes 10 times in 5 minutes)
##   - GameState owns one as `rebalance_daemon` and persists it
##   - GameState.llm_rebalance_enabled opt-in flag exists


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_rebalance_daemon_class_exists() -> void:
	var src := _read("res://src/llm/RebalanceDaemon.gd")
	assert_true(src.contains("class_name RebalanceDaemon"),
		"RebalanceDaemon class must be declared")
	assert_true(src.contains("extends RefCounted"),
		"RebalanceDaemon must extend RefCounted — owned by GameState, not an autoload")


func test_consider_method_signature() -> void:
	var src := _read("res://src/llm/RebalanceDaemon.gd")
	# Settings flag check, GameLoop call sites, future LLM integration
	# all touch this method. Sig must be stable.
	assert_true(src.contains("func consider(trigger_type: String, context: Dictionary) -> bool"),
		"consider() must take (trigger_type, context) and return bool — bool result so caller knows if it was throttled")


func test_consider_throttles_repeat_calls() -> void:
	# A 10-wipe streak shouldn't fire 10 LLM calls. Daemon enforces a
	# minimum interval between considerations.
	var daemon = load("res://src/llm/RebalanceDaemon.gd").new()
	# Shorten the interval for the test — default is 60s, we test that
	# the throttle EXISTS, not its specific value.
	daemon.min_consideration_interval_sec = 999.0
	var first: bool = daemon.consider("party_wipe", {"map_id": "whispering_cave"})
	assert_true(first, "first consider() must succeed")
	var second: bool = daemon.consider("party_wipe", {"map_id": "whispering_cave"})
	assert_false(second, "second consider() within the interval must be throttled (returns false)")
	assert_eq(daemon.pending.size(), 1,
		"only one proposal should land in pending when the second was throttled")


func test_consider_records_trigger_and_context() -> void:
	# The proposal must capture WHAT triggered it so the review UI
	# (later tick) can show "rebalance considered after Mordaine wipe".
	var daemon = load("res://src/llm/RebalanceDaemon.gd").new()
	daemon.min_consideration_interval_sec = 0.0
	daemon.consider("boss_defeat", {"boss": "cave_rat_king", "turns": 7})
	assert_eq(daemon.pending.size(), 1, "consider() must append exactly one proposal")
	var proposal: Dictionary = daemon.pending[0]
	assert_eq(str(proposal.get("trigger", "")), "boss_defeat",
		"proposal must record the trigger type")
	var summary: String = str(proposal.get("context_summary", ""))
	assert_true(summary.contains("boss=cave_rat_king"),
		"proposal context summary must include the trigger context — boss name in this case")


func test_pending_cap_is_enforced() -> void:
	# Old proposals get dropped — ring-buffer pattern like EventLog.
	var daemon = load("res://src/llm/RebalanceDaemon.gd").new()
	daemon.min_consideration_interval_sec = 0.0
	for i in range(30):
		daemon.consider("manual", {"i": i})
	assert_lte(daemon.pending.size(), daemon.PENDING_CAP,
		"pending queue must not exceed PENDING_CAP — older proposals dropped first")


func test_to_dict_from_dict_round_trip() -> void:
	# Daemon state must survive save/load.
	var daemon_a = load("res://src/llm/RebalanceDaemon.gd").new()
	daemon_a.min_consideration_interval_sec = 0.0
	daemon_a.consider("party_wipe", {"map_id": "fire_dragon_cave"})
	var snap: Dictionary = daemon_a.to_dict()
	var daemon_b = load("res://src/llm/RebalanceDaemon.gd").new()
	daemon_b.from_dict(snap)
	assert_eq(daemon_b.pending.size(), 1,
		"round-trip must preserve pending proposals")
	assert_eq(str(daemon_b.pending[0].get("trigger", "")), "party_wipe",
		"round-trip must preserve proposal trigger")


func test_game_state_owns_a_daemon_and_flag() -> void:
	var src := _read("res://src/meta/GameState.gd")
	assert_true(src.contains("var llm_rebalance_enabled: bool = false"),
		"GameState must declare the opt-in flag (default off)")
	assert_true(src.contains("var rebalance_daemon: RebalanceDaemon"),
		"GameState must own a RebalanceDaemon instance")
	# Instantiate in _ready alongside event_log.
	assert_true(src.contains("rebalance_daemon = RebalanceDaemon.new()"),
		"GameState._ready must instantiate the daemon")


func test_game_state_persists_daemon_and_flag() -> void:
	var src := _read("res://src/meta/GameState.gd")
	# Write side — _create_save_data includes both the flag AND the
	# daemon's serialized state.
	assert_true(src.contains("\"llm_rebalance_enabled\": llm_rebalance_enabled"),
		"_create_save_data must include llm_rebalance_enabled")
	assert_true(src.contains("\"rebalance_daemon\": rebalance_daemon.to_dict()"),
		"_create_save_data must include the daemon's serialized pending+applied state")
	# Read side — _apply_save_data restores both.
	assert_true(src.contains("save_data[\"llm_rebalance_enabled\"]"),
		"_apply_save_data must read llm_rebalance_enabled")
	assert_true(src.contains("rebalance_daemon.from_dict"),
		"_apply_save_data must restore the daemon state")
