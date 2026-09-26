extends GutTest

## The editor legend says T:Target. T called _is_on_action_group(), which is true only when
## the same action is repeated (Attack ×2) — that predicate exists so L can split the group.
## A normal one-action cell, which is every rule a player writes before they queue a repeat,
## played the error sound and left the aim unchanged. The buried More Actions row already
## opened the picker for that cell, so the advertised key was the one that did not.

const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _editor: Node = null
var _saved_persist: bool = false
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_editor = load(ED).new()
	add_child_autofree(_editor)
	_editor.setup("hero", "Hero")
	await get_tree().process_frame


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist


func _press_t() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.pressed = true
	_editor._input(ev)


func _aim_power_strike() -> void:
	_editor.rules = [{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "ability", "id": "power_strike", "target": "lowest_hp_enemy"}],
		"enabled": true,
	}]
	_editor.cursor_row = 0
	## ALWAYS occupies column 0, so the single action is column 1.
	_editor.cursor_col = 1


func test_t_opens_the_target_picker_on_a_single_action() -> void:
	_aim_power_strike()
	_press_t()
	assert_not_null(_editor._option_picker,
		"T on a one-action cell must open the target picker — the legend says T:Target, and this is the cell a player is on before they queue a repeat")
	if _editor._option_picker == null:
		return
	var spec: Dictionary = _editor._option_picker.get_meta("spec")
	assert_eq(str(spec.get("kind", "")), "target_type",
		"the picker T opens must be the target list, not some other overlay")
	assert_eq(_editor.rules[0]["actions"][0].get("target", ""), "lowest_hp_enemy",
		"opening the picker must not rewrite the aim")


## The key that worked before was a repeated action. It has to keep working.
func test_t_still_opens_the_target_picker_on_a_repeated_action() -> void:
	_editor.rules = [{
		"conditions": [{"type": "always"}],
		"actions": [
			{"type": "attack", "target": "highest_hp_enemy"},
			{"type": "attack", "target": "highest_hp_enemy"},
		],
		"enabled": true,
	}]
	_editor.cursor_row = 0
	_editor.cursor_col = 1
	_press_t()
	assert_not_null(_editor._option_picker,
		"T on a repeated action (Attack ×2) must still open the target picker")


## T on the condition must not invent a target picker. That column has no aim.
func test_t_on_a_condition_does_not_open_the_target_picker() -> void:
	_aim_power_strike()
	_editor.cursor_col = 0
	_press_t()
	assert_null(_editor._option_picker,
		"T on a condition cell has no action to aim, so it must not open the target picker")
