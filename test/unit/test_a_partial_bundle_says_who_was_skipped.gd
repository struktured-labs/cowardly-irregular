extends GutTest

## A bundle import is the only import that can PARTLY succeed, and it reported only its
## successes.
##
## `apply_script_bundle` skips a malformed entry and keeps going — which is right, one bad
## script should not sink the other four. But the skip went to `push_warning` alone, so the
## only number that reached the player was the count that worked:
##
##     "Imported 3 autobattle scripts from party.json"      in the success colour
##
## Import a five-character bundle with two bad scripts and that line is identical to a clean
## import of three. Two party members silently kept their old scripts, and the player had no
## way to know which two or why — `last_import_errors` was never written on this path, so
## `_refusal_suffix()` would have said "(no reason recorded)" even if the branch had called it.
##
## Every sibling branch in `_import_scripts` already names its reason: the single-script path,
## the autogrind-rules path and the unreadable-file path all do. The bundle path was the one
## that could half-fail and the only one that could not say so.
##
## The repair records the per-character reason where `last_import_reason()` reads it, and the
## UI reports `count of total` with the skipped count whenever they differ. Cleared at ENTRY
## for the reason `apply_character_script` already states: a stale reason from the PREVIOUS
## import is specific, plausible, and about a different file.
##
## ⚠️ PERSISTENCE IS DISABLED FOR EVERY ARM. Applying a bundle calls
## `AutobattleSystem.set_character_script`, which writes `user://autobattle/profiles.json` —
## the player's live profiles, from whichever worktree runs the suite. The profiles map is
## snapshotted and restored as well, because `_test_disable_persistence` stops the WRITE and
## not the in-memory mutation.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")
const Profiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _sys = null
var _snap: Dictionary = {}
var _orig_persist: bool = false


func before_each() -> void:
	_sys = get_tree().root.get_node_or_null("AutobattleSystem")
	if _sys == null:
		return
	_snap = Profiles.snapshot(_sys)
	_orig_persist = _sys._test_disable_persistence
	_sys._test_disable_persistence = true


func after_each() -> void:
	if _sys == null:
		return
	Profiles.restore(_sys, _snap)
	_sys._test_disable_persistence = _orig_persist
	SSM.last_import_errors = []


func _good() -> Dictionary:
	return {
		"rules": [{
			"conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
			"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
		}]
	}


func _bad() -> Dictionary:
	## An unknown condition type — the shallow validator's own vocabulary check, so this
	## fails for a reason the grammar owns rather than a shape the parser would reject.
	return {
		"rules": [{
			"conditions": [{"type": "definitely_not_a_condition", "op": "<", "value": 30}],
			"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
		}]
	}


func _bundle(scripts: Dictionary) -> Dictionary:
	return {"type": "autobattle_bundle", "scripts": scripts}


func test_control_a_clean_bundle_applies_every_script_and_records_no_reason() -> void:
	if _sys == null:
		return
	var n: int = SSM.apply_script_bundle(_bundle({"fighter": _good(), "mage": _good()}))
	assert_eq(n, 2, "CONTROL: both valid scripts must apply")
	assert_eq(SSM.last_import_errors.size(), 0,
		"CONTROL: a clean bundle must record no reason, got: %s" % [SSM.last_import_errors])
	assert_eq(SSM.last_import_reason(), "", "CONTROL: and no reason text")


func test_a_partial_bundle_records_a_reason_naming_the_skipped_character() -> void:
	if _sys == null:
		return
	var n: int = SSM.apply_script_bundle(_bundle({"fighter": _good(), "mage": _bad()}))
	assert_eq(n, 1, "the good script still applies — one bad entry must not sink the bundle")
	assert_eq(SSM.last_import_errors.size(), 1,
		"the skipped entry must record a reason, got: %s" % [SSM.last_import_errors])
	if SSM.last_import_errors.is_empty():
		return
	## Without the name, "the reason" is useless on a bundle: it says something is wrong
	## and not whose script kept its old rules.
	assert_true(str(SSM.last_import_errors[0]).begins_with("mage:"),
		"the reason must name the character it is about, got: %s" % [SSM.last_import_errors[0]])


func test_the_reason_reaches_the_sentence_the_player_reads() -> void:
	## _refusal_suffix() in AutogrindUI is `" — " + last_import_reason()`, or the literal
	## "(no reason recorded)" when it is empty. This arm pins the input to that.
	if _sys == null:
		return
	SSM.apply_script_bundle(_bundle({"fighter": _good(), "mage": _bad()}))
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "a skipped entry must leave a non-empty reason for the UI suffix")
	assert_true(why.find("mage") != -1, "the reason the player reads must name the character: '%s'" % [why])


func test_every_bad_entry_is_named_not_just_the_first() -> void:
	if _sys == null:
		return
	var n: int = SSM.apply_script_bundle(_bundle({"fighter": _bad(), "mage": _bad(), "rogue": _good()}))
	assert_eq(n, 1, "only the valid script applies")
	assert_eq(SSM.last_import_errors.size(), 2,
		"BOTH skipped entries must be recorded — a count of one hides the second: %s" % [SSM.last_import_errors])


func test_a_bundle_where_nothing_applies_still_says_why() -> void:
	if _sys == null:
		return
	var n: int = SSM.apply_script_bundle(_bundle({"fighter": _bad()}))
	assert_eq(n, 0, "nothing applies")
	assert_ne(SSM.last_import_reason(), "",
		"the all-bad case must record a reason too — this is the branch that said 'no script in the bundle could be applied' with nothing after it")


func test_a_stale_reason_from_the_previous_import_does_not_survive() -> void:
	## The failure this guards is specific AND plausible AND about a different file, which is
	## why apply_character_script clears at entry rather than per branch.
	if _sys == null:
		return
	SSM.apply_script_bundle(_bundle({"mage": _bad()}))
	assert_ne(SSM.last_import_reason(), "", "precondition: the first import leaves a reason")
	SSM.apply_script_bundle(_bundle({"fighter": _good()}))
	assert_eq(SSM.last_import_reason(), "",
		"a clean bundle must clear the previous import's reason, got: '%s'" % [SSM.last_import_reason()])
