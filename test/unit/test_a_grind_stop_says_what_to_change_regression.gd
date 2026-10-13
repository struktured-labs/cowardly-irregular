extends GutTest
## The refusal to START a grind has always said what to change -- "Heal first, or lower \"Stop at
## HP\" in Options" -- and the mid-session stop never did. Both read the same five rules, and
## `_party_interrupt` carries the rule id for both; `_check_interrupt_conditions` returned only the
## reason String and dropped it, so no consumer could key advice on it. Same discard that cost the
## member name until .669, one field over.
## THE SURFACE MATTERS AS MUCH AS THE SENTENCE: my first version hung the advice on
## `AutogrindUI._on_interrupt_triggered`, and NOTHING EMITS `interrupt_triggered` -- a dead handler.
## `test_autogrind_summary_reports_your_rules_regression` already says why: the console is exactly
## what is not open during a grind, and the Summary is the surface that always runs.
## The rule set is derived from AutogrindSystem.interrupt_rules.keys() at RUNTIME, not parsed from
## source and not hand-listed: a sixth interrupt rule added without advice reds this file.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"

var _ag: Dictionary
var _saved_rules: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_saved_rules = AutogrindSystem.interrupt_rules.duplicate(true)


func after_each() -> void:
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindSystem.interrupt_rules = _saved_rules
	AutogrindState.restore(_ag)


## Returns the ABSENT value, never a placeholder: a sentinel reading non-empty would satisfy "every
## rule must say something" and green this whole file on the defect. The floors name the member.
func _advice(rule: String) -> String:
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	if not s.has_method("_interrupt_advice"):
		return ""
	return str(s._interrupt_advice(rule))


func _assert_advice_exists() -> void:
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	assert_true(s.has_method("_interrupt_advice"),
		"FLOOR: AutogrindSummary._interrupt_advice must exist, or every arm below passes by absence")


func _remembered() -> String:
	if not ("last_interrupt_rule" in AutogrindSystem):
		return ""
	return str(AutogrindSystem.last_interrupt_rule)


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


func _texts(n: Node, acc: Array) -> Array:
	if n is Label:
		acc.append(str(n.text))
	for c in n.get_children():
		_texts(c, acc)
	return acc


## Builds the REAL summary through its own entry point, so the advice is read off what renders.
func _render(reason: String, rule: String) -> Array:
	if "last_interrupt_rule" in AutogrindSystem:
		AutogrindSystem.last_interrupt_rule = rule
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	s.setup({"battles_won": 7, "total_exp": 120, "elapsed_seconds": 90.0}, reason)
	await wait_frames(3)
	return _texts(s, [])


## THE DERIVED ARM: every rule the system can interrupt on must have advice, read from the live
## dictionary rather than a list in this file.
func test_every_interrupt_rule_says_what_to_change() -> void:
	_assert_advice_exists()
	var rules: Array = AutogrindSystem.interrupt_rules.keys()
	assert_gt(rules.size(), 3, "FLOOR: the live rule set must have been read, not an empty dict")
	for rule in rules:
		assert_ne(_advice(str(rule)), "",
			"'%s' can stop a grind, so it must say what the player can change" % rule)


## THE ARM THAT CATCHES THE DEAD SURFACE: a sentence that exists but reaches nobody is not a fix.
func test_the_advice_reaches_the_rendered_summary() -> void:
	var want: String = _advice("hp_threshold")
	assert_ne(want, "", "FLOOR: there must be an hp_threshold sentence to look for")
	var texts: Array = await _render("Rook is below your 30% HP stop", "hp_threshold")
	var joined: String = "\n".join(texts)
	assert_true(joined.contains("Stopped:"), "FLOOR: the summary must have rendered at all: %s" % joined)
	assert_true(joined.contains(want),
		"the advice must reach the surface a player actually sees, not just exist: %s" % joined)


## CONTROL: a stop with no interrupt rule behind it (manual, or a stop_grinding rule) must not be
## handed someone else's remedy.
func test_a_stop_with_no_rule_renders_no_advice() -> void:
	var texts: Array = await _render("Manual stop", "")
	var joined: String = "\n".join(texts)
	assert_true(joined.contains("Stopped:"), "FLOOR: the summary must still render its reason: %s" % joined)
	for rule in AutogrindSystem.interrupt_rules.keys():
		var a: String = _advice(str(rule))
		if a != "":
			assert_false(joined.contains(a), "a manual stop must not show '%s' advice" % rule)


## CONTROL: the advice must not be one sentence that answers for anything.
func test_an_unknown_rule_gets_no_invented_advice() -> void:
	_assert_advice_exists()
	assert_eq(_advice("not_a_rule"), "", "CONTROL: an unknown rule must get nothing, not a default sentence")
	assert_eq(_advice(""), "", "CONTROL: and neither must an empty one")


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
	assert_eq(_remembered(), "hp_threshold", "the rule that stopped the grind must survive the String return")


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


## A new session must not inherit the last one's rule: a grind stopped manually before its first
## check would otherwise show the previous session's remedy.
func test_a_new_grind_does_not_inherit_the_previous_rule() -> void:
	_assert_rule_field_exists()
	if "last_interrupt_rule" in AutogrindSystem:
		AutogrindSystem.last_interrupt_rule = "hp_threshold"
	var started: bool = AutogrindSystem.start_autogrind(_party("Rook", 100), {"id": "slime", "name": "Slime", "max_hp": 30})
	assert_true(started, "FLOOR: the fixture must actually start a grind")
	assert_eq(_remembered(), "", "a new session must not inherit the previous session's rule")
