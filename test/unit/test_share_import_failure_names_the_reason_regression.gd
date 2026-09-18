extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left autoload state for every later file.
var _ag_state: Dictionary

## A refused share code told the player "Share code valid but could not apply."
##
## That sentence asserts the code is valid AND that it did not apply, in one breath, and gives
## nothing to act on. The real reason existed: validate_imported_script returns errors naming the
## RULE INDEX and the offending field, and the applier passed them to push_warning — the log the
## player never reads — then returned a bare false. The diagnosis was computed, formatted, and
## discarded one frame before the message that needed it.
##
## Found by checking the blast radius of my own change: tightening validate_rule to require
## condition payloads (530de5d5) makes refusal MORE reachable, and import is all-or-nothing — a
## single bad rule rejects the whole script, so the player loses working rules too and previously
## had no way to learn which one was at fault.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	SSM.last_import_errors = []
	var abs_node := get_node_or_null("/root/AutobattleSystem")
	if abs_node:
		abs_node._test_disable_persistence = true
	var ags := get_node_or_null("/root/AutogrindSystem")
	if ags:
		ags._test_disable_persistence = true


func after_each() -> void:
	SSM.last_import_errors = []
	var abs_node := get_node_or_null("/root/AutobattleSystem")
	if abs_node:
		abs_node.character_profiles.erase("share_reason_probe")
	AutogrindState.restore(_ag_state)



func test_a_refused_autobattle_import_reports_which_rule_and_field() -> void:
	## has_status with no status: validates clean before 530de5d5, dead forever after import.
	var applied: bool = SSM.apply_character_script("share_reason_probe", {
		"type": "autobattle_script",
		"script": {"rules": [
			{"conditions": [{"type": "has_status"}],
			 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
		]},
	})
	assert_false(applied, "precondition: the import must be refused, or there is no reason to report")
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "a refusal must carry a reason the UI can show")
	assert_true(why.contains("rule 0"),
		"the reason must name WHICH rule, or a five-rule script gives the player nothing to fix: %s" % why)
	assert_true(why.contains("status"),
		"the reason must name the missing FIELD: %s" % why)


func test_a_refused_autogrind_import_reports_its_reason_too() -> void:
	var applied: bool = SSM.apply_autogrind_rules({
		"type": "autogrind_rules",
		"rules": [
			{"conditions": [{"type": "member_status", "member": "cleric", "value": 0}],
			 "actions": [{"type": "stop_grinding"}], "enabled": true},
		],
	})
	assert_false(applied, "precondition: a numeric status value must be refused")
	assert_true(SSM.last_import_reason().contains("member_status"),
		"the autogrind path must name its condition too: %s" % SSM.last_import_reason())


func test_a_successful_import_leaves_no_stale_reason() -> void:
	## The trap in carrying state across calls: a later success must not show the earlier failure's
	## message. Refuse once, then succeed, and check the reason cleared.
	SSM.apply_character_script("share_reason_probe", {
		"type": "autobattle_script",
		"script": {"rules": [{"conditions": [{"type": "has_status"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]},
	})
	assert_ne(SSM.last_import_reason(), "", "precondition: the first import failed and set a reason")

	var ok: bool = SSM.apply_character_script("share_reason_probe", {
		"type": "autobattle_script",
		"script": {"rules": [{"conditions": [{"type": "has_status", "status": "poison"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]},
	})
	assert_true(ok, "precondition: the corrected script imports")
	assert_eq(SSM.last_import_reason(), "",
		"a success must clear the reason — a stale one would caption the next success as a failure")


func test_multiple_bad_rules_are_summarised_not_truncated_silently() -> void:
	SSM.apply_character_script("share_reason_probe", {
		"type": "autobattle_script",
		"script": {"rules": [
			{"conditions": [{"type": "has_status"}], "actions": [{"type": "attack"}], "enabled": true},
			{"conditions": [{"type": "item_count", "op": ">", "value": 0}], "actions": [{"type": "attack"}], "enabled": true},
		]},
	})
	var why: String = SSM.last_import_reason()
	assert_true(why.contains("more"),
		"with several bad rules the player must learn there are others, not just the first: %s" % why)


## The manager computing a reason and the UI SHOWING it are two claims; every arm above tests the
## first. Derived rather than hand-listed: the scope is expressible — a file that decodes a share
## code is a paste path, whoever adds the next one.
func test_every_paste_path_can_say_why_it_refused() -> void:
	var checked: int = 0
	var mute: Array = []
	for path in _ui_files():
		var code: String = FileAccess.get_file_as_string(path)
		## Per file — a dark read decodes nothing and would leave this arm silently empty.
		assert_gt(code.length(), 50, "CONTROL: %s must actually be read" % path)
		if not code.contains("decode_share_code("):
			continue
		checked += 1
		if not code.contains("last_import_reason()"):
			mute.append(str(path).get_file())
	assert_gt(checked, 1, "CONTROL: expected more than one paste path, found %d" % checked)
	assert_eq(mute, [], "these decode a share code and cannot tell the player why one was refused: %s"
		% str(mute))


func _ui_files() -> Array:
	var out: Array = []
	var stack: Array = ["res://src/ui"]
	while not stack.is_empty():
		var dir: String = str(stack.pop_back())
		for d in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + str(d))
		for f in DirAccess.get_files_at(dir):
			if str(f).ends_with(".gd"):
				out.append(dir + "/" + str(f))
	return out
