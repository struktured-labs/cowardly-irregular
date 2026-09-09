extends GutTest

## struktured 2026-09-06: "should be able to select a specific party member condition or ability.
## like if cleric is dead, stop grinding. if mage is dead, have cleric [use] restorative."
##
## The CONDITION half shipped in .239 (member_dead + "member"). This is the ACTION half — the
## sentence "have cleric use restorative" had no expressible form: the five action types were all
## party-level verbs with no caster and no ability.
##
## Between battles, like heal_party. The difference is the currency: heal_party spends POTIONS,
## member_ability spends the caster's MP. That is a real choice, not a strict upgrade.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", 40], ["mage", 40]]:
		var c := Combatant.new()
		c.initialize({
			"name": str(spec[0]).capitalize(), "max_hp": 1000, "max_mp": int(spec[1]),
			"attack": 10, "defense": 10, "magic": 20, "speed": 10
		})
		c.job = {"id": str(spec[0])}
		add_child_autofree(c)
		_party.append(c)
	_party[0].learned_abilities.append("cure")
	_system.grind_party = _party


func _apply(member: String, ability: String, target: String = "") -> Dictionary:
	return _system._member_ability_apply(_system._resolve_member(_party, member), ability, target)


func test_the_named_member_casts_and_pays_for_it() -> void:
	_party[1].current_hp = 100           # mage hurt
	var mp_before: int = _party[0].current_mp
	var info := _apply("cleric", "cure", "mage")
	assert_true(info.get("ok", false), "the cleric knows cure and has MP: %s" % str(info.get("reason", "")))
	assert_gt(_party[1].current_hp, 100, "the mage must actually be healed")
	assert_lt(_party[0].current_mp, mp_before, "and the CLERIC pays the MP — this is not a free heal")


func test_a_member_who_does_not_know_the_ability_is_refused_with_a_reason() -> void:
	## The mage never learned cure. Silent refusal is the hardest bug to debug from a console,
	## so every rejection names itself.
	var info := _apply("mage", "cure")
	assert_false(info.get("ok", true), "the mage does not know cure")
	assert_true(str(info.get("reason", "")).contains("does not know"),
		"the refusal must say WHY, got '%s'" % str(info.get("reason", "")))


func test_insufficient_mp_is_refused_not_cast_for_free() -> void:
	_party[0].current_mp = 0
	var info := _apply("cleric", "cure")
	assert_false(info.get("ok", true), "no MP means no cast")
	assert_true(str(info.get("reason", "")).contains("MP"), "the reason must name MP")


func test_an_unknown_ability_id_is_refused() -> void:
	## Mirrors the resolver fix: an id JobSystem cannot resolve must never fall through to a
	## default that does something.
	var info := _apply("cleric", "zzq_not_a_real_ability")
	assert_false(info.get("ok", true), "an unresolvable ability must be refused")


func test_a_member_not_in_the_party_is_refused() -> void:
	# ARM+ for _resolve_member reuse: a bard who left must not resolve to whoever is first.
	var info := _apply("bard", "cure")
	assert_false(info.get("ok", true), "a member absent from the party cannot cast")


func test_the_default_target_is_the_ally_who_most_needs_it() -> void:
	## No explicit target: pick the lowest-HP living ally. Without this the rule would need the
	## player to name a target for the common case, which is the case he described.
	_party[0].current_hp = 900
	_party[1].current_hp = 50
	var info := _apply("cleric", "cure")
	assert_true(info.get("ok", false), "should cast: %s" % str(info.get("reason", "")))
	assert_eq(str(info.get("target", "")), "Mage", "the hurt mage is the default target, not the caster")


func test_an_explicit_target_overrides_the_default() -> void:
	# ARM+ for the above: proves the default is a fallback, not the only behaviour.
	_party[0].current_hp = 500
	_party[1].current_hp = 50
	var info := _apply("cleric", "cure", "cleric")
	assert_eq(str(info.get("target", "")), "Cleric", "an explicit target must win over lowest-HP")


func test_the_validator_requires_both_halves() -> void:
	## "have <member> use <ability>" needs both. An absent field would evaluate to a silent no-op.
	for bad in [{"type": "member_ability", "member": "cleric"}, {"type": "member_ability", "ability": "cure"}]:
		var errs: Array = _system.validate_rule({
			"conditions": [{"type": "always"}], "actions": [bad]
		})
		assert_gt(errs.size(), 0, "incomplete member_ability must be rejected: %s" % str(bad))


func test_a_complete_member_ability_rule_validates() -> void:
	# ARM+ for the rejection: proves the check is scoped and does not refuse valid rules.
	var errs: Array = _system.validate_rule({
		"conditions": [{"type": "member_dead", "member": "mage"}],
		"actions": [{"type": "member_ability", "member": "cleric", "ability": "cure"}]
	})
	assert_eq(errs.size(), 0, "his exact sentence must validate, got %s" % str(errs))


func test_the_action_is_registered_everywhere_a_consumer_reads_it() -> void:
	## The fan-out I got wrong last time: a grammar addition has FOUR consumers and a per-file
	## test run cannot see any of them. Registering in the table alone leaves the type
	## unauthorable by the editor and unemittable by the Rule Composer.
	assert_true(_system.AUTOGRIND_ACTION_TYPES.has("member_ability"), "the action table")
	var ui: String = load("res://src/ui/autogrind/AutogrindUI.gd").source_code
	assert_true(ui.contains('"id": "member_ability"'), "the editor's action picker rows")
	var prompts: String = load("res://src/llm/DialoguePrompts.gd").source_code
	assert_true(prompts.contains("member_ability"), "the LLM Rule Composer grammar")
