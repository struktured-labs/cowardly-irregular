extends GutTest

## Two bugs in one mechanism, and the second only exists because I fixed the first badly.
##
## The rule-fire counters reset ONLY on a rule edit. So:
##   fresh grind, rules unchanged   -> inherited the PREVIOUS grind's counts
##   the Summary's "Your Rules" row -> reported last session's answer as this session's
##
## Fixing that with a reset in start_autogrind alone would break RESUME, because resume is
## `_start_autogrind(config)` followed by `restore_system_from_snapshot(...)` (GameLoop:6579-6582) —
## start resets, restore puts back only what the snapshot carries. A counter not in the snapshot
## resets on resume. That is exactly how the meta-boss counters broke, one change earlier.
##
## So both halves are required and they are not independent: reset on start, restore on resume.
##
## ⚠️ AND THE RESTORE HAS A TRAP. A snapshot round-trips through JSON, which has STRING keys only.
## {0: 4} comes back as {"0": 4}, so every `fired.get(i, 0)` with an int i misses and the counts
## read as ZERO while rule_eval_count restores correctly — producing "0 of 5 fired (214 checks)",
## the exact string that means "your rules are broken". The keys are coerced back to int on restore
## and this file round-trips through real JSON to prove it.

var _ags: Node = null


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
		_ags.reset_rule_fire_counts()


func after_each() -> void:
	if _ags:
		_ags.reset_rule_fire_counts()
		_ags.is_grinding = false


func _party() -> Array:
	var p: Array[Combatant] = []
	var c := Combatant.new()
	c.initialize({"name": "Resume Probe", "max_hp": 400, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	p.append(c)
	return p


func test_a_fresh_grind_does_not_inherit_the_last_one_s_counts() -> void:
	_ags._rule_fire_counts = {0: 7, 1: 3}
	_ags._rule_eval_count = 214
	_ags.is_grinding = false
	assert_true(_ags.start_autogrind(_party(), {}, {}), "precondition: a new grind started")

	assert_eq(_ags.get_rule_eval_count(), 0,
		"a fresh grind must start from zero — otherwise the Summary reports the PREVIOUS session's numbers as this one's")
	assert_eq(_ags.get_rule_fire_counts().size(), 0, "per-rule counts too")


func test_the_counts_survive_a_snapshot_round_trip_THROUGH_JSON() -> void:
	## Round-tripped through real JSON, not a dict copy, because JSON is where the int keys die.
	_ags._rule_fire_counts = {0: 7, 2: 1}
	_ags._rule_eval_count = 214
	var block: Dictionary = _ags.build_snapshot_system_block()
	var revived: Dictionary = JSON.parse_string(JSON.stringify(block))
	assert_true(revived.has("rule_fire_counts"), "precondition: the writer carries the counts")
	assert_true(revived["rule_fire_counts"].has("0"),
		"precondition: JSON really did turn the int key into a STRING — if not, this test is not testing the trap")

	_ags.reset_rule_fire_counts()
	_ags.restore_system_from_snapshot(revived)

	assert_eq(_ags.get_rule_eval_count(), 214, "the denominator survives")
	var counts: Dictionary = _ags.get_rule_fire_counts()
	assert_eq(int(counts.get(0, -1)), 7,
		"rule 0's count must be readable by INT key after a JSON round trip — a string key here reads as 0 and the Summary says the rules never fired")
	assert_eq(int(counts.get(2, -1)), 1, "and rule 2's")


func test_an_old_snapshot_restores_empty_rather_than_erroring() -> void:
	## Backward compatibility: snapshots written before this change have no such keys.
	_ags._rule_fire_counts = {0: 5}
	_ags._rule_eval_count = 99
	_ags.restore_system_from_snapshot({"collapse_count": 2})
	assert_eq(_ags.get_rule_eval_count(), 0, "an old snapshot restores zero, not stale memory")
	assert_eq(_ags.get_rule_fire_counts().size(), 0, "and no per-rule counts")


func test_reset_on_start_and_restore_on_resume_are_BOTH_required() -> void:
	## The pairing, stated as a test so neither half can be removed as redundant: resume is start
	## THEN restore, so a reset without a restore loses the tally a resumed session should keep.
	_ags._rule_fire_counts = {1: 4}
	_ags._rule_eval_count = 50
	var block: Dictionary = _ags.build_snapshot_system_block()
	_ags.is_grinding = false
	_ags.start_autogrind(_party(), {}, {})
	assert_eq(_ags.get_rule_eval_count(), 0, "start cleared it, as a fresh grind requires")
	_ags.restore_system_from_snapshot(block)
	assert_eq(_ags.get_rule_eval_count(), 50, "and restore put the resumed session's tally back")
