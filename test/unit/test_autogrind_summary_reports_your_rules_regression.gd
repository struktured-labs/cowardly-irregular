extends GutTest

## The console tells a player which rules fired. The console is exactly what is NOT open during a
## grind — that single fact produced three separate defects this session: a stop_grinding rule that
## never stopped anything, a SYSTEM COLLAPSE nobody saw, and a meta-boss met and beaten in silence.
##
## The Summary is the surface that ALWAYS runs. So a player whose rules did nothing should learn it
## there, without having had the console open and without knowing the console exists.
##
##   "3 of 5 fired (214 checks)"     they are working
##   "0 of 4 fired (214 checks)"     the grind ran on built-in interrupts alone — flagged
##   "4 authored, never evaluated"   NOT MEASURED, not broken
##   "none authored"                 nothing to report
##
## The denominator rule is the same one the console readout uses: zero fires across zero checks is
## not evidence of a dead rule, and colouring it as a problem would accuse every short session.

const SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"


func _make_summary(stats: Dictionary) -> Node:
	var s: Node = load(SUMMARY).new()
	add_child_autofree(s)
	s._stats = stats
	return s


func test_rules_that_fired_are_reported_with_their_denominator() -> void:
	var s := _make_summary({"rules_authored": 5, "rules_that_fired": 3, "rule_checks": 214})
	var text: String = s._rules_summary()
	assert_true(text.contains("3 of 5"), "both halves of the ratio must show: %s" % text)
	assert_true(text.contains("214"), "and the checks that produced them: %s" % text)
	assert_false(s._rules_did_nothing(), "rules that fired are not a problem to flag")


func test_rules_that_NEVER_fired_across_many_checks_are_flagged() -> void:
	## The case worth surfacing: the grind ran on built-in interrupts alone and the player's own
	## rules contributed nothing.
	var s := _make_summary({"rules_authored": 4, "rules_that_fired": 0, "rule_checks": 214})
	assert_true(s._rules_did_nothing(),
		"four authored rules and 214 checks with zero fires is the case a player most needs told")
	assert_true(s._rules_summary().contains("0 of 4"), "and it must say so plainly: %s" % s._rules_summary())


func test_zero_checks_is_NOT_MEASURED_rather_than_broken() -> void:
	## The denominator. A grind that ended before any rule check must not accuse the rules.
	var s := _make_summary({"rules_authored": 4, "rules_that_fired": 0, "rule_checks": 0})
	assert_false(s._rules_did_nothing(),
		"zero fires across zero checks is not evidence of anything — flagging it would accuse every short session")
	assert_true(s._rules_summary().contains("never evaluated"),
		"and it must say it did not measure, not that nothing fired: %s" % s._rules_summary())


func test_no_rules_authored_reports_plainly() -> void:
	var s := _make_summary({"rules_authored": 0, "rules_that_fired": 0, "rule_checks": 99})
	assert_false(s._rules_did_nothing(), "a player with no rules has no dead rules")
	assert_true(s._rules_summary().contains("none authored"), "%s" % s._rules_summary())


func test_the_controller_carries_the_three_keys_the_summary_reads() -> void:
	## The wiring. Correct helpers reading keys the controller never sends report nothing — the
	## same one-layer-up defect that made meta-bosses invisible.
	var ags := get_node_or_null("/root/AutogrindSystem")
	if ags:
		ags._test_disable_persistence = true
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	var stats: Dictionary = ctrl.get_grind_stats()
	for key in ["rules_authored", "rules_that_fired", "rule_checks"]:
		assert_true(stats.has(key),
			"get_grind_stats must carry '%s' to the Summary: %s" % [key, str(stats.keys())])


func test_the_summary_renders_the_row() -> void:
	var src: String = FileAccess.get_file_as_string(SUMMARY)
	assert_ne(src, "", "control: the summary source must be readable")
	assert_true(src.contains("\"Your Rules\""),
		"the row must exist in the rendered stat list, not merely as a helper nobody calls")
