extends GutTest

## I fixed this same bug twice in two hours, so this file fixes the CLASS instead of a third instance.
##
## Every session-scoped field on AutogrindSystem lives in three places, and the three must agree:
##   RESET    start_autogrind            -- a fresh grind must not inherit the last one's tally
##   SNAPSHOT build_snapshot_system_block-- resume continues the SAME grind, so it must survive a pause
##   RESTORE  restore_system_from_snapshot
## Miss the snapshot and the tally zeroes on RESUME (that was the meta-boss counters).
## Miss the reset and it LEAKS into the next grind (that was the rule-fire counts).
## Both halves are needed because resume is `_start_autogrind(config)` THEN restore
## (GameLoop:6579-6582): start clears, restore puts back only what the snapshot carried.
##
## Censusing all three sets at once found three more that were already shipped:
##   consecutive_wins  leaked -- and win_streak is a live RULE CONDITION, so an authored
##                     `win_streak >= 10 -> stop` could fire on battle 1 of a brand-new grind
##   collapse_count    leaked -- the dashboard's win_rate divides a SESSION numerator
##                     (battles_completed, reset here) by a LIFETIME denominator, so after three
##                     lifetime collapses a fresh grind's first battle reads 25%
##   _injury_baseline  was absent from the snapshot, so start_autogrind re-baselined against the
##                     already-injured party on resume, absorbing every pre-pause injury
##
## The last one is why persisting the derived count would NOT have worked: check_new_injuries()
## recomputes injuries_this_session from the baseline on the very next battle, so a restored
## count is overwritten one battle later and the test that checked it passes anyway.
##
## The first test below is the ratchet: it derives the three sets from the SOURCE, so the next
## field added to one and not the others fails here by name, without anyone remembering to look.

const SRC := "res://src/autogrind/AutogrindSystem.gd"

## Asymmetric BY DESIGN. The value is the reason, and the ratchet requires it to be non-empty --
## you cannot silence an entry green, only explain it green. It also fails on a STALE entry, so
## a field that later becomes symmetric must be removed from here.
const CLASSIFIED := {
	"is_grinding": "lifecycle flag, not a tally; a snapshot only exists while it is true",
	"grind_party": "restored by the resume path from the live party, not from the system block",
	"grind_enemy_template": "restored by the resume path alongside grind_party",
	"_automation_paused": "resuming a grind means you want it running; a paused resume is a wedge",
	"injuries_this_session": "DERIVED from _injury_baseline by check_new_injuries; the baseline is the persisted half",
	"current_region_id": "a place, not a tally; you grind the same region across sessions by design",
	"efficiency_growth_rate": "DERIVED from permadeath_staking_enabled, which IS snapshotted; restoring the flag through enable_permadeath_staking re-derives the rate",
	"_ability_learned_conns": "signal bookkeeping rebuilt from the live party; Callables cannot round-trip JSON",
	"_rare_drop_conn": "signal bookkeeping rebuilt from the live BattleManager; a Callable, not state",
}

var _ags: Node = null


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true


func after_each() -> void:
	if _ags:
		_ags.is_grinding = false


# ── source census ────────────────────────────────────────────────────────────

func _lines() -> PackedStringArray:
	var f := FileAccess.open(SRC, FileAccess.READ)
	assert_not_null(f, "AutogrindSystem.gd must be readable at %s" % SRC)
	if f == null:
		return PackedStringArray()
	return f.get_as_text().split("\n")


func _body(lines: PackedStringArray, fname: String) -> PackedStringArray:
	var out := PackedStringArray()
	var inside := false
	for l in lines:
		if l.begins_with("func " + fname + "("):
			inside = true
			continue
		if inside:
			if l.begins_with("func "):
				break
			out.append(l)
	return out


## Fields assigned (or cleared) at any indent inside a body.
func _assigned(body: PackedStringArray) -> Dictionary:
	var re := RegEx.create_from_string("^\\t+(_?[a-z][a-z0-9_]*)\\s*(=[^=]|\\.clear\\(\\))")
	var out := {}
	for l in body:
		var m := re.search(l)
		if m:
			out[m.get_string(1)] = true
	return out


## Zero-or-one-arg helper calls, so a reset or restore done through a setter still counts.
func _called_helpers(body: PackedStringArray) -> PackedStringArray:
	var re := RegEx.create_from_string("^\\t+([a-z_]+)\\(")
	var out := PackedStringArray()
	for l in body:
		var m := re.search(l)
		if m and not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


