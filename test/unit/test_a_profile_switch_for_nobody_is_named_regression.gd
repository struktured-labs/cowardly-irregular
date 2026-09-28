extends GutTest

## Every Switch Profile in the shipped autogrind defaults names "hero" or "mira", early placeholders who are in no party.
## The action called AutobattleSystem.set_active_profile for them, which CREATED and SAVED a profile set for a phantom
## character, and changed nobody's script. The rule still counted as fired. Now a switch for someone outside the party
## does nothing to the save and is tallied on the Summary like any other rule that did nothing.

const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _system
var _abs: Node
var _saved_profiles: Dictionary
var _saved_persist: bool
var _party: Array[Combatant] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	_saved_profiles = ABProfiles.snapshot(_abs)
	_saved_persist = bool(_abs._test_disable_persistence) if _abs else false
	if _abs:
		_abs._test_disable_persistence = true
		## Erased AFTER the snapshot, so the restore puts back whatever was there. A phantom already present is what this fixes.
		for phantom in ["hero", "mira"]:
			_abs.character_profiles.erase(phantom)
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for n in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		c.initialize({"name": n, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
		c.job = {"id": n.to_lower()}
		add_child_autofree(c)
		_party.append(c)
	_system.grind_party = _party


func after_each() -> void:
	ABProfiles.restore(_abs, _saved_profiles)
	if _abs:
		_abs._test_disable_persistence = _saved_persist


func test_a_switch_for_a_phantom_creates_nothing() -> void:
	assert_false(_abs.character_profiles.has("hero"), "CONTROL: the fixture must start without a hero profile")
	_system.apply_autogrind_actions([{"type": "switch_profile", "character_id": "hero", "profile_index": 1}])
	assert_false(_abs.character_profiles.has("hero"), "a switch for a character in no party created a profile set for them")
	assert_eq(int(_system.get_rule_action_noops().get("Switch Profile: no party member \"hero\"", 0)), 1,
		"and the Summary must be told the rule did nothing")


func test_a_switch_for_a_real_member_still_switches() -> void:
	_system.apply_autogrind_actions([{"type": "switch_profile", "character_id": "fighter", "profile_index": 1}])
	assert_true(_abs.character_profiles.has("fighter"), "CONTROL: a real member's switch must reach autobattle")
	assert_eq(int(_abs.character_profiles["fighter"].get("active", -1)), 1, "a party member's switch must still apply")
	assert_true(_system.get_rule_action_noops().is_empty(), "and must not be reported as doing nothing")


func test_a_knocked_out_member_is_still_in_the_party() -> void:
	_party[1].is_alive = false
	_system.apply_autogrind_actions([{"type": "switch_profile", "character_id": "cleric", "profile_index": 1}])
	assert_true(_system.get_rule_action_noops().is_empty(), "a KO'd member is still the player's, so a switch for them is not a phantom")


## The shipped defaults are the reachable case: a new player's Standard Grind fires these on its first battle.
func test_the_shipped_defaults_leave_no_phantom_behind() -> void:
	for rule in _system._create_default_autogrind_rules():
		_system.apply_autogrind_actions(rule.get("actions", []).filter(func(a): return a.get("type") == "switch_profile"))
	for phantom in ["hero", "mira"]:
		assert_false(_abs.character_profiles.has(phantom), "the shipped defaults left a saved profile for %s" % phantom)
