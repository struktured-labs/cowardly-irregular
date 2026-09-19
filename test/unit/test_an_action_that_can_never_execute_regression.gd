extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag_state: Dictionary

## A grind rule can FIRE and still do nothing. `_member_ability_apply` refuses by name — unknown
## ability, caster does not know it, nothing between battles, target names nobody — and every one
## of those reasons goes to a `print()`. The player's surface is `_log_message`, so none of it is
## reachable; and the explain preview happily rendered the action's LABEL either way, so a rule
## that can never execute read exactly like a working one.
##
## ⛔ THE HALF THAT MAKES THIS A FEATURE RATHER THAN NOISE: only AUTHORING errors are reported.
## A downed caster, an empty MP bar and "no living ally" are TRANSIENT — a healthy grind hits them
## routinely, and a preview that flagged them would be ignored by the second session.
## test_a_transient_refusal_stays_silent is that half, and it is the arm to keep.

var _ui


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	var party: Array = []
	for spec in ["cleric", "mage"]:
		var c := Combatant.new()
		c.initialize({"name": spec.capitalize(), "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 20, "speed": 20})
		## The REAL kit, not {"id": spec} — knows_ability reads job.abilities, so a bare dict makes
		## every ability unknown and the preview would flag a working rule.
		c.job = JobSystem.get_job(spec) if JobSystem and JobSystem.has_method("get_job") else {"id": spec}
		add_child_autofree(c)
		party.append(c)
	_ui._party = party


func after_each() -> void:
	AutogrindState.restore(_ag_state)


func _report(action: Dictionary) -> String:
	_ui.rules = [{"conditions": [{"type": "always"}], "actions": [action], "enabled": true}]
	return "\n".join(PackedStringArray(_ui.explain_rules_report().map(func(x): return str(x))))


## FLOOR. Every symbol these arms drive, named from one place, so a rename reds here instead of
## aborting an arm into a vacuous pass.
func test_the_surface_these_arms_drive_exists() -> void:
	for m in ["_explain_action_refusal", "_can_apply_between_battles", "explain_rules_report"]:
		assert_true(_ui.has_method(m), "AutogrindUI must define %s" % m)
	assert_true(AutogrindSystem.has_method("_resolve_member"), "AutogrindSystem must define _resolve_member")
	assert_true(AutogrindSystem.has_method("ability_works_between_battles"),
		"the between-battle owner must exist — the preview delegates rather than copying it")


func test_an_action_naming_no_ability_is_called_out() -> void:
	var r := _report({"type": "member_ability", "member": "cleric", "ability": ""})
	assert_true(r.contains("names no ability"), "an ability-less cast must be named: %s" % r)
	assert_true(r.contains("never execute"), "and said to be unexecutable: %s" % r)


func test_an_action_naming_a_nonexistent_ability_says_the_id_does_not_exist() -> void:
	## A typo and a real-but-inapplicable ability need DIFFERENT fixes, so they get different words.
	var r := _report({"type": "member_ability", "member": "cleric", "ability": "cuer"})
	assert_true(r.contains("no ability called 'cuer' exists"),
		"a typo'd id must be named as a typo, not as an inapplicable ability: %s" % r)


func test_an_action_whose_ability_does_nothing_between_battles_says_so() -> void:
	assert_false(_ui._can_apply_between_battles("power_strike"),
		"CONTROL: power_strike has no between-battle effect")
	var r := _report({"type": "member_ability", "member": "cleric", "ability": "power_strike"})
	assert_true(r.contains("does nothing between battles"),
		"a real ability that cannot run here must say that, not 'does not exist': %s" % r)


func test_an_action_naming_someone_not_in_the_party_is_called_out() -> void:
	var r := _report({"type": "member_ability", "member": "ninja", "ability": "cure"})
	assert_true(r.contains("names no one in your party"),
		"a member the party does not contain must be named: %s" % r)


func test_a_transient_refusal_stays_silent() -> void:
	## THE ARM TO KEEP. The cleric is DOWN, so at runtime this action is refused — and that is the
	## normal path, not a broken rule. Flagging it would make the preview cry wolf every session.
	_ui._party[0].current_hp = 0
	_ui._party[0].is_alive = false
	_ui._party[1].current_mp = 0
	var r := _report({"type": "member_ability", "member": "cleric", "ability": "cure"})
	assert_false(r.contains("never execute"),
		"a downed caster is transient — the preview must not call the rule dead: %s" % r)
	assert_false(r.contains("fires but its action"),
		"no authoring footnote may appear for a transient refusal: %s" % r)


func test_a_workable_action_produces_no_footnote() -> void:
	var r := _report({"type": "member_ability", "member": "cleric", "ability": "cure"})
	assert_false(r.contains("fires but its action"),
		"a rule that works must draw no complaint, or the footnote means nothing: %s" % r)


func test_a_disabled_rule_is_not_reported() -> void:
	_ui.rules = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "member_ability", "member": "cleric", "ability": ""}], "enabled": false}]
	var r := "\n".join(PackedStringArray(_ui.explain_rules_report().map(func(x): return str(x))))
	assert_false(r.contains("fires but its action"),
		"a disabled rule cannot fire, so its action cannot be at fault: %s" % r)



func test_a_caster_who_does_not_know_the_ability_is_told_to_learn_it() -> void:
	## `pray` is the Cleric's free move and DOES work between battles, so this reaches the
	## knows_ability branch rather than the between-battles one — the only arm that can.
	assert_true(_ui._can_apply_between_battles("pray"),
		"CONTROL: pray works between battles, so a refusal here is about the CASTER")
	var r := _report({"type": "member_ability", "member": "mage", "ability": "pray"})
	assert_true(r.contains("does not know"),
		"a caster without the ability must be told, not left with a silently dead rule: %s" % r)
	assert_false(r.contains("never execute"),
		"and NOT called permanently dead — they can still learn it: %s" % r)


func test_an_action_targeting_someone_not_in_the_party_is_called_out() -> void:
	## A generic ally word means "the lowest-HP living ally" and is valid; a NAME that resolves to
	## nobody is not, and at runtime it refuses silently.
	var r := _report({"type": "member_ability", "member": "cleric", "ability": "pray", "target": "ninja"})
	assert_true(r.contains("targets 'ninja'"), "an unresolvable target must be named: %s" % r)
	var ok := _report({"type": "member_ability", "member": "cleric", "ability": "pray", "target": "lowest_hp_ally"})
	assert_false(ok.contains("fires but its action"),
		"CONTROL: a generic ally target is valid and must draw no complaint: %s" % ok)