func _resolve(lines: PackedStringArray, fname: String) -> Dictionary:
	var fields := _assigned(_body(lines, fname))
	for h in _called_helpers(_body(lines, fname)):
		for k in _assigned(_body(lines, h)):
			fields[k] = true
	return fields


func _snapshot_fields(lines: PackedStringArray) -> Dictionary:
	var re := RegEx.create_from_string("^\\t\\t\"[a-z_]+\":\\s*(_?[a-z][a-z0-9_]*)")
	var out := {}
	for l in _body(lines, "build_snapshot_system_block"):
		var m := re.search(l)
		if m and m.get_string(1) != "elapsed":
			out[m.get_string(1)] = true
	return out


func test_every_session_field_is_reset_snapshotted_and_restored() -> void:
	var lines := _lines()
	assert_gt(lines.size(), 100, "census must read a real file, not an empty one")

	var reset := _resolve(lines, "start_autogrind")
	var snap := _snapshot_fields(lines)
	var restore := _resolve(lines, "restore_system_from_snapshot")

	# The census must actually find things, or every assert below is vacuously green.
	assert_gt(reset.size(), 10, "start_autogrind must yield a non-trivial reset set")
	assert_gt(snap.size(), 10, "build_snapshot_system_block must yield a non-trivial field set")
	assert_gt(restore.size(), 10, "restore_system_from_snapshot must yield a non-trivial field set")
	assert_true(reset.has("battles_completed"), "control: a known session tally must appear in the reset set")
	assert_true(snap.has("battles_completed"), "control: a known session tally must appear in the snapshot set")

	var unclassified := []
	for f in reset.keys():
		if not snap.has(f) and not CLASSIFIED.has(f):
			unclassified.append("%s is RESET but not SNAPSHOTTED -> it zeroes on resume" % f)
	for f in snap.keys():
		if not reset.has(f) and not CLASSIFIED.has(f):
			unclassified.append("%s is SNAPSHOTTED but not RESET -> it leaks into the next grind" % f)
		if not restore.has(f) and not CLASSIFIED.has(f):
			unclassified.append("%s is WRITTEN to the snapshot but never READ back" % f)
	assert_eq(unclassified.size(), 0,
		"session-scope asymmetry -- fix it, or add the field to CLASSIFIED with a reason:\n  %s"
		% "\n  ".join(unclassified))


func test_no_stale_classified_entries() -> void:
	var lines := _lines()
	var reset := _resolve(lines, "start_autogrind")
	var snap := _snapshot_fields(lines)
	var restore := _resolve(lines, "restore_system_from_snapshot")

	var stale := []
	var reasonless := []
	for f in CLASSIFIED.keys():
		if str(CLASSIFIED[f]).strip_edges().is_empty():
			reasonless.append(f)
		var symmetric: bool = reset.has(f) and snap.has(f) and restore.has(f)
		if symmetric:
			stale.append(f)
		if not reset.has(f) and not snap.has(f) and not restore.has(f):
			stale.append("%s (absent from all three -- renamed or deleted?)" % f)
	assert_eq(reasonless, [], "a CLASSIFIED entry with an empty reason is a suppression, not an explanation")
	assert_eq(stale, [], "CLASSIFIED entry is no longer asymmetric -- remove it so the ratchet keeps its teeth")


# ── behaviour ────────────────────────────────────────────────────────────────

func _party() -> Array:
	var p: Array[Combatant] = []
	var c := Combatant.new()
	c.initialize({"name": "Scope Probe", "max_hp": 400, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	p.append(c)
	return p


func test_a_fresh_grind_does_not_inherit_the_last_grinds_streak_or_collapses() -> void:
	if _ags == null:
		pass_test("AutogrindSystem autoload unavailable")
		return
	_ags.is_grinding = false
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10})
	_ags.consecutive_wins = 7
	_ags.collapse_count = 3
	_ags.stop_autogrind()

	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10})
	assert_eq(_ags.consecutive_wins, 0, "a new grind starts with no win streak -- win_streak is a rule condition")
	assert_eq(_ags.collapse_count, 0, "a new grind starts with no collapses -- win_rate divides by this")


