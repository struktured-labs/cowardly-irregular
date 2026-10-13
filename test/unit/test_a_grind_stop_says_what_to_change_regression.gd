extends GutTest
## The refusal to START a grind has always said what to change — "Heal first, or lower \"Stop at
## HP\" in Options" — and the mid-session stop never did. Both read the same five rules, and
## `_party_interrupt` carries the rule id for both; `_check_interrupt_conditions` returned only the
## reason String and dropped it, so the console had nothing to key advice on. Same discard that
## cost the member name until .669, one field over.
## The rule set is derived from AutogrindSystem.interrupt_rules.keys() at RUNTIME, not parsed from
## source and not hand-listed: a sixth interrupt rule added without advice reds this file.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _saved_rules: Dictionary
var _ui


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_saved_rules = AutogrindSystem.interrupt_rules.duplicate(true)
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)


func after_each() -> void:
	AutogrindSystem.interrupt_rules = _saved_rules
	AutogrindState.restore(_ag)


## Neither member exists on the unfixed tree, and reaching a missing one ABORTS the arm into Risky
## rather than failing it. These return the ABSENT value, never a placeholder: a sentinel that reads
## non-empty would satisfy "every rule must say something" and green this whole file on the defect.
## The floors below are what name the missing symbol, so no arm can pass by absence instead.
func _advice(rule: String) -> String:
	if not _ui.has_method("_interrupt_advice"):
		return ""
	return str(_ui._interrupt_advice(rule))


func _remembered() -> String:
	if not ("last_interrupt_rule" in AutogrindSystem):
		return ""
	return str(AutogrindSystem.last_interrupt_rule)


func _assert_advice_exists() -> void:
	assert_true(_ui.has_method("_interrupt_advice"),
		"FLOOR: AutogrindUI._interrupt_advice must exist, or every arm below passes by absence")


func _assert_rule_field_exists() -> void:
	assert_true("last_interrupt_rule" in AutogrindSystem,
		"FLOOR: AutogrindSystem.last_interrupt_rule must exist, or an empty read looks like a clear")


func _party(hurt: String, hp: int, alive: bool = true) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for n in ["Rook", "Vesper"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": n, "max_hp": 100, "max_mp": 10})
		c.current_hp = (hp if n == hurt else 100)
		c.is_alive = (alive if n == hurt else true)
		out.append(c)
	return out


## THE DERIVED ARM: every rule the system can interrupt on must have advice, and the rule set comes
## from the live dictionary rather than a list in this file.
func test_every_interrupt_rule_says_what_to_change() -> void:
	_assert_advice_exists()
	var rules: Array = AutogrindSystem.interrupt_rules.keys()
	assert_gt(rules.size(), 3, "FLOOR: the live rule set must have been read, not an empty dict")
	for rule in rules:
		assert_ne(_advice(str(rule)), "",
			"'%s' can stop a grind, so it must say what the player can change" % rule)


## CONTROL: the advice must not be a constant that answers for anything.
func test_an_unknown_rule_gets_no_invented_advice() -> void:
	_assert_advice_exists()
	assert_eq(_advice("not_a_rule"), "", "CONTROL: an unknown rule must get nothing, not a default sentence")
	assert_eq(_advice(""), "", "CONTROL: and neither must an empty one")


## CONTROL: the five must not share one sentence.
func test_the_rules_do_not_share_one_sentence() -> void:
	_assert_advice_exists()
	var seen: Dictionary = {}
	for rule in AutogrindSystem.interrupt_rules.keys():
		var a: String = _advice(str(rule))
		assert_false(seen.has(a), "'%s' repeats another rule's advice, which tells the player nothing" % rule)
		seen[a] = true


func test_the_system_remembers_which_rule_stopped_the_grind() -> void:
	_assert_rule_field_exists()
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	AutogrindSystem.interrupt_rules["party_death"] = false
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	AutogrindSystem.grind_party = _party("Vesper", 11)
	var reason: String = AutogrindSystem._check_interrupt_conditions()
	assert_ne(reason, "", "FLOOR: the fixture must actually trip a rule")
	assert_eq(_remembered(), "hp_threshold",
		"the rule that stopped the grind must survive the String return")


## CONTROL: a grind that was not stopped must not leave a stale rule behind.
func test_a_grind_that_was_not_stopped_remembers_nothing() -> void:
	_assert_rule_field_exists()
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	AutogrindSystem.interrupt_rules["party_death"] = true
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	if "last_interrupt_rule" in AutogrindSystem:
		AutogrindSystem.last_interrupt_rule = "hp_threshold"
	AutogrindSystem.grind_party = _party("Rook", 100)
	assert_eq(AutogrindSystem._check_interrupt_conditions(), "", "FLOOR: a healthy party trips nothing")
	assert_eq(_remembered(), "",
		"CONTROL: and the remembered rule must be cleared, or the next stop reports the previous one")
