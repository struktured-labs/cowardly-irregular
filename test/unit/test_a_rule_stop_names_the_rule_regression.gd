extends GutTest
## A grind stopped by the player's OWN rule said "Autogrind rule triggered stop" -- true, and it
## named neither which rule nor anything the player could go and look at. The interrupt stops learned
## to say what to change in .672; this is the sibling path, and it is the one a player hits after
## authoring a stop_grinding rule and forgetting it. Rules carry no name field, so the ROW NUMBER is
## the handle: it is what the rule editor shows, so "#3" leads back to the rule that did it.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	## OWN THE PRECONDITION. start_autogrind REFUSES a double-start, so a predecessor file that
	## leaked is_grinding would red this file's FLOOR and read as a defect in the change under test.
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("inherited session cleared by this fixture")


func after_each() -> void:
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindState.restore(_ag)


func _reason() -> String:
	if not AutogrindSystem.has_method("stop_rule_reason"):
		return ""
	return str(AutogrindSystem.stop_rule_reason())


func _assert_reason_fn_exists() -> void:
	assert_true(AutogrindSystem.has_method("stop_rule_reason"),
		"FLOOR: AutogrindSystem.stop_rule_reason must exist, or every arm below passes by absence")


func _assert_index_field_exists() -> void:
	assert_true("last_fired_rule_index" in AutogrindSystem,
		"FLOOR: AutogrindSystem.last_fired_rule_index must exist, or touching it aborts this arm into Risky")


func _party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for n in ["Rook", "Vesper"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": n, "max_hp": 100, "max_mp": 10})
		out.append(c)
	return out


## Three rows, the THIRD one matching -- so a reason naming "#1" or an off-by-one reads as a pass
## against a single-rule fixture and cannot here.
func _author_rules_where_the_third_fires() -> void:
	AutogrindSystem.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "alive_count", "op": "<", "value": 1}], "actions": [{"type": "stop_grinding"}]},
		{"enabled": true, "conditions": [{"type": "battles_done", "op": ">", "value": 9999}], "actions": [{"type": "stop_grinding"}]},
		{"enabled": true, "conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}]},
	])


func test_the_stop_reason_names_the_row_that_fired() -> void:
	_assert_reason_fn_exists()
	_author_rules_where_the_third_fires()
	var matched: Dictionary = AutogrindSystem.evaluate_autogrind_rules(_party())
	assert_false(matched.is_empty(), "FLOOR: the third rule must actually match, or this measures nothing")
	assert_eq(int(AutogrindSystem.last_fired_rule_index), 2, "FLOOR: the third row is index 2")
	assert_true(_reason().contains("#3"),
		"the stop must name the row the player can open, not just say a rule did it: %s" % _reason())


## CONTROL: a stop with no rule behind it must not invent a row. Index -1 is the no-rule state.
func test_a_stop_with_no_rule_behind_it_names_no_row() -> void:
	_assert_reason_fn_exists()
	_assert_index_field_exists()
	if not ("last_fired_rule_index" in AutogrindSystem):
		return
	AutogrindSystem.last_fired_rule_index = -1
	var r: String = _reason()
	assert_false(r.contains("#"), "CONTROL: with no rule fired, no row may be named: %s" % r)
	assert_ne(r, "", "and it must still say something rather than go blank")


## CONTROL: a pass over rules where NOTHING matches must clear the row, or the next rule-stop
## reports whichever rule fired last time.
func test_a_pass_that_matches_nothing_clears_the_row() -> void:
	_assert_index_field_exists()
	if not ("last_fired_rule_index" in AutogrindSystem):
		return
	AutogrindSystem.last_fired_rule_index = 2
	AutogrindSystem.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "battles_done", "op": ">", "value": 9999}], "actions": [{"type": "stop_grinding"}]},
	])
	var matched: Dictionary = AutogrindSystem.evaluate_autogrind_rules(_party())
	assert_true(matched.is_empty(), "FLOOR: nothing may match this fixture")
	assert_eq(int(AutogrindSystem.last_fired_rule_index), -1,
		"CONTROL: a non-matching pass must clear the row, or a later stop names a rule that did not fire")


## THE ARM THAT REACHES THE PLAYER: the reason the ACTION produces is the one that travels to the
## Summary, which is the surface a stop always reaches. Driving stop_rule_reason() alone would prove
## the sentence exists and not that stop_grinding uses it.
func test_the_rule_action_stops_with_the_naming_reason() -> void:
	_assert_reason_fn_exists()
	_author_rules_where_the_third_fires()
	## START FIRST, then evaluate -- the order the controller uses. start_autogrind clears the row,
	## and rules are evaluated BETWEEN battles, so evaluating before the start tested a sequence the
	## game never runs and went red the moment the reset landed.
	var started: bool = AutogrindSystem.start_autogrind(_party(), {"id": "slime", "name": "Slime", "max_hp": 30})
	assert_true(started, "FLOOR: a grind must be running for a stop to report anything")
	AutogrindSystem.evaluate_autogrind_rules(_party())
	assert_eq(int(AutogrindSystem.last_fired_rule_index), 2, "FLOOR: the third row must have matched after the start")
	watch_signals(AutogrindSystem)
	AutogrindSystem.apply_autogrind_actions([{"type": "stop_grinding"}])
	assert_signal_emitted(AutogrindSystem, "grind_stopped", "the stop_grinding action must actually stop the grind")
	var params = get_signal_parameters(AutogrindSystem, "grind_stopped", 0)
	assert_not_null(params, "FLOOR: the stop must carry its results")
	if params == null:
		return
	var reason: String = str((params[0] as Dictionary).get("stop_reason", ""))
	assert_true(reason.contains("#3"),
		"the reason that travels to the Summary must name the row: %s" % reason)


## A NEW grind must not inherit the previous session's row -- the same leak the interrupt rule had.
## Without the reset in start_autogrind this field sits in ZERO of reset/snapshot/restore, which
## test_autogrind_session_scope_symmetry_regression documents as its own blind spot: a zero-set field
## is never iterated there, so it would have folded green rather than red.
func test_a_new_grind_does_not_inherit_the_previous_rows() -> void:
	_assert_index_field_exists()
	if not ("last_fired_rule_index" in AutogrindSystem):
		return
	AutogrindSystem.last_fired_rule_index = 2
	var started: bool = AutogrindSystem.start_autogrind(_party(), {"id": "slime", "name": "Slime", "max_hp": 30})
	assert_true(started, "FLOOR: the fixture must actually start a grind")
	assert_eq(int(AutogrindSystem.last_fired_rule_index), -1,
		"a new session must not inherit the row that stopped the previous one")
