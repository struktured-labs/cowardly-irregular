extends GutTest

## member_status could not be authored in the console, so a console-made rule could never fire.
##
## The evaluator reads the status NAME from `value` — AutogrindSystem:1912, and the LLM grammar
## says so explicitly ("member_status takes the status name in value"). The console's type table
## declared it has_value: false with default_value 0, and there was no picker: member and ability
## have cycling rings, status had none. So a rule authored in the console asked has_status("0")
## and was permanently false, while its own display arm rendered value as a status name.
##
## Found by censusing the 19 party conditions after the six actions (fd8b794f). Same shape as
## member_ability's target one hour earlier and the same shape as the frozen turn counter: the
## authoring path cannot produce what the evaluator needs, and nothing between them disagrees
## loudly enough to notice.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _ui() -> Node:
	var u = load(UI).new()
	add_child_autofree(u)
	return u


func _member(cname: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 1000, "max_mp": 100,
		"attack": 20, "defense": 20, "magic": 20, "speed": 20})
	c.job = JobSystem.get_job(job_id)
	add_child_autofree(c)
	return c


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true


func test_every_offered_status_is_one_the_game_can_actually_show() -> void:
	## Derived guard rather than a restated list: the ring must be a subset of the statuses
	## BattleScene has icons for, so it can never offer something the player cannot even see on
	## their party.
	var displayable: Dictionary = load(BATTLE_SCENE).STATUS_ICON_CONFIG
	assert_gt(displayable.size(), 0, "control: the icon config must be readable, or this proves nothing")
	var ring: Array = load(UI).MEMBER_STATUS_RING
	assert_gt(ring.size(), 0, "control: the ring must be non-empty")
	var undisplayable: Array = []
	for st in ring:
		if not displayable.has(str(st)):
			undisplayable.append(str(st))
	assert_eq(undisplayable.size(), 0,
		"the status ring offers statuses the game has no icon for: %s" % str(undisplayable))


func test_a_freshly_typed_member_status_condition_is_not_numeric() -> void:
	## default_value 0 is what made the condition dead on creation — has_status("0") is false for
	## every character forever.
	var types: Array = load(UI).CONDITION_TYPES
	var entry: Dictionary = {}
	for t in types:
		if str((t as Dictionary).get("id", "")) == "member_status":
			entry = t
	assert_false(entry.is_empty(), "control: member_status must still be in the console's type table")
	var dv = entry.get("default_value", 0)
	assert_eq(typeof(dv), TYPE_STRING,
		"a member_status condition seeded with a NUMBER asks has_status('0') and can never fire")
	assert_true(load(UI).MEMBER_STATUS_RING.has(str(dv)),
		"the seeded default must be a status the ring can cycle from, or the first press jumps")


func test_cycling_the_status_writes_a_name_the_evaluator_can_use() -> void:
	var u := _ui()
	u.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "value": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true,
	}]
	u.cursor_row = 0
	var before: String = str(u.rules[0]["conditions"][0]["value"])
	u._cycle_status_on_cursor_cell()
	var after: String = str(u.rules[0]["conditions"][0]["value"])
	assert_ne(after, before, "cycling must change the status")
	assert_true(load(UI).MEMBER_STATUS_RING.has(after),
		"cycling must land on a ring entry, not an arbitrary value: %s" % after)


func test_a_console_authored_status_rule_fires_when_the_member_has_it() -> void:
	## End-to-end against the real evaluator: the console's own default, evaluated by
	## AutogrindSystem, must discriminate between an afflicted member and a healthy one.
	var cleric := _member("Status Cleric", "cleric")
	var mage := _member("Status Mage", "mage")
	var party: Array = [cleric, mage]

	var types: Array = load(UI).CONDITION_TYPES
	var seeded := ""
	for t in types:
		if str((t as Dictionary).get("id", "")) == "member_status":
			seeded = str((t as Dictionary).get("default_value", ""))
	## The expectation is DERIVED from the table, so it would move with a mutation of that table —
	## add_status("0") / has_status("0") round-trips happily and this test would pass while the
	## condition was dead in practice. Pin the value's shape here as well.
	assert_eq(typeof(seeded), TYPE_STRING, "precondition: the seeded default is a status NAME")
	assert_true(load(UI).MEMBER_STATUS_RING.has(seeded),
		"precondition: the seeded default is a real affliction, not any string that round-trips")
	var cond := {"type": "member_status", "member": "cleric", "value": seeded}

	assert_false(AutogrindSystem._evaluate_party_condition(party, cond),
		"control: a healthy party must NOT satisfy the condition, or the assertion below is meaningless")
	cleric.add_status(seeded, 3)
	assert_true(cleric.has_status(seeded), "precondition: the status actually landed on the member")
	assert_true(AutogrindSystem._evaluate_party_condition(party, cond),
		"the console's own seeded rule must fire once the named member has that status")


func test_the_ring_row_is_offered_so_the_control_is_reachable() -> void:
	## A cycler nothing can call is the same defect one layer up.
	var u := _ui()
	u.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "value": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true,
	}]
	u.cursor_row = 0
	var ids: Array = []
	for opt in u._options_ring_spec().get("options", []):
		ids.append(str((opt as Dictionary).get("id", "")))
	assert_true(ids.has("cycle_status"),
		"the OPTIONS ring must offer the status cycler, or it is unreachable on a pad")
