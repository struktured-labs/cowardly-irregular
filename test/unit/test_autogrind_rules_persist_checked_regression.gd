extends GutTest

## set_autogrind_rules VALIDATES and refuses invalid input with NO mutation, returning false.
## Its docstring tells callers to check. Two of six call sites did not (audit for cowir-main,
## 2026-09-06, off cowir-controller's c930ec05):
##
##   AutogrindGridEditor._save_rules  emitted rules_saved REGARDLESS — a phantom success,
##                                    announcing a save that never happened
##   AutogrindUI grind start          started the grind on the PREVIOUS ruleset while the
##                                    player watched their edited rules on screen
##
## And closing the console never persisted at all, so edits made and then closed without
## starting a grind were dropped outright.

var _ui
var _editor
var _saved_emitted: int = 0


func before_each() -> void:
	_saved_emitted = 0
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_editor = preload("res://src/ui/autogrind/AutogrindGridEditor.gd").new()
	add_child_autofree(_editor)
	_editor.rules_saved.connect(func(_r) -> void: _saved_emitted += 1)


func _valid_rule() -> Dictionary:
	return {"conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}]}


func _invalid_rule() -> Dictionary:
	return {"conditions": [{"type": "no_such_condition_type"}], "actions": [{"type": "stop_grinding"}]}


func test_the_validator_actually_rejects_the_fixture() -> void:
	# ARM+. If this fixture were accepted, every rejection assertion below would be vacuous.
	assert_false(AutogrindSystem.set_autogrind_rules([_invalid_rule()]),
		"control: the invalid fixture must be REJECTED, else this file tests nothing")
	assert_true(AutogrindSystem.set_autogrind_rules([_valid_rule()]),
		"control: the valid fixture must be ACCEPTED")


func test_the_editor_does_not_announce_a_save_that_was_refused() -> void:
	_editor.rules = [_invalid_rule()]
	_editor._save_rules()
	assert_eq(_saved_emitted, 0,
		"rules_saved must NOT fire when the write was refused — that is a phantom success")


func test_the_editor_still_announces_a_real_save() -> void:
	# ARM+ for the above: proves the guard is scoped and did not mute the signal entirely.
	_editor.rules = [_valid_rule()]
	_editor._save_rules()
	assert_eq(_saved_emitted, 1, "a valid save must still emit rules_saved")


func test_closing_persists_valid_rules() -> void:
	## Closing was the console's only unpersisted exit.
	AutogrindSystem.set_autogrind_rules([])
	_ui.rules = [_valid_rule()]
	_ui._persist_rules_on_close()
	assert_eq(AutogrindSystem.get_autogrind_rules().size(), 1,
		"closing the console must persist the edited rules")


func test_closing_with_invalid_rules_does_not_wipe_the_saved_set() -> void:
	## No mutation on rejection — a mid-edit rule must not destroy the last good ruleset.
	AutogrindSystem.set_autogrind_rules([_valid_rule()])
	_ui.rules = [_invalid_rule()]
	_ui._persist_rules_on_close()
	assert_eq(AutogrindSystem.get_autogrind_rules().size(), 1,
		"a refused close-save must leave the previously saved rules intact")


func test_closing_is_never_blocked_by_a_refused_save() -> void:
	## The wedge invariant: closing must not depend on the state that broke. An incomplete
	## mid-edit rule must never trap the player in the console.
	var closed := [0]
	_ui.closed.connect(func() -> void: closed[0] += 1)
	_ui.rules = [_invalid_rule()]
	_ui.visible = true
	_ui._is_grinding = false
	_ui._close_ui()
	assert_eq(closed[0], 1, "a rejected save must still let the console close")


func test_the_seam_teardown_and_the_players_close_share_one_path() -> void:
	## @cowir-controller's save_and_close and the player's cancel must not grow separate persist
	## implementations — that is how the two drifted in the first place (reconciled 2026-09-06).
	AutogrindSystem.set_autogrind_rules([])
	_ui.rules = [_valid_rule()]
	_ui.save_and_close()
	assert_eq(AutogrindSystem.get_autogrind_rules().size(), 1,
		"save_and_close must persist through the same checked path as _close_ui")


func test_a_console_torn_down_before_its_rules_loaded_does_not_wipe_the_saved_set() -> void:
	## The empty-guard. A teardown that fires before _load_rules populates `rules` would
	## otherwise persist [] over the player's real ruleset — validation accepts an empty array,
	## so nothing would refuse it. Silent, total data loss at exactly the involuntary seam.
	AutogrindSystem.set_autogrind_rules([_valid_rule()])
	_ui.rules = []
	_ui.save_and_close()
	assert_eq(AutogrindSystem.get_autogrind_rules().size(), 1,
		"an empty in-memory ruleset must never overwrite the saved one")
