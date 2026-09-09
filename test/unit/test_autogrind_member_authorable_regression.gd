extends GutTest

## Found by running cowir-controller's legend sweep BACKWARDS on my own feature: not "is what the
## console SAYS true" (I fixed that this morning) but "is everything the grammar ALLOWS actually
## authorable". It was not.
##
##   condition["member"]  0 writes anywhere in AutogrindUI
##   action["member"]     1 write — my seeding function, not player-reachable
##   action["ability"]    1 write — same
##
## So the FINE tier of everything I shipped in .239/.242 — the whole point, "if CLERIC is dead",
## "have CLERIC cast cure" — could only be authored through the LLM composer or by hand-editing
## JSON. The picker offered the TYPE and no route to the field that makes it fine rather than
## coarse. struktured asked for member-naming by name; in the editor it did not exist.

var _ui
var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_party.clear()
	for spec in ["cleric", "mage"]:
		var c := Combatant.new()
		c.initialize({
			"name": spec.capitalize(), "max_hp": 500, "max_mp": 40,
			"attack": 10, "defense": 10, "magic": 20, "speed": 10
		})
		c.job = {"id": spec}
		add_child_autofree(c)
		_party.append(c)
	_party[0].learned_abilities.append_array(["cure", "protect"])
	_ui._party = _party


func _put(cell: Dictionary, as_action: bool) -> void:
	## One rule, cursor parked on the cell under test. An "always" condition occupies a slot and
	## blocks the spare, so the first action sits at col 1.
	if as_action:
		_ui.rules = [{"conditions": [{"type": "always"}], "actions": [cell], "enabled": true}]
		_ui.cursor_col = 1
	else:
		_ui.rules = [{"conditions": [cell], "actions": [{"type": "stop_grinding"}], "enabled": true}]
		_ui.cursor_col = 0
	_ui.cursor_row = 0


func test_a_member_scoped_CONDITION_can_be_pointed_at_a_character() -> void:
	var cond := {"type": "member_dead"}
	_put(cond, false)
	_ui._cycle_member_on_cursor_cell()
	assert_ne(str(cond.get("member", "")), "",
		"cycling must set a member — this is the fine tier and it had no route at all")
	assert_true(["cleric", "mage"].has(str(cond["member"])),
		"and it must be a REAL party member, got '%s'" % str(cond.get("member", "")))


func test_the_condition_form_can_cycle_BACK_to_any() -> void:
	## The coarse tier must stay reachable: absent member IS the any-member rule, and a player who
	## cycles past the end must be able to get back to it rather than being stuck fine-grained.
	## Start FROM a named member, or a no-op cycle passes on the first iteration (member is already
	## "") and the arm is hollow — caught by reading it before mutating, not after.
	var cond := {"type": "member_dead", "member": "cleric"}
	_put(cond, false)
	var seen_any := false
	for _i in range(_party.size() + 2):
		_ui._cycle_member_on_cursor_cell()
		if str(cond.get("member", "")) == "":
			seen_any = true
			break
	assert_true(seen_any, "cycling must return to Any (the coarse form), not strand the rule")


func test_a_member_ability_ACTION_never_cycles_to_an_empty_member() -> void:
	## validate_rule REFUSES member_ability with no member, so offering "Any" here would let the
	## player cycle their own rule into an unsaveable state — the exact defect I fixed last hour,
	## reintroduced through a different door.
	var act := {"type": "member_ability", "member": "cleric", "ability": "cure"}
	_put(act, true)
	for _i in range(_party.size() + 2):
		_ui._cycle_member_on_cursor_cell()
		assert_ne(str(act.get("member", "")), "",
			"the action form must never land on an empty member")


func test_cycling_the_member_keeps_the_action_saveable() -> void:
	var act := {"type": "member_ability", "member": "cleric", "ability": "cure"}
	_put(act, true)
	_ui._cycle_member_on_cursor_cell()
	var errs: Array = _system.validate_rule({
		"conditions": [{"type": "always"}], "actions": [act]
	})
	assert_eq(errs.size(), 0, "after cycling the member the rule must still validate: %s" % str(errs))


func test_ability_cycling_only_offers_what_that_member_knows() -> void:
	## An ability the caster cannot cast saves fine and is refused BY NAME at runtime — debuggable,
	## but a picker should not hand the player a rule that cannot fire.
	var act := {"type": "member_ability", "member": "cleric", "ability": "cure"}
	_put(act, true)
	_ui._cycle_ability_on_cursor_cell()
	assert_true(["cure", "protect"].has(str(act.get("ability", ""))),
		"cycling must stay inside the cleric's known abilities, got '%s'" % str(act.get("ability", "")))


func test_the_ring_actually_offers_these_verbs() -> void:
	## The gap was never in the grammar or the executor — it was that no ROUTE existed. A helper
	## nothing calls is the same defect one layer over, so assert the ring rows themselves.
	var src: String = load("res://src/ui/autogrind/AutogrindUI.gd").source_code
	assert_true(src.contains('"id": "cycle_member"'), "the OPTIONS ring must offer Cycle Member")
	assert_true(src.contains('"id": "cycle_ability"'), "the OPTIONS ring must offer Cycle Ability")
	assert_true(src.contains('"cycle_member":'), "and the ring must DISPATCH it, not just list it")


func test_cycling_a_non_member_cell_does_nothing() -> void:
	# ARM+: the verbs must be inert where they do not apply, not corrupt an unrelated cell.
	var cond := {"type": "party_hp_avg", "op": "<", "value": 30}
	_put(cond, false)
	_ui._cycle_member_on_cursor_cell()
	assert_false(cond.has("member"), "a party-level condition must not gain a member field")
