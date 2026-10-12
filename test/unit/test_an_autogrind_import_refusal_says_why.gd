extends GutTest

## Three of the four `return false` exits in `apply_autogrind_rules` recorded no reason, and
## both callers ask for one.
##
## The file-import path prints `_refusal_suffix()`, which renders the literal
## "(no reason recorded)" when `last_import_reason()` is empty. The clipboard path is worse:
## it falls back to "Clipboard has no valid autogrind share code", which is simply WRONG for
## an export containing an empty rule list — the code decoded fine and had no rules in it.
##
## Only the rule-error exit passed its reason on. The empty-rules exit and the choke-point
## drift exit both computed or knew the reason and dropped it; the drift one even carries the
## comment "surface it instead of lying to the user" directly above a `push_warning` that only
## reaches the console.
##
## This is the sibling of the bundle defect fixed in `a-partial-bundle-says-who-was-skipped`:
## same file, same `last_import_errors` channel, same shape — a precise reason that stopped at
## the console while the player read a vague or misleading line.
##
## ⚠️ REACHABILITY, checked rather than assumed. Both callers pre-check the type, so the
## wrong-type exit is not reachable from either one today; it is covered because the function
## should not depend on every caller remembering, which is the same argument the existing
## clear-at-entry comment makes. The two exits a player CAN reach are the empty rule set and
## the drift, and those are the arms that matter.
##
## Persistence is disabled and the rule set snapshotted: a successful apply writes
## `user://autogrind` — the player's live rules, from whichever worktree runs the suite.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")

var _ag = null
var _snap: Array = []
var _orig_persist: bool = false


func before_each() -> void:
	_ag = get_tree().root.get_node_or_null("AutogrindSystem")
	if _ag == null:
		return
	_snap = (_ag.get_autogrind_rules() as Array).duplicate(true)
	_orig_persist = _ag._test_disable_persistence
	_ag._test_disable_persistence = true
	SSM.last_import_errors = []


func after_each() -> void:
	if _ag == null:
		return
	_ag.set_autogrind_rules(_snap)
	_ag._test_disable_persistence = _orig_persist
	SSM.last_import_errors = []


func test_control_the_autoload_is_reachable_and_a_valid_import_records_no_reason() -> void:
	## Without this, every refusal arm below could pass on a function that refuses everything.
	assert_not_null(_ag, "CONTROL: AutogrindSystem autoload must exist")
	if _ag == null:
		return
	var good: Dictionary = {"type": "autogrind_rules", "rules": _snap.duplicate(true)}
	if _snap.is_empty():
		## No live rules to round-trip; the other arms still stand on their own.
		return
	assert_true(SSM.apply_autogrind_rules(good), "CONTROL: the player's own current rules must re-import")
	assert_eq(SSM.last_import_reason(), "", "CONTROL: and a clean import records no reason")


func test_an_empty_rule_set_says_it_is_empty_rather_than_invalid() -> void:
	## The misleading one: the clipboard caller says "no valid autogrind share code" when the
	## code was perfectly valid and simply had no rules.
	if _ag == null:
		return
	assert_false(SSM.apply_autogrind_rules({"type": "autogrind_rules", "rules": []}),
		"an empty rule set must still be refused")
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "an empty rule set must record a reason, not leave '(no reason recorded)'")
	assert_true(why.to_lower().find("no autogrind rules") != -1,
		"and the reason must say the export is EMPTY rather than implying it is malformed: '%s'" % [why])


func test_a_missing_rules_key_is_the_same_refusal_as_an_empty_one() -> void:
	## `data.get("rules", [])` makes an absent key and an empty list the same case. Pinned so
	## a later split of the two cannot silently drop the reason from one of them.
	if _ag == null:
		return
	assert_false(SSM.apply_autogrind_rules({"type": "autogrind_rules"}),
		"an export with no 'rules' key must be refused")
	assert_ne(SSM.last_import_reason(), "", "and it must record a reason too")


func test_a_wrong_type_records_a_reason_even_though_both_callers_pre_check() -> void:
	## Not reachable from either caller today — covered so the function does not depend on
	## every future caller remembering to pre-check.
	if _ag == null:
		return
	assert_false(SSM.apply_autogrind_rules({"type": "autobattle_script", "rules": [{}]}),
		"a non-autogrind export must be refused")
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "the wrong-type exit must record a reason")
	assert_true(why.find("autobattle_script") != -1,
		"and naming the type it actually got is what makes it actionable: '%s'" % [why])


func test_a_stale_reason_from_a_previous_import_does_not_survive() -> void:
	## The clear sits at entry for this reason; the arm pins that it works through THIS path.
	if _ag == null:
		return
	SSM.apply_autogrind_rules({"type": "autogrind_rules", "rules": []})
	assert_ne(SSM.last_import_reason(), "", "precondition: the first refusal leaves a reason")
	if _snap.is_empty():
		return
	assert_true(SSM.apply_autogrind_rules({"type": "autogrind_rules", "rules": _snap.duplicate(true)}),
		"precondition: a valid import succeeds")
	assert_eq(SSM.last_import_reason(), "",
		"a successful import must clear the previous refusal's reason, got: '%s'" % [SSM.last_import_reason()])
