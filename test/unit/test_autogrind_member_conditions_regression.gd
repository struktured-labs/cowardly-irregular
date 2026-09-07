extends GutTest

## struktured 2026-09-06 (relayed by cowir-main): "if cleric is dead, stop grinding. if mage is
## dead, have cleric [use] restorative." The vocabulary had member_dead/member_injured but both
## were PARTY-WIDE aggregates — member_dead discarded op/value and answered "is anyone dead",
## so no rule could name a character. These are the member-scoped predicates.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", 100], ["mage", 80], ["fighter", 120]]:
		var c := Combatant.new()
		c.initialize({
			"name": str(spec[0]).capitalize(), "max_hp": int(spec[1]), "max_mp": 40,
			"attack": 10, "defense": 10, "magic": 10, "speed": 10
		})
		c.job = {"id": str(spec[0])}
		add_child_autofree(c)
		_party.append(c)


func _cond(d: Dictionary) -> bool:
	return _system._evaluate_party_condition(_party, d)


func _member(job_id: String) -> Combatant:
	return _system._resolve_member(_party, job_id)


func test_resolve_finds_a_member_by_job_id() -> void:
	var m := _member("cleric")
	assert_not_null(m, "job id must resolve — this is how struktured phrases rules")
	assert_eq(str(m.job.id), "cleric", "must resolve the CLERIC, not merely some member")


func test_resolve_is_case_insensitive_and_falls_back_to_name() -> void:
	assert_not_null(_member("CLERIC"), "job id match must be case-insensitive")
	assert_not_null(_member("Fighter"), "the character name is the documented fallback")


func test_resolve_returns_null_for_an_absent_member() -> void:
	# ARM+: without this, every predicate below could be passing on a resolver that
	# returns the first party member for any input.
	assert_null(_member("bard"), "a job not in the party must not resolve")
	assert_null(_member(""), "an empty member key must not resolve")


func test_member_dead_scoped_to_one_character() -> void:
	_party[0].is_alive = false  # cleric down, others up
	assert_true(_cond({"type": "member_dead", "member": "cleric"}),
		"'if cleric is dead' must be true when the cleric is the one down")
	assert_false(_cond({"type": "member_dead", "member": "mage"}),
		"...and false for a member who is still standing")


func test_member_dead_without_a_member_keeps_the_old_any_member_meaning() -> void:
	# BACKWARD COMPATIBILITY. Every rule authored before this change omits "member";
	# if the scoped path captured them, existing interrupt rules would change meaning silently.
	assert_false(_cond({"type": "member_dead"}), "nobody down — the unscoped form stays false")
	_party[1].is_alive = false
	assert_true(_cond({"type": "member_dead"}), "any member down — the unscoped form stays true")


func test_member_hp_compares_that_members_percentage() -> void:
	_party[1].current_hp = 20  # mage at 25% of 80
	assert_true(_cond({"type": "member_hp", "member": "mage", "op": "<", "value": 30}),
		"the mage is at 25% and must satisfy < 30")
	assert_false(_cond({"type": "member_hp", "member": "cleric", "op": "<", "value": 30}),
		"the cleric is untouched and must NOT satisfy it — the predicate must read the NAMED member")


func test_member_status_reads_the_named_member() -> void:
	_party[0].add_status("poison")
	assert_true(_cond({"type": "member_status", "member": "cleric", "value": "poison"}),
		"the cleric is poisoned")
	assert_false(_cond({"type": "member_status", "member": "mage", "value": "poison"}),
		"the mage is not — status must not leak across members")


func test_an_unresolvable_member_is_false_never_a_crash() -> void:
	assert_false(_cond({"type": "member_hp", "member": "bard", "op": "<", "value": 99}),
		"a member who left the party must evaluate false, not abort the rule sweep")


func test_validator_rejects_a_member_scoped_condition_with_no_member() -> void:
	var errs: Array = _system.validate_rule({
		"conditions": [{"type": "member_hp", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}]
	})
	assert_gt(errs.size(), 0,
		"a member-scoped condition with no member would evaluate false forever — that is a typo, not a rule")


func test_validator_still_accepts_unscoped_member_dead() -> void:
	# ARM+ for the rejection above: proves the check is scoped and did not break the legacy form.
	var errs: Array = _system.validate_rule({
		"conditions": [{"type": "member_dead"}],
		"actions": [{"type": "stop_grinding"}]
	})
	assert_eq(errs.size(), 0, "the pre-existing any-member form must still validate")


func test_the_new_types_are_in_the_grammar() -> void:
	# The LLM Rule Composer and the editor's picker both enumerate this dict; a type that
	# evaluates but is absent here is unauthorable.
	for t in ["member_hp", "member_mp", "member_status"]:
		assert_true(_system.PARTY_CONDITION_TYPES.has(t),
			"%s must be in PARTY_CONDITION_TYPES or no editor or composer can offer it" % t)
