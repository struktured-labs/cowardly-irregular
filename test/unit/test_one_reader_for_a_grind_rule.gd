extends GutTest

## cowir-ai 27374: three private copies described a grind rule, and they disagreed. The console's switch_profile read
## `target`, a key no switch_profile carries, so every switch read "Switch Profile (all)"; the editor's built a profile
## set for "*" just by displaying it. One reader now: AutogrindSystem.describe_condition / describe_action / describe_rule.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const MEMBER := "oneread_probe"

var _ag: Dictionary
var _ab: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_ab = ABProfiles.snapshot(AutobattleSystem)
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	ABProfiles.restore(AutobattleSystem, _ab)
	AutogrindState.restore(_ag)
	AutobattleSystem._test_disable_persistence = false


func test_a_profile_switch_names_who_and_which_profile() -> void:
	AutobattleSystem.character_profiles[MEMBER] = {"profiles": [{"name": "Default"}, {"name": "Turtle Up"}], "active": 0}
	var text: String = AutogrindSystem.describe_action({"type": "switch_profile", "character_id": MEMBER, "profile_index": 1})
	assert_string_contains(text, AutogrindSystem.member_display_name(MEMBER), "a switch names the member it switches")
	assert_string_contains(text, "Turtle Up", "a switch names the profile it switches to, by its own name")
	assert_false(text.contains("(all)"), "a switch for one member read as the whole party: %s" % text)


func test_a_whole_party_switch_reads_as_one_and_creates_no_profile() -> void:
	assert_false(AutobattleSystem.character_profiles.has(AutogrindSystem.ALL_PARTY), "CONTROL: no profile set for '*' before the read")
	var text: String = AutogrindSystem.describe_action({"type": "switch_profile", "character_id": AutogrindSystem.ALL_PARTY, "profile_index": 2})
	assert_string_contains(text, "Whole party", "the party-wide switch says so")
	assert_string_contains(text, "Profile 3", "and names the slot it moves everyone to")
	assert_false(AutobattleSystem.character_profiles.has(AutogrindSystem.ALL_PARTY), "describing a rule created a profile set for '*'")


## Derived from the grammar's own tables, so a new type that nobody taught the reader reds here.
func test_every_condition_and_action_type_reads_as_words() -> void:
	var conds: Array = AutogrindSystem.PARTY_CONDITION_TYPES.keys()
	var acts: Array = AutogrindSystem.AUTOGRIND_ACTION_TYPES.keys()
	assert_gt(conds.size(), 15, "CONTROL: the condition table is the one this file means")
	assert_gt(acts.size(), 5, "CONTROL: the action table is the one this file means")
	for t in conds:
		var d: Dictionary = {"type": t, "member": "fighter"}
		d.merge(AutogrindSystem.condition_defaults_for(str(t)))
		assert_ne(AutogrindSystem.describe_condition(d), str(t), "condition '%s' reads as its raw id" % t)
	for t in acts:
		assert_ne(AutogrindSystem.describe_action({"type": t, "member": "fighter", "ability": "cure", "character_id": MEMBER}), str(t),
			"action '%s' reads as its raw id" % t)


func test_the_console_and_the_editor_say_the_same_thing() -> void:
	var ui: Node = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(ui)
	var ed: Node = load("res://src/ui/autogrind/AutogrindGridEditor.gd").new()
	add_child_autofree(ed)
	var cond := {"type": "party_hp_avg", "op": "<", "value": 30}
	var act := {"type": "switch_profile", "character_id": AutogrindSystem.ALL_PARTY, "profile_index": 1}
	assert_eq(ui._format_condition(cond), AutogrindSystem.describe_condition(cond), "the console's condition cell is the shared reading")
	assert_eq(ed._format_condition(cond), AutogrindSystem.describe_condition(cond), "the editor's condition cell is the shared reading")
	assert_eq(ui._format_action(act), AutogrindSystem.describe_action(act), "the console's action cell is the shared reading")
	assert_eq(ed._format_action(act), AutogrindSystem.describe_action(act), "the editor's action cell is the shared reading")


func test_a_rule_reads_on_one_line() -> void:
	var line: String = AutogrindSystem.describe_rule({
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}],
	})
	assert_eq(line, "Party HP < 30% -> STOP GRINDING", "one rule, one line, in the words the grid uses")
	assert_eq(AutogrindSystem.describe_rule({"conditions": [], "actions": []}), "ALWAYS -> (no actions)", "an empty rule still reads")
