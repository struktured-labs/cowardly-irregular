extends GutTest

## Simulate answers "what does this grid actually DO?" The grid the player is editing lives on
## the editor. _open_simulate used to ignore it and read the last SAVED script, so changing an
## HP threshold with W/S and pressing R described the old number. The fight, after the editor
## closes and saves, then did the new one. The panel and the cells disagreed.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const CID := "sim_open_grid"

const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
var _ab_profiles_entry: Dictionary = {}
var _saved_persist: bool = false


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	AutobattleSystem.reset_rule_fire_counts(CID)


func after_each() -> void:
	AutobattleSystem.reset_rule_fire_counts(CID)
	AutobattleSystem._test_disable_persistence = _saved_persist


func _hp_rule(threshold: int) -> Dictionary:
	return {
		"enabled": true,
		"conditions": [{"type": "hp_percent", "op": "<", "value": threshold}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
	}


func _save_script(threshold: int) -> void:
	AutobattleSystem.set_character_script(CID, {
		"character_id": CID,
		"name": "Saved",
		"rules": [_hp_rule(threshold)],
	})


func _editor_showing(threshold: int) -> Node:
	var editor: Node = load(EDITOR).new()
	editor.character_id = CID
	editor.rules = [_hp_rule(threshold)]
	add_child_autofree(editor)
	return editor


func _panel_lines(editor: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var panel: Node = editor.get("_simulate_panel")
	if panel != null:
		_collect_labels(panel, out)
	return out


func _collect_labels(node: Node, out: PackedStringArray) -> void:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_collect_labels(child, out)


func _line_starting(lines: PackedStringArray, prefix: String) -> String:
	for line in lines:
		if line.begins_with(prefix):
			return line
	return ""


func test_simulate_describes_the_threshold_on_screen_not_the_last_save() -> void:
	# Saved script heals... attacks under 30. The open grid says under 80, and nothing has saved that.
	# Half HP is 50: under 30 does not fire, under 80 does. That one line is the whole defect.
	_save_script(30)
	var editor := _editor_showing(80)
	editor._open_simulate()
	var half := _line_starting(_panel_lines(editor), "half HP")
	assert_true(half.contains("rule 1 fires"),
		"half HP must follow the open grid (HP < 80), not the saved HP < 30. Got: '%s'" % half)
	var saved_rules: Array = AutobattleSystem.get_character_script(CID).get("rules", [])
	var saved_value: int = int((saved_rules[0] as Dictionary)["conditions"][0]["value"])
	assert_eq(saved_value, 30,
		"Simulate is a preview — it must not write the unsaved threshold back into the save")
	var full := _line_starting(_panel_lines(editor), "full HP")
	assert_true(full.contains("no rule matches"),
		"full HP must still miss HP < 80, or the readout is matching every state: '%s'" % full)


func test_an_unedited_grid_still_shows_fight_counts() -> void:
	# The companion: when the grid and the save agree, counts recorded this session still belong
	# on the panel. A match check that always says "unsaved" would hide them.
	_save_script(30)
	var editor := _editor_showing(30)
	AutobattleSystem._rule_eval_counts[CID] = 4
	AutobattleSystem._rule_fire_counts[CID] = {0: 3}
	editor._open_simulate()
	var text := "\n".join(_panel_lines(editor))
	assert_true(text.contains("fired 3"),
		"an unedited grid must still show how often the rule fired. Got:\n%s" % text)
	assert_false(text.contains("unsaved"),
		"an unedited grid is not unsaved. Got:\n%s" % text)
