extends GutTest

const Ed := preload("res://src/ui/autogrind/AutogrindGridEditor.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const EDITOR_SRC := "res://src/ui/autogrind/AutogrindGridEditor.gd"

## ⛔ THE VALUE DIAL THREW ON EVERY PRESS OVER A "Member Has Status" CONDITION.
## `member_status` is the lane's one NAMED_VALUE_CONDITION — its payload is a status id
## ("poison"), not a number — and `_adjust_condition_value` did
## `clamp(current_value + delta * step, ...)` unconditionally. Measured:
##
##   before dial: value=poison (String)
##   after  dial: value=poison (String)
##   SCRIPT ERROR: Invalid operands 'String' and 'int' in operator '+'.   (one per press)
##
## The error ABORTS the function, so the write and `_refresh_grid()` below it never ran either.
## The player sees a dial that does nothing; the log fills with type errors.
##
## 🔑 TWO HALVES, AND ONLY ONE IS A BUG. That the status CANNOT BE CHANGED is a missing picker —
## @cowir-ai measured the same shape in the autobattle twin (8 conditions stuck on their seed) and
## routed it to struktured as a scope call, because adding one is a feature. That every press raises
## a TYPE ERROR is not a scope call at all. This fixes the second and leaves the first declared.
##
## ⚠️ THE SYMPTOM THIS CANNOT ASSERT ON: GUT exposes no `assert_no_script_errors` to GDScript
## (`test_quest_examine_point_bounds_regression` documents the same limit; `tools/gate.sh` counts
## them). An abort and a clean skip are indistinguishable from the caller — both leave the value
## untouched and both skip the refresh. So the arm that detects the GUARD is the source one, and the
## behavioural arms pin the CONTRACT. Recorded so nobody reads their green as proof the guard exists.


## ⛔ GATED AND RESTORED. This file instantiates the grid editor, and a UI node reaches an autogrind
## SAVER three calls down — my own test_autogrind_tests_never_write_player_data caught this file on
## its first lane run. snapshot_and_isolate sets _test_disable_persistence AND captures the whole
## autoload surface, so this guard cannot write the player's profiles or leak state to a later file.
var _ag_state: Dictionary


func before_each() -> void:
	_ag_state = AutogrindState.snapshot_and_isolate()


func after_each() -> void:
	AutogrindState.restore(_ag_state)


func _editor() -> Node:
	var ed = Ed.new()
	add_child_autofree(ed)
	return ed


func _rule(ctype: String, value) -> Dictionary:
	return {"conditions": [{"type": ctype, "op": "==", "value": value}], "actions": [{"type": "attack"}]}


## CONTROL: the subject must still exist, or every arm below is about a condition nobody can author.
func test_the_grammar_still_carries_a_named_value_condition() -> void:
	assert_true("member_status" in AutogrindSystem.NAMED_VALUE_CONDITIONS,
		"member_status is no longer a named-value condition — this file is about a payload that is a status id, not a number")
	var defaults: Dictionary = AutogrindSystem.CONDITION_DEFAULTS if "CONDITION_DEFAULTS" in AutogrindSystem else {}
	if defaults.has("member_status"):
		assert_true(str((defaults["member_status"] as Dictionary).get("value", "")) != "",
			"CONTROL: member_status must still seed a non-empty status id")


## ⛔ THE GUARD ITSELF. Source-level, because an abort and a clean skip look identical from outside.
func test_the_dial_refuses_a_non_numeric_value_before_the_arithmetic() -> void:
	var src: String = GdSource.code_of(EDITOR_SRC)
	var at: int = src.find("func _adjust_condition_value(")
	assert_gt(at, -1, "CONTROL: the dial must exist")
	var stop: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (stop - at) if stop > at else -1)

	var guard_at: int = body.find("current_value is int or current_value is float")
	var math_at: int = body.find("current_value + delta")
	assert_gt(math_at, -1, "CONTROL: the arithmetic this guard protects must still be here")
	assert_gt(guard_at, -1,
		"the value dial does no type check before `current_value + delta * step` — a member_status " +
		"condition carries a status id, so every press raises \"Invalid operands 'String' and 'int'\" " +
		"and aborts before the write and the refresh")
	assert_lt(guard_at, math_at,
		"the type check must come BEFORE the arithmetic, or the throw happens first and the guard is decoration")


## The contract: a status condition's payload survives the dial in both directions.
func test_dialling_a_status_condition_leaves_its_status_intact() -> void:
	var ed := _editor()
	ed.rules = [_rule("member_status", "poison")]
	ed.cursor_row = 0
	ed.cursor_col = 0
	ed._adjust_condition_value(1)
	ed._adjust_condition_value(-1)
	var got = ed.rules[0]["conditions"][0]["value"]
	gut.p("    after up+down: value=%s (%s)" % [str(got), type_string(typeof(got))])
	assert_eq(str(got), "poison",
		"the dial replaced a status id with something else — a condition referencing no real status never fires")
	assert_true(got is String, "the payload must stay a status id, not become a number")


## CONTROL: the dial must still work on the numeric conditions it is for.
func test_the_dial_still_moves_a_numeric_condition() -> void:
	var ed := _editor()
	ed.rules = [_rule("corruption", 3)]
	ed.cursor_row = 0
	ed.cursor_col = 0
	ed._adjust_condition_value(1)
	var got = ed.rules[0]["conditions"][0]["value"]
	gut.p("    numeric dial: 3 -> %s" % str(got))
	assert_ne(str(got), "3",
		"CONTROL: the dial no longer moves a numeric condition — the fix over-reached and disabled the feature")


## ⛔ THE DIAL HAND-LISTS 3 OF THE GRAMMAR'S 5 NULLARY CONDITIONS.
## NULLARY_CONDITIONS is ["member_dead", "member_injured", "ability_learned", "rare_item_found",
## "always"]; the early return names only the last three. So dialling on Member Dead or Member
## Injured moves a `value` NOTHING READS — member_injured returns `check_new_injuries() > 0` and
## member_dead goes through _member_predicate, which reads `member` and never `value`.
## @cowir-ai measured the same thing in the autobattle twin ("the dial edits a number nothing
## reads") and fixed it there; this is the autogrind half, and the cause is a hand-list beside a
## set the grammar already owns.
func test_dialling_a_nullary_condition_changes_nothing() -> void:
	for ctype in ["member_dead", "member_injured"]:
		var ed := _editor()
		ed.rules = [_rule(ctype, 0)]
		ed.cursor_row = 0
		ed.cursor_col = 0
		ed._adjust_condition_value(1)
		var got = ed.rules[0]["conditions"][0]["value"]
		gut.p("    %s after dial: value=%s" % [ctype, str(got)])
		assert_eq(str(got), "0",
			"%s is a NULLARY condition — its evaluator never reads `value`, so the dial moved a number that decides nothing and the player sees the cell change with no effect" % ctype)


## The guard must DERIVE the nullary set, so a sixth one is covered the day the grammar gains it.
func test_the_dial_derives_its_nullary_set_from_the_grammar() -> void:
	var src: String = GdSource.code_of(EDITOR_SRC)
	var at: int = src.find("func _adjust_condition_value(")
	var stop: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (stop - at) if stop > at else -1)
	assert_true(body.contains("NULLARY_CONDITIONS"),
		"the dial hand-lists which conditions have no value instead of asking the grammar — " +
		"NULLARY_CONDITIONS already owns that set, and a hand-list beside it covered 3 of 5")
	assert_gte(AutogrindSystem.NULLARY_CONDITIONS.size(), 5,
		"CONTROL: the grammar must still declare the nullary set this guard defers to")
