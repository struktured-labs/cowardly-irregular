extends GutTest

## Measured in struktured's own saves, 2026-10-14, at default settings. Once a game constant reaches
## the authored band edge, every clamped apply recorded an "applied" change that changed nothing:
##   save_98  50 recorded changes · 48 clamped · 46 literally `1.15 -> 1.15`, all status "applied"
##   save_99  50 · 42 clamped        save_00  23 · 12 clamped
## His history panel therefore lists ~46 adjustments that never happened, and each one had already
## spent an LLM call. A REPORTED change that did not occur is this project's silent-failure rule
## running backwards. The daemon now reports APPLY_NO_CHANGE, records no phantom change, and says so
## in the log -- it previously printed only `considered` and `throttled`, so no play log could tell
## a resolved proposal from a failed one.

const Daemon := preload("res://src/llm/RebalanceDaemon.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	# Snapshot FIRST: the constants are autoload state and nothing below may skip putting them back.
	_saved_constants = {}
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "game_constants" in gs:
		_saved_constants = (gs.game_constants as Dictionary).duplicate(true)


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "game_constants" in gs and not _saved_constants.is_empty():
		gs.game_constants.clear()
		for k in _saved_constants.keys():
			gs.game_constants[k] = _saved_constants[k]


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


## The ceiling the clamp enforces: the authored baseline times the safe band's top.
func _ceiling(name: String) -> float:
	return float(_gs().DEFAULT_GAME_CONSTANTS[name]) * Daemon.SAFE_DELTA_MAX


func _proposal(deltas: Array, confidence: float = 0.95) -> Dictionary:
	return {
		"status": "proposed", "verdict": "nudge_easier", "confidence": confidence,
		"trigger": "level_up", "reason": "four losses in a row", "deltas": deltas,
	}


func _daemon_with(deltas: Array, confidence: float = 0.95):
	var d = Daemon.new()
	d.pending.append(_proposal(deltas, confidence))
	return d


# ---------------------------------------------------------------- the control


## The fix must not disable applying. A constant with room still moves and still reports it.
func test_a_proposal_with_room_still_applies() -> void:
	var gs = _gs()
	assert_not_null(gs, "CONTROL: no GameState, so nothing below measures the real clamp")
	gs.game_constants["exp_multiplier"] = 1.0
	var d = _daemon_with([{"constant": "exp_multiplier", "multiplier": 1.05}])
	var result: String = d.try_auto_apply(0)
	assert_eq(result, Daemon.APPLY_APPLIED, "a constant at 1.0 has room; this must apply")
	assert_eq(d.applied.size(), 1, "the proposal must reach the history")
	var ch: Array = d.applied[0].get("applied_changes", [])
	assert_eq(ch.size(), 1, "a real change must be recorded")
	assert_gt(float(ch[0]["after"]), float(ch[0]["before"]), "the recorded change must actually move")


# ---------------------------------------------------------------- the defect


func test_a_pinned_constant_reports_no_change_rather_than_applied() -> void:
	var gs = _gs()
	var ceiling: float = _ceiling("exp_multiplier")
	gs.game_constants["exp_multiplier"] = ceiling
	var d = _daemon_with([{"constant": "exp_multiplier", "multiplier": 1.05}])
	var result: String = d.try_auto_apply(0)
	assert_eq(result, Daemon.APPLY_NO_CHANGE,
		"a constant already at its authored ceiling (%.4g) cannot move, so this is not an apply" % ceiling)
	assert_eq(d.applied.size(), 1, "it must still leave pending — his saves reached 17 stale rows")
	assert_eq(d.pending.size(), 0, "the proposal lingered in pending")
	assert_eq(str(d.applied[0].get("status", "")), Daemon.STATUS_AT_LIMIT,
		"the history must say the constants were at their limit, not that something was applied")
	assert_eq((d.applied[0].get("applied_changes", []) as Array).size(), 0,
		"a change that did not happen must not be recorded as one")
	assert_almost_eq(float(gs.game_constants["exp_multiplier"]), ceiling, 0.0001,
		"the constant must be exactly where it was")


func test_the_players_own_apply_press_gets_the_same_answer() -> void:
	var gs = _gs()
	gs.game_constants["encounter_rate"] = float(gs.DEFAULT_GAME_CONSTANTS["encounter_rate"]) * Daemon.SAFE_DELTA_MIN
	var d = _daemon_with([{"constant": "encounter_rate", "multiplier": 0.9}], 0.1)
	assert_eq(d.try_auto_apply(0), Daemon.APPLY_NEEDS_REVIEW, "low confidence must route to review first")
	var result: String = d.force_apply(0)
	assert_eq(result, Daemon.APPLY_NO_CHANGE, "pressing Apply on a pinned constant is still not an apply")
	assert_eq(str(d.applied[0].get("status", "")), Daemon.STATUS_AT_LIMIT, "the forced path must be honest too")
	assert_true(bool(d.applied[0].get("force_applied", false)), "the forced path must keep its own marker")
	assert_eq((d.applied[0].get("applied_changes", []) as Array).size(), 0, "no phantom change on the forced path")


## Straight from his saves: a run of at-limit decisions must leave an EMPTY change history, where
## pre-fix it left one phantom row per decision (46 of them in save_98).
func test_a_run_of_pinned_decisions_records_no_history_at_all() -> void:
	var gs = _gs()
	gs.game_constants["exp_multiplier"] = _ceiling("exp_multiplier")
	var d = Daemon.new()
	for _i in 12:
		d.pending.append(_proposal([{"constant": "exp_multiplier", "multiplier": 1.05}]))
	for _i in 12:
		d.try_auto_apply(0)
	assert_eq(d.pending.size(), 0, "every decision must leave pending")
	assert_eq(d.applied.size(), 12, "every decision must be in the history")
	var phantom: int = 0
	for a in d.applied:
		phantom += (a.get("applied_changes", []) as Array).size()
	assert_eq(phantom, 0, "%d phantom 'applied' change(s) were recorded for constants that never moved" % phantom)


## A MIXED proposal is the case where reporting "nothing applied" would be the NEW lie: one delta is
## pinned, the other has room, so something really did change.
func test_a_mixed_proposal_still_counts_as_applied() -> void:
	var gs = _gs()
	gs.game_constants["exp_multiplier"] = _ceiling("exp_multiplier")
	gs.game_constants["encounter_rate"] = 1.0
	var d = _daemon_with([
		{"constant": "exp_multiplier", "multiplier": 1.05},
		{"constant": "encounter_rate", "multiplier": 0.95},
	])
	assert_eq(d.try_auto_apply(0), Daemon.APPLY_APPLIED,
		"one pinned delta beside one that moved is still an apply")
	var ch: Array = d.applied[0].get("applied_changes", [])
	assert_eq(ch.size(), 2, "both deltas belong in the record, including the pinned one")
	assert_eq(str(d.applied[0].get("status", "")), "applied", "a mixed result is applied, not at-limit")


func test_nothing_moved_reads_the_record_not_the_intent() -> void:
	assert_true(Daemon._nothing_moved([{"before": 1.15, "after": 1.15}]), "an unchanged row is no movement")
	assert_true(Daemon._nothing_moved([]), "an empty record cannot have moved anything")
	assert_false(Daemon._nothing_moved([{"before": 1.0, "after": 1.05}]), "a changed row is movement")
	assert_false(Daemon._nothing_moved([{"before": 1.15, "after": 1.15}, {"before": 1.0, "after": 0.95}]),
		"one moved row makes the whole decision a real apply")


# ---------------------------------------------------------------- the floor


func test_the_daemon_still_has_what_this_file_drives() -> void:
	var d = Daemon.new()
	for m in ["try_auto_apply", "force_apply", "request_llm_proposal", "format_for_review"]:
		assert_true(d.has_method(m), "RebalanceDaemon has no %s(), so the arms that drive it pass without running" % m)
	for f in ["pending", "applied"]:
		assert_true(f in d, "RebalanceDaemon has no %s, so this file's fixture is stale" % f)
	var consts: Dictionary = Daemon.get_script_constant_map()
	for c in ["APPLY_APPLIED", "APPLY_NO_CHANGE", "APPLY_NEEDS_REVIEW", "STATUS_AT_LIMIT",
			"SAFE_DELTA_MIN", "SAFE_DELTA_MAX"]:
		assert_true(consts.has(c), "RebalanceDaemon no longer declares %s" % c)
	assert_true(_gs() != null and "DEFAULT_GAME_CONSTANTS" in _gs(),
		"the clamp reads GameState.DEFAULT_GAME_CONSTANTS; without it every arm here measures a no-op path")
