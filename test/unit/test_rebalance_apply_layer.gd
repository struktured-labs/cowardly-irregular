extends GutTest

## tick 45: apply layer. The piece that actually changes game_constants.
##
## Safety contract:
##   - Unknown constant → APPLY_REJECTED (never writes to game_constants)
##   - Multiplier outside [0.85, 1.15] → APPLY_NEEDS_REVIEW (preserved
##     for player review, not silently dropped)
##   - Confidence < 0.7 → APPLY_NEEDS_REVIEW
##   - verdict='no_change' → APPLY_NO_CHANGE (proposal moved to applied[])
##   - Otherwise → APPLY_APPLIED (deltas written, proposal moved to applied[])

const DAEMON_PATH := "res://src/llm/RebalanceDaemon.gd"


func _make_daemon():
	return load(DAEMON_PATH).new()


func _append_proposal(daemon, verdict: String, confidence: float, deltas: Array) -> int:
	# Bypass consider() so we can pin specific verdict/deltas without
	# making an actual LLM call.
	daemon.pending.append({
		"trigger": "manual",
		"ts": 0,
		"context_summary": "test",
		"status": "proposed",
		"verdict": verdict,
		"confidence": confidence,
		"deltas": deltas,
		"reason": "test",
	})
	return daemon.pending.size() - 1


func test_unknown_constant_is_rejected_not_applied() -> void:
	# Critical safety: an unknown constant must NOT write to
	# game_constants. The LLM might hallucinate 'boss_hp_multiplier'
	# or similar that doesn't exist; the safelist is the gate.
	var daemon = _make_daemon()
	var idx: int = _append_proposal(daemon, "nudge_easier", 0.9, [
		{"constant": "boss_hp_multiplier", "multiplier": 0.9, "reason": "wipe streak"}
	])
	var result: String = daemon.try_auto_apply(idx)
	assert_eq(result, daemon.APPLY_REJECTED,
		"unknown constant must trigger APPLY_REJECTED — silently dropping would let the LLM scribble anywhere")


func test_out_of_band_multiplier_goes_to_review() -> void:
	# Multipliers outside [0.85, 1.15] must NOT auto-apply — but they
	# ARE valid constants, so the proposal stays in pending[] for the
	# player to decide.
	var daemon = _make_daemon()
	var idx: int = _append_proposal(daemon, "nudge_easier", 0.9, [
		{"constant": "exp_multiplier", "multiplier": 0.5, "reason": "harsh wipe"}
	])
	var result: String = daemon.try_auto_apply(idx)
	assert_eq(result, daemon.APPLY_NEEDS_REVIEW,
		"out-of-band multiplier must route to NEEDS_REVIEW (player decides), not be silently applied")
	assert_eq(daemon.pending.size(), 1,
		"NEEDS_REVIEW proposals must STAY in pending[] for the review UI to surface")
	assert_eq(str(daemon.pending[0].get("status", "")), "needs_review",
		"proposal status must be marked 'needs_review' so the UI can filter")


func test_low_confidence_goes_to_review() -> void:
	# Even with safe deltas, confidence below the threshold means the
	# LLM wasn't sure — surface to the player rather than silently
	# nudge the world.
	var daemon = _make_daemon()
	var idx: int = _append_proposal(daemon, "nudge_easier", 0.5, [
		{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "barely"}
	])
	var result: String = daemon.try_auto_apply(idx)
	assert_eq(result, daemon.APPLY_NEEDS_REVIEW,
		"low confidence must route to NEEDS_REVIEW even with safe deltas")


func test_no_change_verdict_is_logged_in_applied() -> void:
	# 'no_change' means the LLM thinks the curve is fine. The proposal
	# should still move to applied[] (so the player can see "AI
	# considered, decided no nudge needed" in the diegetic log).
	var daemon = _make_daemon()
	var idx: int = _append_proposal(daemon, "no_change", 0.8, [])
	var result: String = daemon.try_auto_apply(idx)
	assert_eq(result, daemon.APPLY_NO_CHANGE,
		"verdict='no_change' must return APPLY_NO_CHANGE")
	assert_eq(daemon.pending.size(), 0,
		"NO_CHANGE proposals must move out of pending[]")
	assert_eq(daemon.applied.size(), 1,
		"NO_CHANGE proposals must land in applied[] for the diegetic log")


