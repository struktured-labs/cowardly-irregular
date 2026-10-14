extends GutTest

## "Safe Grind" shipped the one-rule placeholder a BLANK profile gets -- no stop rule at all -- while "Standard Grind" stops at alive_count <= 2, so the profile named for caution was the least cautious one shipped and byte-identical to "Aggressive Grind".

const GuardSubject := preload("res://test/unit/helpers/guard_subject.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SELF_PATH := "res://test/unit/test_a_shipped_grind_profile_keeps_its_name_promise.gd"

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = AutogrindState.snapshot_and_isolate()


func after_each() -> void:
	AutogrindState.restore(_snap)


## Driven through .call so the floor arm below can derive the name from this file's own source.
func _shipped(slot: int) -> Array:
	return AutogrindSystem.call("shipped_autogrind_rules_for", slot) as Array


func _slots() -> int:
	return int(AutogrindSystem.DEFAULT_AUTOGRIND_TEMPLATES.size())


func _name_of(slot: int) -> String:
	return str(AutogrindSystem.DEFAULT_AUTOGRIND_TEMPLATES[slot])


## The alive_count a ruleset stops at; -1 when it carries no alive_count stop at all.
func _stop_at_alive(rules: Array) -> int:
	for rule in rules:
		var rd := rule as Dictionary
		var stops := false
		for a in (rd.get("actions", []) as Array):
			if str((a as Dictionary).get("type", "")) == "stop_grinding":
				stops = true
				break
		if not stops:
			continue
		for c in (rd.get("conditions", []) as Array):
			var cd := c as Dictionary
			if str(cd.get("type", "")) == "alive_count":
				return int(cd.get("value", -1))
	return -1


func _pairs(rules: Array, cond_type: String, action_type: String) -> bool:
	for rule in rules:
		var rd := rule as Dictionary
		var has_cond := false
		for c in (rd.get("conditions", []) as Array):
			if str((c as Dictionary).get("type", "")) == cond_type:
				has_cond = true
				break
		if not has_cond:
			continue
		for a in (rd.get("actions", []) as Array):
			if str((a as Dictionary).get("type", "")) == action_type:
				return true
	return false


func _actions_of_type(rules: Array, want: String) -> Array:
	var out: Array = []
	for rule in rules:
		for a in ((rule as Dictionary).get("actions", []) as Array):
			if str((a as Dictionary).get("type", "")) == want:
				out.append(a as Dictionary)
	return out


func test_no_shipped_profile_is_the_blank_placeholder() -> void:
	var blank: Array = AutogrindSystem.call("_create_empty_autogrind_rules") as Array
	assert_gt(blank.size(), 0, "CONTROL: the blank placeholder is empty, so this comparison cannot fail for the right reason")
	for slot in range(_slots()):
		assert_ne(str(_shipped(slot)), str(blank),
			("shipped profile \"%s\" (slot %d) holds the SAME one-rule placeholder a brand-new "
			+ "blank profile gets, so its name promises a ruleset it does not carry") % [_name_of(slot), slot])


func test_no_two_shipped_profiles_are_the_same_ruleset() -> void:
	var seen: Dictionary = {}
	for slot in range(_slots()):
		var key: String = str(_shipped(slot))
		assert_false(seen.has(key),
			("shipped profiles \"%s\" and \"%s\" are byte-identical rulesets -- the player picks "
			+ "between two names that do the same thing") % [_name_of(int(seen.get(key, -1))) if seen.has(key) else "", _name_of(slot)])
		seen[key] = slot


func test_every_shipped_profile_carries_a_stop_rule() -> void:
	for slot in range(_slots()):
		assert_gt(_actions_of_type(_shipped(slot), "stop_grinding").size(), 0,
			("shipped profile \"%s\" has NO stop_grinding rule, so nothing but the interrupt rules "
			+ "ever ends a grind run under it") % [_name_of(slot)])


func test_the_cautious_profile_stops_no_later_than_the_standard_one() -> void:
	var standard: int = _stop_at_alive(_shipped(0))
	var safe: int = _stop_at_alive(_shipped(1))
	assert_gt(standard, 0, "CONTROL: \"%s\" carries no alive_count stop, so there is nothing to be cautious RELATIVE TO" % [_name_of(0)])
	assert_gt(safe, 0, "\"%s\" carries no alive_count stop at all" % [_name_of(1)])
	assert_true(safe >= standard,
		("\"%s\" stops with %d alive but \"%s\" stops with %d -- the cautious profile lets the "
		+ "party get THINNER before it stops, which is the opposite of its name") % [
			_name_of(1), safe, _name_of(0), standard])


## The other side of the same threshold, and the reason equality above is the CORRECT state rather than a missed chance to be safer.
func test_no_shipped_profile_refuses_a_party_the_standard_one_would_grind() -> void:
	var standard: int = _stop_at_alive(_shipped(0))
	assert_gt(standard, 0, "CONTROL: \"%s\" carries no alive_count stop to compare against" % [_name_of(0)])
	for slot in range(_slots()):
		var mine: int = _stop_at_alive(_shipped(slot))
		if mine < 0:
			continue
		assert_true(mine <= standard,
			("shipped profile \"%s\" stops at %d alive where \"%s\" stops at %d -- alive_count is "
			+ "ABSOLUTE and nothing refuses a rule-level stop up front, so it starts and halts at "
			+ "its first evaluation for any party of %d. W1 unlocks the starters one "
			+ "at a time, so that party size is normal.") % [
				_name_of(slot), mine, _name_of(0), standard, mine])


## Where the caution actually lives, now that the party-size stop cannot carry it.
func test_the_cautious_profile_carries_a_protection_the_standard_one_lacks() -> void:
	var standard: Array = _shipped(0)
	var safe: Array = _shipped(1)
	assert_false(_pairs(standard, "member_injured", "stop_grinding"),
		"CONTROL: \"%s\" already hard-stops on a permanent injury, so that is no longer the cautious profile's own promise" % [_name_of(0)])
	assert_true(_pairs(safe, "member_injured", "stop_grinding"),
		("\"%s\" does not stop on a permanent injury -- with its party-size stop matching "
		+ "\"%s\" by necessity, this is the protection that makes the name true") % [_name_of(1), _name_of(0)])


func test_the_aggressive_profile_leans_the_other_way() -> void:
	var standard: int = _stop_at_alive(_shipped(0))
	var aggressive: int = _stop_at_alive(_shipped(2))
	assert_gt(standard, 0, "CONTROL: \"%s\" carries no alive_count stop to lean against" % [_name_of(0)])
	assert_gt(aggressive, 0, "\"%s\" keeps a last-resort stop so a wipe still ends the run" % [_name_of(2)])
	assert_true(aggressive <= standard,
		("\"%s\" stops with %d alive and \"%s\" with %d -- the aggressive profile is no more "
		+ "willing to push than the standard one, so the name buys the player nothing") % [
			_name_of(2), aggressive, _name_of(0), standard])


func test_every_shipped_ruleset_is_accepted_by_the_validator() -> void:
	for slot in range(_slots()):
		var rules: Array = _shipped(slot)
		assert_gt(rules.size(), 0, "shipped profile \"%s\" has no rules at all" % [_name_of(slot)])
		for i in range(rules.size()):
			var errs: Array = AutogrindSystem.call("validate_rule", rules[i] as Dictionary)
			assert_eq(errs.size(), 0,
				"shipped profile \"%s\" rule %d does not validate: %s" % [_name_of(slot), i, errs])
		assert_true(bool(AutogrindSystem.call("set_autogrind_rules", rules.duplicate(true))),
			("set_autogrind_rules REFUSED shipped profile \"%s\" -- the console shows that as "
			+ "\"Rules rejected\" with no bad row to fix") % [_name_of(slot)])


func test_every_switch_profile_index_names_a_profile_that_exists() -> void:
	var made: Dictionary = AutobattleSystem.call("_create_default_profiles", "fighter") as Dictionary
	var available: int = int((made.get("profiles", []) as Array).size())
	assert_gt(available, 0, "CONTROL: a character got no default autobattle profiles, so no index can be checked")
	for slot in range(_slots()):
		for action in _actions_of_type(_shipped(slot), "switch_profile"):
			var idx: int = int(action.get("profile_index", -1))
			assert_true(idx >= 0 and idx < available,
				("shipped profile \"%s\" switches to autobattle profile %d but a character is "
				+ "created with %d -- set_active_profile IGNORES an out-of-range index SILENTLY, "
				+ "so the rule would fire forever and change nothing") % [_name_of(slot), idx, available])


func test_this_guard_still_reaches_its_subjects() -> void:
	var calls: Dictionary = GuardSubject.audit_calls(SELF_PATH, AutogrindSystem)
	assert_eq(str(calls["why"]).strip_edges(), "",
		"the comment strip failed, so the derived member list is prose or empty -- that is the INSTRUMENT, not the subject: %s" % [calls["why"]])
	assert_gt(int(calls["found"]), 0,
		"VOID: no `.call(\"name\")` found in this file's own text -- the extraction is broken, not the subject")
	## audit_calls is receiver-BLIND: it derives every name this file drives, and this file drives TWO autoloads.
	var orphans: Array = []
	for n in (calls["missing"] as Array):
		if not AutobattleSystem.has_method(str(n)):
			orphans.append(str(n))
	orphans.sort()
	assert_eq(orphans, [],
		("this guard drives those methods BY NAME and neither AutogrindSystem nor AutobattleSystem "
		+ "has them, so its arms would ABORT INTO A SILENT PASS: %s") % [orphans])
