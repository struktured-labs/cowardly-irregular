extends GutTest

## tick 48: review-layer data API. Surfaces NEEDS_REVIEW proposals to
## the (forthcoming) review panel:
##   force_apply(idx)      — player consents, bypass confidence+band gates
##   dismiss(idx)          — player rejects, move to history with
##                           status='dismissed' (not silent deletion)
##   needs_review_count()  — badge count for the settings menu
##   format_for_review()   — multi-line display string for the panel

const DAEMON_PATH := "res://src/llm/RebalanceDaemon.gd"


func _make_daemon():
	return load(DAEMON_PATH).new()


func _append_pending(daemon, verdict: String, confidence: float, deltas: Array, status: String) -> int:
	daemon.pending.append({
		"trigger": "manual",
		"ts": 0,
		"context_summary": "test",
		"status": status,
		"verdict": verdict,
		"confidence": confidence,
		"deltas": deltas,
		"reason": "test reason",
	})
	return daemon.pending.size() - 1


func test_force_apply_respects_safelist_even_with_consent() -> void:
	# CRITICAL invariant: player consent does NOT unlock arbitrary
	# constants. The LLM's hallucinated 'boss_hp_multiplier' must
	# still be rejected even if the player clicks "Apply".
	var daemon = _make_daemon()
	var idx: int = _append_pending(daemon, "nudge_easier", 0.5, [
		{"constant": "boss_hp_multiplier", "multiplier": 0.9, "reason": "x"}
	], "needs_review")
	var result: String = daemon.force_apply(idx)
	assert_eq(result, daemon.APPLY_REJECTED,
		"force_apply must STILL reject unsafelisted constants — consent doesn't unlock arbitrary writes")


func test_force_apply_bypasses_confidence_gate() -> void:
	# Low-confidence proposal — try_auto_apply would route to
	# NEEDS_REVIEW. force_apply must apply it if GameState is present
	# (or fall back to REJECTED if not, but never NEEDS_REVIEW —
	# force_apply doesn't return that result).
	var daemon = _make_daemon()
	var idx: int = _append_pending(daemon, "nudge_easier", 0.2, [
		{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "x"}
	], "needs_review")
	var result: String = daemon.force_apply(idx)
	# Either APPLY_APPLIED (GameState present) or APPLY_REJECTED
	# (GameState absent in test env). Critically NOT NEEDS_REVIEW.
	assert_ne(result, daemon.APPLY_NEEDS_REVIEW,
		"force_apply must never return NEEDS_REVIEW — that's the auto-apply state, not the consent path")


func test_force_apply_bypasses_out_of_band_multiplier() -> void:
	# Out-of-band multiplier (0.5 = -50%) — try_auto_apply routes to
	# review. force_apply with safelisted constant should apply (or
	# REJECT if GameState absent).
	var daemon = _make_daemon()
	var idx: int = _append_pending(daemon, "nudge_easier", 0.9, [
		{"constant": "exp_multiplier", "multiplier": 0.5, "reason": "x"}
	], "needs_review")
	var result: String = daemon.force_apply(idx)
	assert_ne(result, daemon.APPLY_NEEDS_REVIEW,
		"force_apply must accept out-of-band multipliers (player saw and confirmed)")


func test_dismiss_moves_to_applied_with_status() -> void:
	# Dismiss is NOT silent deletion — proposal lands in applied[] so
	# the history surface can show "you rejected 3 proposals this
	# session". Helps the player understand what the daemon is doing.
	var daemon = _make_daemon()
	var idx: int = _append_pending(daemon, "nudge_easier", 0.5, [
		{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "x"}
	], "needs_review")
	var ok: bool = daemon.dismiss(idx)
	assert_true(ok, "dismiss must return true for a valid idx")
	assert_eq(daemon.pending.size(), 0,
		"dismissed proposals must leave pending[]")
	assert_eq(daemon.applied.size(), 1,
		"dismissed proposals must land in applied[] (history, not silent delete)")
	assert_eq(str(daemon.applied[0].get("status", "")), "dismissed",
		"applied[] entry must record status='dismissed' so history surface can distinguish from applied")


func test_dismiss_bad_idx_returns_false() -> void:
	var daemon = _make_daemon()
	assert_false(daemon.dismiss(-1), "negative idx must return false")
	assert_false(daemon.dismiss(99), "out-of-range idx must return false")


func test_needs_review_count_filters_by_status() -> void:
	# Only proposals with status='needs_review' count. 'proposed',
	# 'awaiting_llm', 'stub', etc. are pending-but-not-actionable.
	var daemon = _make_daemon()
	_append_pending(daemon, "nudge_easier", 0.9, [], "needs_review")
	_append_pending(daemon, "nudge_easier", 0.9, [], "awaiting_llm")
	_append_pending(daemon, "nudge_easier", 0.9, [], "needs_review")
	_append_pending(daemon, "nudge_easier", 0.9, [], "stub")
	assert_eq(daemon.needs_review_count(), 2,
		"needs_review_count must filter by status — 2 of the 4 pending in this setup")


func test_format_for_review_includes_verdict_confidence_deltas() -> void:
	# Display string for the review panel. Pin the key data points
	# so a future formatter rewrite doesn't accidentally hide info.
	var daemon = _make_daemon()
	var prop: Dictionary = {
		"trigger": "party_wipe",
		"verdict": "nudge_easier",
		"confidence": 0.8,
		"reason": "Three wipes in a row",
		"deltas": [
			{"constant": "exp_multiplier", "multiplier": 1.10, "reason": "more XP per win"},
		],
	}
	var msg: String = daemon.format_for_review(prop)
	assert_true(msg.contains("nudge_easier"),
		"display must show the verdict")
	assert_true(msg.contains("80%") or msg.contains("80 %"),
		"display must show confidence as percentage")
	assert_true(msg.contains("party_wipe"),
		"display must show what triggered the proposal")
	assert_true(msg.contains("Three wipes in a row"),
		"display must surface the LLM's reason")
	assert_true(msg.contains("exp_multiplier"),
		"display must list constant names from the deltas")
	assert_true(msg.contains("+10%"),
		"display must format delta multipliers as signed percentages")


func test_format_for_review_handles_empty_deltas() -> void:
	# verdict='no_change' produces a proposal with empty deltas.
	# Display must NOT silently render as malformed.
	var daemon = _make_daemon()
	var prop: Dictionary = {
		"trigger": "boss_defeat",
		"verdict": "no_change",
		"confidence": 0.95,
		"reason": "Curve looks right",
		"deltas": [],
	}
	var msg: String = daemon.format_for_review(prop)
	assert_true(msg.contains("no concrete deltas") or msg.contains("(no"),
		"empty deltas must surface as an explicit note — silent omission would look like a bug to the user")