func test_safe_high_confidence_applies_and_moves() -> void:
	# Happy path: safe constants + safe multipliers + high confidence
	# = applied. Proposal moves from pending[] to applied[], deltas
	# written to GameState.game_constants.
	# NOTE: this test calls into the actual /root/GameState autoload
	# if one is running. Without one the apply path early-returns to
	# NEEDS_REVIEW (the daemon refuses to lose deltas).
	var daemon = _make_daemon()
	var idx: int = _append_proposal(daemon, "nudge_easier", 0.9, [
		{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "first wipe of the run"}
	])
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var gs = null
	if tree != null and tree.root != null:
		gs = tree.root.get_node_or_null("GameState")
	if gs == null or not ("game_constants" in gs):
		# Defensive: in some test runs GameState isn't an autoload.
		# Skip the happy-path assertion but pin the NEEDS_REVIEW
		# fallback (deltas preserved, not lost).
		var result: String = daemon.try_auto_apply(idx)
		assert_eq(result, daemon.APPLY_NEEDS_REVIEW,
			"without GameState, apply must fall back to NEEDS_REVIEW so deltas aren't silently lost")
		return
	# Real GameState present — snapshot the constant, apply, verify.
	var before: float = float(gs.game_constants.get("exp_multiplier", 1.0))
	var result: String = daemon.try_auto_apply(idx)
	assert_eq(result, daemon.APPLY_APPLIED,
		"safe + high-confidence proposal must APPLY_APPLIED")
	var after: float = float(gs.game_constants.get("exp_multiplier", 1.0))
	assert_almost_eq(after, before * 1.05, 0.001,
		"exp_multiplier must be multiplied by the delta")
	assert_eq(daemon.pending.size(), 0,
		"applied proposals must leave pending[]")
	assert_eq(daemon.applied.size(), 1,
		"applied proposals must land in applied[]")
	# Restore the constant so subsequent tests aren't affected.
	gs.game_constants["exp_multiplier"] = before


func test_summarize_applied_formats_percentage() -> void:
	# The diegetic Toast pulls its message from this formatter. Pin
	# the format so a future refactor doesn't break the Toast text.
	var daemon = _make_daemon()
	var prop: Dictionary = {
		"verdict": "nudge_easier",
		"applied_changes": [
			{"constant": "exp_multiplier", "before": 1.0, "after": 1.05, "multiplier": 1.05},
		],
	}
	var msg: String = daemon.summarize_applied(prop)
	assert_true(msg.contains("Auto-rebalance"),
		"summary must lead with 'Auto-rebalance' so the Toast reads as a system message")
	assert_true(msg.contains("exp_multiplier"),
		"summary must name the constant that changed")
	assert_true(msg.contains("+5%"),
		"summary must format percentage with sign (+5% for 1.05x)")


func test_allowed_constants_list_matches_game_state() -> void:
	# Safelist mirrors the keys that game_constants actually has —
	# applying to a key not in game_constants is a no-op write.
	var src := FileAccess.get_file_as_string(DAEMON_PATH)
	for c in ["exp_multiplier", "gold_multiplier", "encounter_rate"]:
		assert_true(src.contains("\"" + c + "\""),
			"ALLOWED_CONSTANTS must include '%s' (matches game_constants key)" % c)
	# Negative assertion: the prior wrong name (encounter_rate_modifier)
	# must NOT appear in the daemon — that one wasn't a real
	# game_constants key.
	assert_false(src.contains("encounter_rate_modifier"),
		"prior wrong name encounter_rate_modifier must be gone — real game_constants key is 'encounter_rate'")
