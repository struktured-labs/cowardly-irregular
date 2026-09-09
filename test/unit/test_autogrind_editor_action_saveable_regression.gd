extends GutTest

## The picker offered a state the editor could not author. _cycle_action_type set only `type`, and
## validate_rule REFUSES an action missing its required fields — so cycling onto "Member Casts"
## produced {"type": "member_ability"}, which fails validation, so set_autogrind_rules refuses the
## whole ruleset and the save is silently rejected behind a push_warning the player never sees.
##
## I shipped both halves in .242 — the picker row and the validation — without checking they were
## compatible with each other. Same shape as cowir-main's revert: I checked the value my change was
## meant to fix and not the values it would also change.
##
## THE INVARIANT: every action type the picker can produce must validate the moment it appears.

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
	_party[0].learned_abilities.append("cure")
	_ui._party = _party


func _seeded(action_type: String) -> Dictionary:
	var action := {"type": action_type}
	_ui._seed_required_action_fields(action)
	return action


func test_every_cyclable_action_validates_the_moment_it_is_created() -> void:
	## The whole point: walk the picker's OWN list rather than a copy of it, so a future action
	## type with required fields is caught here instead of by a player who cannot save.
	var offenders: Array[String] = []
	for entry in _ui.ACTION_TYPES:
		var atype := str((entry as Dictionary)["id"])
		var action := _seeded(atype)
		if bool((entry as Dictionary).get("has_target", false)):
			action["target"] = "all"
		var errs: Array = _system.validate_rule({
			"conditions": [{"type": "always"}], "actions": [action]
		})
		if errs.size() > 0:
			offenders.append("%s -> %s" % [atype, str(errs)])
	assert_eq(offenders.size(), 0,
		"the picker can produce actions that fail validation, so the player cannot save: %s" % str(offenders))


func test_member_ability_is_seeded_from_the_real_party() -> void:
	var action := _seeded("member_ability")
	assert_eq(str(action.get("member", "")), "cleric",
		"the first living member's job id seeds the caster, got '%s'" % str(action.get("member", "")))
	assert_eq(str(action.get("ability", "")), "cure",
		"a healing ability the member actually knows seeds the spell")


func test_seeding_does_not_overwrite_what_the_player_chose() -> void:
	## ARM+: seeding must fill gaps, never clobber. Without this, every cycle would reset the
	## player's chosen caster back to the default.
	var action := {"type": "member_ability", "member": "mage", "ability": "fire"}
	_ui._seed_required_action_fields(action)
	assert_eq(str(action["member"]), "mage", "an explicit member must survive seeding")
	assert_eq(str(action["ability"]), "fire", "an explicit ability must survive seeding")


func test_the_validator_still_refuses_a_genuinely_empty_action() -> void:
	# ARM+ for the whole file: proves validation is real and seeding is what fixes it, rather
	# than the validator having been loosened.
	var errs: Array = _system.validate_rule({
		"conditions": [{"type": "always"}],
		"actions": [{"type": "member_ability"}]
	})
	assert_gt(errs.size(), 0, "an unseeded member_ability must still be rejected by the validator")


func test_the_CYCLE_PATH_itself_seeds_not_just_the_helper() -> void:
	## The arms above call _seed_required_action_fields DIRECTLY, so they pass whether or not
	## _cycle_action_type actually invokes it — deleting the call site left them 4/4 GREEN.
	## The bug lives at the WIRING, so drive the real entry point.
	_ui.rules = [{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}],
		"enabled": true
	}]
	_ui.cursor_row = 0
	## one "always" condition occupies a slot and blocks the +1 spare, so action 0 sits at col 1
	_ui.cursor_col = 1
	# cycle until we land on member_ability, at most one full lap
	var landed := false
	for _i in range(_ui.ACTION_TYPES.size() + 1):
		_ui._cycle_action_type()
		if str((_ui.rules[0]["actions"][0] as Dictionary).get("type", "")) == "member_ability":
			landed = true
			break
	assert_true(landed, "control: cycling must be able to reach member_ability at all")
	var action: Dictionary = _ui.rules[0]["actions"][0]
	assert_ne(str(action.get("member", "")), "",
		"cycling onto member_ability must seed 'member' — got %s" % str(action))
	var errs: Array = _system.validate_rule({
		"conditions": [{"type": "always"}], "actions": [action]
	})
	assert_eq(errs.size(), 0, "the action the CYCLE produced must validate: %s" % str(errs))
