extends GutTest
## The stop advice is drawn by a Label with no width, no clip_text and no autowrap, inside a panel
## whose DEFAULT width is 520 (AutogrindSummary:166). I shipped it in .672 and rendered it ONCE --
## with `hp_threshold`, ~61 chars. `corruption_limit` is 101 and is a real stop: it guards system
## collapse. @cowir-adhoc's jobs-panel finding the same day is the reason this file exists: "exactly
## at the edge is what a defect looks like when the shortest case is the one you happen to render."
## So this measures EVERY rule the system can stop on, derived from interrupt_rules.keys(), against
## the NARROW panel -- not the one sentence I had a screenshot of.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _labels(n: Node, acc: Array) -> Array:
	if n is Label:
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)
	return acc


## Builds the REAL summary and returns [the advice Label, the panel it sits in], or [] if absent.
func _render(rule: String) -> Array:
	if "last_interrupt_rule" in AutogrindSystem:
		AutogrindSystem.last_interrupt_rule = rule
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	s.setup({"battles_won": 7, "total_exp": 120, "elapsed_seconds": 90.0}, "a stop")
	await wait_frames(3)
	var want: String = ""
	if s.has_method("_interrupt_advice"):
		want = str(s._interrupt_advice(rule))
	if want == "":
		return []
	for lbl in _labels(s, []):
		if str(lbl.text) == want:
			return [lbl, lbl.get_parent()]
	return []


func test_every_advice_sentence_stays_inside_the_panel() -> void:
	var rules: Array = AutogrindSystem.interrupt_rules.keys()
	assert_gt(rules.size(), 3, "FLOOR: the live rule set must have been read")
	var checked: int = 0
	for rule in rules:
		var found: Array = await _render(str(rule))
		assert_false(found.is_empty(), "FLOOR: '%s' must render an advice label to measure" % rule)
		if found.is_empty():
			continue
		var lbl: Label = found[0]
		var panel: Node = found[1]
		checked += 1
		var right: float = lbl.position.x + lbl.size.x
		assert_lte(right, panel.size.x,
			"'%s' advice runs %dpx past the panel edge (%d chars) -- it draws over the screen behind the menu" % [
				rule, int(right - panel.size.x), str(lbl.text).length()])
	assert_eq(checked, rules.size(), "FLOOR: every rule must have been measured, not skipped")


## CONTROL: the arm above is only worth anything if the LONGEST sentence is actually among the ones
## it measures -- a corpus that happens to hold only short ones proves nothing about the defect.
func test_the_longest_sentence_is_in_the_measured_set() -> void:
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	assert_true(s.has_method("_interrupt_advice"), "FLOOR: the advice function must exist")
	if not s.has_method("_interrupt_advice"):
		return
	var longest: int = 0
	for rule in AutogrindSystem.interrupt_rules.keys():
		longest = maxi(longest, str(s._interrupt_advice(str(rule))).length())
	assert_gt(longest, 80,
		"CONTROL: the measured set must contain a sentence long enough to overflow 520px, or the arm above is vacuous")
