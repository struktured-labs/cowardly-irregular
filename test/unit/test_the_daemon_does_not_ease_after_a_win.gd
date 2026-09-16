extends GutTest

## HELD BRANCH — this is a difficulty-behaviour change and struktured's call. The
## guard exists so the option can be seen rather than argued.
##
## MEASURED 2026-09-16, live llama3, 12 samples per cell, through RebalanceDaemon's
## own build_prompt, on two boards with opposite correct answers:
##
##   triple wipe                                     nudge_easier 12/12   correct
##   boss beaten, nobody died, party at 95% HP       nudge_easier 11/12
##   ... with the verdict list reordered             nudge_easier 12/12   not position bias
##   ... with the prompt naming THIS board and
##       "beaten with nobody dying -> nudge_harder"  nudge_easier 12/12   not wording
##
## So the verdict carries no evidence about difficulty, and the daemon applied it
## straight after a win — a bounded one-way ratchet toward easier.
##
## The gate declines to AUTO-apply an easing verdict on a victory trigger and sends it
## to the review queue. It does not delete the proposal, judge its size, or touch
## force_apply: an explicit player yes still applies.

const RebalanceDaemonScript = preload("res://src/llm/RebalanceDaemon.gd")

var _daemon = null


func before_each() -> void:
	_daemon = RebalanceDaemonScript.new()


func _proposal(trigger: String, verdict: String) -> int:
	_daemon.pending.append({
		"trigger": trigger,
		"ts": 0,
		"context_summary": "measured fixture",
		"status": "proposed",
		"verdict": verdict,
		"confidence": 0.9,
		"deltas": [{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "fixture"}],
	})
	return _daemon.pending.size() - 1


func test_easing_straight_after_a_boss_win_is_not_auto_applied() -> void:
	var idx: int = _proposal(_daemon.TRIGGER_BOSS_DEFEAT, "nudge_easier")
	var result: String = _daemon.try_auto_apply(idx)
	assert_eq(result, _daemon.APPLY_NEEDS_REVIEW,
		"the player just won — an easing verdict must not apply itself")
	assert_eq(str(_daemon.pending[idx].get("auto_apply_declined", "")), "eased_after_a_win",
		"and the reason must be recorded, not silent")


func test_the_proposal_is_kept_for_the_player_to_decide() -> void:
	## Declining to AUTO-apply is not discarding. The review queue is the point.
	var idx: int = _proposal(_daemon.TRIGGER_BOSS_DEFEAT, "nudge_easier")
	_daemon.try_auto_apply(idx)
	assert_eq(_daemon.pending.size(), 1, "the proposal must stay pending")
	assert_eq(_daemon.needs_review_count(), 1, "and be counted for the review badge")


func test_an_explicit_yes_still_applies_it() -> void:
	## force_apply is the player's own decision and this gate must not touch it.
	var idx: int = _proposal(_daemon.TRIGGER_BOSS_DEFEAT, "nudge_easier")
	_daemon.try_auto_apply(idx)
	var forced: String = _daemon.force_apply(idx)
	assert_eq(forced, _daemon.APPLY_APPLIED,
		"a player who reviews it and says yes must still get it")


func test_easing_after_a_WIPE_still_auto_applies() -> void:
	## The half that must not change: after repeated losses, easing is the feature
	## working. A gate that caught this too would disable the daemon, not fix it.
	var idx: int = _proposal(_daemon.TRIGGER_PARTY_WIPE, "nudge_easier")
	var result: String = _daemon.try_auto_apply(idx)
	assert_ne(result, _daemon.APPLY_NEEDS_REVIEW,
		"a wipe is the board this feature exists for — easing must still apply there")


func test_nudge_harder_after_a_win_is_untouched() -> void:
	## The gate keys on the VERDICT, not on the trigger alone. Making the game harder
	## after a win is coherent and must pass straight through.
	var idx: int = _proposal(_daemon.TRIGGER_BOSS_DEFEAT, "nudge_harder")
	var result: String = _daemon.try_auto_apply(idx)
	assert_ne(result, _daemon.APPLY_NEEDS_REVIEW,
		"tightening after a win is exactly what the daemon should be free to do")


func test_no_change_after_a_win_is_untouched() -> void:
	var idx: int = _proposal(_daemon.TRIGGER_BOSS_DEFEAT, "no_change")
	var result: String = _daemon.try_auto_apply(idx)
	assert_eq(result, _daemon.APPLY_NO_CHANGE,
		"'no change' must still record and apply nothing, as before")


func test_the_gate_runs_before_the_confidence_check() -> void:
	## Ordering matters for the recorded reason: a high-confidence easing verdict after
	## a win must be declined FOR THAT REASON, not fall through to a confidence verdict
	## that happens to agree. Otherwise the review queue cannot say why it is there.
	var idx: int = _proposal(_daemon.TRIGGER_BOSS_DEFEAT, "nudge_easier")
	_daemon.pending[idx]["confidence"] = 0.99
	_daemon.try_auto_apply(idx)
	assert_eq(str(_daemon.pending[idx].get("auto_apply_declined", "")), "eased_after_a_win",
		"the recorded reason must be the win, not confidence")
