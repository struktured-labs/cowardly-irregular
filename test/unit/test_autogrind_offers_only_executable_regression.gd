extends GutTest

## cowir-sfx's placement rule, applied to my own feature: "the guard belongs in the GENERATOR, not
## a test on shipped assets — by the time it IS an asset, 'plays nothing' is indistinguishable from
## 'nobody triggers it'." Same for a rule: once saved, "never fires" is indistinguishable from
## "never triggered", and the only refusal that helps is the one at authoring time.
##
## _member_ability_apply executes an ability from its AUTHORED heal_amount / mp_amount and refuses
## anything else by name — at runtime, into a print. Measured across starter kits 2026-09-09:
##
##   cleric   applicable 3   cure · crystal_heal · cura
##   fighter  applicable 0   (5 known)      mage  applicable 0  (11 known)
##   rogue    applicable 0   (7 known)      bard  applicable 0  (4 known)
##
## So the editor was seeding a Fighter's power_strike into a rule that could never fire, and
## cycling offered ten more like it. The feature is Cleric-only in practice, which matches what
## struktured actually asked for ("have cleric use restorative") — but the editor must not offer
## the other four as though they work.

var _ui
var _party: Array[Combatant] = []


func before_each() -> void:
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_party.clear()
	for spec in ["cleric", "fighter"]:
		var c := Combatant.new()
		c.initialize({
			"name": spec.capitalize(), "max_hp": 500, "max_mp": 40,
			"attack": 10, "defense": 10, "magic": 20, "speed": 10
		})
		c.job = {"id": spec}
		add_child_autofree(c)
		_party.append(c)
	_party[0].learned_abilities.append_array(["cure", "protect"])     # protect cannot fire
	_party[1].learned_abilities.append_array(["power_strike", "cleave"])  # neither can these
	_ui._party = _party


func test_the_executable_predicate_matches_the_executor() -> void:
	## ARM+ for everything below: it must say YES to a heal and NO to a support ability, or the
	## filters are either inert or block everything.
	assert_true(_ui._can_apply_between_battles("cure"), "cure authors heal_amount and must pass")
	assert_true(_ui._can_apply_between_battles("pray"), "pray authors mp_amount and must pass")
	assert_false(_ui._can_apply_between_battles("protect"), "protect authors neither and cannot fire")
	assert_false(_ui._can_apply_between_battles("zzq_not_real"), "an unknown id cannot fire")


func test_ability_cycling_never_offers_one_that_cannot_fire() -> void:
	var act := {"type": "member_ability", "member": "cleric", "ability": "cure"}
	_ui.rules = [{"conditions": [{"type": "always"}], "actions": [act], "enabled": true}]
	_ui.cursor_row = 0
	_ui.cursor_col = 1
	for _i in range(6):
		_ui._cycle_ability_on_cursor_cell()
		assert_true(_ui._can_apply_between_battles(str(act.get("ability", ""))),
			"cycling landed on '%s', which the executor refuses" % str(act.get("ability", "")))


func test_seeding_picks_an_ability_that_can_actually_run() -> void:
	## Pre-fix this returned "a healing ability they know, else their FIRST known ability" — so a
	## Fighter seeded power_strike and the rule was saveable and inert.
	var action := {"type": "member_ability"}
	_ui._seed_required_action_fields(action)
	assert_true(_ui._can_apply_between_battles(str(action.get("ability", ""))),
		"seeded '%s' for '%s', which cannot fire" % [str(action.get("ability", "")), str(action.get("member", ""))])


func test_member_cycling_skips_a_member_with_nothing_to_cast() -> void:
	## The fighter knows two abilities and can execute neither. Cycling onto them authors a rule
	## that cannot fire, so they are skipped while someone qualifies.
	var act := {"type": "member_ability", "member": "cleric", "ability": "cure"}
	_ui.rules = [{"conditions": [{"type": "always"}], "actions": [act], "enabled": true}]
	_ui.cursor_row = 0
	_ui.cursor_col = 1
	for _i in range(5):
		_ui._cycle_member_on_cursor_cell()
		assert_ne(str(act.get("member", "")), "fighter",
			"cycling must skip a member with no executable ability while one qualifies")


func test_the_verb_stays_usable_when_NOBODY_qualifies() -> void:
	## Scope guard against over-filtering: a party with no applicable ability anywhere must still
	## be able to author the action, and learn why from the runtime refusal, rather than have the
	## verb silently do nothing when selected.
	_party[0].learned_abilities.clear()
	_party[0].learned_abilities.append("protect")
	var act := {"type": "member_ability", "member": "cleric", "ability": "protect"}
	_ui.rules = [{"conditions": [{"type": "always"}], "actions": [act], "enabled": true}]
	_ui.cursor_row = 0
	_ui.cursor_col = 1
	_ui._cycle_member_on_cursor_cell()
	assert_ne(str(act.get("member", "")), "",
		"with nobody qualifying the member must still cycle, not become empty and unsaveable")