func test_resume_keeps_the_streak_and_collapses_the_pause_interrupted() -> void:
	if _ags == null:
		pass_test("AutogrindSystem autoload unavailable")
		return
	_ags.is_grinding = false
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10})
	_ags.consecutive_wins = 7
	_ags.collapse_count = 3
	var block: Dictionary = _ags.build_snapshot_system_block(12.0)
	_ags.stop_autogrind()

	# Through REAL JSON -- resume reads a file, not a dict in memory.
	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(block))
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10})
	assert_eq(_ags.consecutive_wins, 0, "precondition: start must have cleared the streak first")
	_ags.restore_system_from_snapshot(round_tripped)
	assert_eq(_ags.consecutive_wins, 7, "resume continues the same grind, so the streak survives the pause")
	assert_eq(_ags.collapse_count, 3, "resume continues the same grind, so the collapse tally survives")


func test_resume_does_not_absorb_injuries_sustained_before_the_pause() -> void:
	if _ags == null:
		pass_test("AutogrindSystem autoload unavailable")
		return
	_ags.is_grinding = false
	var party := _party()
	_ags.start_autogrind(party, {"name": "slime", "max_hp": 10})
	assert_eq(_ags._injury_baseline, 0, "precondition: an uninjured party baselines at 0")

	party[0].permanent_injuries.append({"type": "cracked_rib", "severity": 1})
	assert_eq(_ags.check_new_injuries(), 1, "precondition: the injury registers before the pause")
	var block: Dictionary = _ags.build_snapshot_system_block(5.0)
	_ags.stop_autogrind()

	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(block))
	# Resume re-enters with the SAME, still-injured party -- that is what re-baselined it to zero.
	_ags.start_autogrind(party, {"name": "slime", "max_hp": 10})
	assert_eq(_ags._injury_baseline, 1, "precondition: start re-baselines against the injured party")
	_ags.restore_system_from_snapshot(round_tripped)
	assert_eq(_ags._injury_baseline, 0, "the snapshot carries the ORIGINAL baseline, not the post-injury one")
	assert_eq(_ags.check_new_injuries(), 1,
		"the pre-pause injury is still this session's -- member_injured must stay true across a resume")


func test_restoring_permadeath_staking_restores_its_growth_rate_too() -> void:
	if _ags == null:
		pass_test("AutogrindSystem autoload unavailable")
		return
	_ags.is_grinding = false
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10}, {"permadeath_staking": true})
	assert_eq(_ags.efficiency_growth_rate, 0.15, "precondition: staking raises the growth rate")
	var block: Dictionary = _ags.build_snapshot_system_block(3.0)
	_ags.stop_autogrind()

	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(block))
	# Resume WITHOUT the config -- this is the seam where the flag and the rate disagreed.
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10}, {"permadeath_staking": false})
	assert_eq(_ags.efficiency_growth_rate, 0.1,
		"THE LEAK: turning staking off must lower the rate too, or it is the bonus without the risk")
	_ags.restore_system_from_snapshot(round_tripped)
	assert_true(_ags.permadeath_staking_enabled, "the staking flag survives the pause")
	assert_eq(_ags.efficiency_growth_rate, 0.15,
		"the rate is derived from the flag -- restoring one without the other pays the base rate while staking")


func test_resume_remembers_what_the_smart_interrupt_rules_were_waiting_for() -> void:
	if _ags == null:
		pass_test("AutogrindSystem autoload unavailable")
		return
	_ags.is_grinding = false
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10})
	assert_false(_ags._ability_learned_this_session, "precondition: a fresh grind has learned nothing")
	_ags._on_smart_interrupt_ability_learned("fire")
	_ags._on_smart_interrupt_rare_drop("elixir", 0.01)
	var block: Dictionary = _ags.build_snapshot_system_block(4.0)
	_ags.stop_autogrind()

	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(block))
	_ags.start_autogrind(_party(), {"name": "slime", "max_hp": 10})
	assert_false(_ags._ability_learned_this_session, "precondition: start clears it, so restore is what puts it back")
	_ags.restore_system_from_snapshot(round_tripped)
	assert_true(_ags._ability_learned_this_session,
		"ability_learned is a rule condition -- a pause must not retract what already happened")
	assert_true(_ags._rare_drop_this_session, "rare_item_found is a rule condition and pairs with it")
