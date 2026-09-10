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
	## This asserted _member("Fighter") and passed via the JOB branch — "fighter" is a job id in
	## this fixture, so the name fallback was never exercised and was DEAD (it compared Node.name,
	## not combatant_name). Give one member a name that is not any job id, or the arm is hollow.
	assert_not_null(_member("CLERIC"), "job id match must be case-insensitive")
	_party[2].combatant_name = "Bram"
	assert_not_null(_member("Bram"), "the character name is the documented fallback")
	assert_not_null(_member("bram"), "and it must be case-insensitive too")


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


func test_the_table_minimal_shape_validates_for_every_member_type() -> void:
	## The picker and the LLM composer build a rule from the type table alone, with NO member.
	## An earlier draft REQUIRED member and this is the ratchet that caught it (fleet gate,
	## 2026-09-06): a type that its own table cannot construct is unauthorable.
	## 2026-09-10: the minimal shape is PER TYPE. This loop gave every type a numeric 30, which
	## asserted that member_status carrying a NUMBER was a valid rule — and that is exactly the
	## rule the console shipped, permanently false because the evaluator reads the status NAME
	## from `value`. The payload validator caught this test encoding the bug.
	var minimal := {
		"member_hp": {"op": "<", "value": 30},
		"member_mp": {"op": "<", "value": 30},
		"member_status": {"value": "poison"},
		"member_dead": {},
	}
	for t in minimal.keys():
		var cond: Dictionary = {"type": t}
		cond.merge(minimal[t])
		var errs: Array = _system.validate_rule({
			"conditions": [cond],
			"actions": [{"type": "stop_grinding"}]
		})
		assert_eq(errs.size(), 0,
			"the minimal shape of '%s' must validate — got %s" % [t, str(errs)])


func test_the_coarse_tier_asks_the_predicate_of_any_member() -> void:
	# No "member" => ANY member satisfies, mirroring member_dead's unscoped form.
	_party[1].current_hp = 20  # mage at 25% of 80; cleric and fighter untouched
	assert_true(_cond({"type": "member_hp", "op": "<", "value": 30}),
		"one member below 30% must satisfy the unscoped form")


func test_the_coarse_tier_is_false_when_no_member_satisfies() -> void:
	# ARM+ for the above: without it, an unconditional `true` would pass that test.
	assert_false(_cond({"type": "member_hp", "op": "<", "value": 30}),
		"a full-health party must NOT satisfy the unscoped form")


func test_coarse_and_fine_disagree_when_the_named_member_is_the_healthy_one() -> void:
	## The whole point of the split: same op/value, different answer. If these ever agree the
	## "member" key is being ignored and every fine rule silently became a coarse one.
	_party[1].current_hp = 20  # only the mage is hurt
	assert_true(_cond({"type": "member_hp", "op": "<", "value": 30}),
		"coarse: someone is hurt")
	assert_false(_cond({"type": "member_hp", "member": "cleric", "op": "<", "value": 30}),
		"fine: the CLERIC is not — the member key must change the answer")


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
