extends GutTest

## Regression: Limit Break / Combo Magic gates must check PARTICIPANTS, not all
## alive players. Previously player1 (already-selected, spent AP) would block
## player3's Limit Break call because the gate iterated alive_players.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_limit_break_gate_iterates_participants() -> void:
	var text = _read(BATTLE_MANAGER_PATH)
	# Old shape iterated alive_players inside the limit_break branch.
	assert_eq(text.find("group_type == \"limit_break\":\n\t\tfor member in alive_players:"), -1,
		"Limit Break gate must NOT iterate alive_players (regression: blocked already-selected PCs).")
	# New shape: gate runs against participants array built earlier in the function.
	assert_true(text.find("group_type == \"limit_break\":\n\t\tfor member in participants:") != -1,
		"Limit Break gate must iterate participants.")


func test_combo_magic_gate_iterates_participants() -> void:
	var text = _read(BATTLE_MANAGER_PATH)
	assert_eq(text.find("group_type == \"combo_magic\":\n\t\tfor member in alive_players:"), -1,
		"Combo Magic AP gate must NOT iterate alive_players.")
	assert_true(text.find("group_type == \"combo_magic\":\n\t\tfor member in participants:") != -1,
		"Combo Magic AP gate must iterate participants.")


func test_combo_magic_element_pool_uses_participants() -> void:
	var text = _read(BATTLE_MANAGER_PATH)
	# Element-uniqueness gate previously used `_get_party_elements(alive_players)` —
	# already-acted PCs could satisfy the 2-element rule on behalf of non-participants.
	assert_eq(text.find("_get_party_elements(alive_players)"), -1,
		"Combo Magic element pool must NOT use alive_players (regression: full-party leak).")
	assert_true(text.find("_get_party_elements(participants)") != -1,
		"Combo Magic element pool must use participants.")


func test_participants_built_before_gates() -> void:
	var text = _read(BATTLE_MANAGER_PATH)
	var participants_pos := text.find("var participants: Array[Combatant] = []")
	var limit_pos := text.find("group_type == \"limit_break\":")
	var combo_pos := text.find("group_type == \"combo_magic\":")
	assert_true(participants_pos > -1, "participants array declaration must exist in player_group_attack")
	assert_true(limit_pos > participants_pos,
		"participants must be computed BEFORE the limit_break gate")
	assert_true(combo_pos > participants_pos,
		"participants must be computed BEFORE the combo_magic gate")
