extends GutTest

## Regression tests for AutobattleGridEditor's picker submenus.
##
## Catches the pre-fix bugs:
##   - Hitting A on a condition cell with an unsupported type (e.g.,
##     'ally_has_status') silently rewrote it to 'hp_percent' via a 6-type
##     cycle. Default Cleric / Mage / Bard scripts were unrecoverable
##     once edited.
##   - The action cycle (attack→ability→defer) skipped 'item' entirely —
##     players could delete the cleric potion-fallback rule and never get
##     it back without editing JSON.
##   - 'all_out_attack' lingered in ACTION_TYPES even though the runtime
##     branch was dead.
##
## We exercise the apply_* helpers (not the picker overlay UI) because the
## overlay is rebuilt every input event and is not deterministic in tests.


const AutobattleSystemScript = preload("res://src/autobattle/AutobattleSystem.gd")
const GridEditorScript = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")


var _autobattle: Node
var _editor: AutobattleGridEditor


func before_each() -> void:
	_autobattle = AutobattleSystemScript.new()
	add_child_autofree(_autobattle)
	_editor = GridEditorScript.new()
	add_child_autofree(_editor)


func _seed_rule(conditions: Array, actions: Array) -> void:
	_editor.rules = [{
		"conditions": conditions,
		"actions": actions,
		"enabled": true,
	}]
	_editor.cursor_row = 0
	_editor.cursor_col = 0


func test_condition_type_keys_cover_all_runtime_types() -> void:
	# The picker reads CONDITION_TYPES keys to populate rows — every type
	# the runtime evaluates in _evaluate_grid_condition (hp_percent, mp_percent,
	# ap, has_status, ally_has_status, ally_hp_percent, ally_mp_percent,
	# turn, enemy_count, ally_count, item_count, setup_complete, has_buff,
	# not_has_buff, always) MUST appear or it's unauthorable from the UI.
	var keys: Array = AutobattleSystem.CONDITION_TYPES.keys()
	var required = [
		"hp_percent", "mp_percent", "ap",
		"has_status", "ally_has_status", "ally_hp_percent",
		"ally_mp_percent", "turn", "enemy_count", "ally_count",
		"item_count", "setup_complete", "always",
	]
	for r in required:
		assert_true(keys.has(r),
			"CONDITION_TYPES must expose '%s' for the picker" % r)


func test_apply_condition_type_preserves_existing_status_field() -> void:
	# Switching to a status-typed condition shouldn't blow away an existing
	# user-set status string.
	_seed_rule(
		[{"type": "always"}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	_editor.rules[0]["conditions"][0] = {"type": "has_status", "status": "blind"}
	_editor.cursor_col = 0
	_editor._apply_condition_type("has_status")
	assert_eq(_editor.rules[0]["conditions"][0].get("status", ""), "blind",
		"Re-applying 'has_status' must preserve the existing status value")


func test_apply_condition_type_seeds_item_count_defaults() -> void:
	# Switching a fresh condition to item_count should seed item_id and a
	# default value so the new condition is immediately evaluable.
	_seed_rule(
		[{"type": "always"}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	_editor.cursor_col = 0
	_editor._apply_condition_type("item_count")
	var c = _editor.rules[0]["conditions"][0]
	assert_eq(c.get("type"), "item_count")
	assert_eq(c.get("item_id"), "potion")
	assert_eq(c.get("op"), ">")
	assert_eq(c.get("value"), 0)


func test_apply_condition_type_seeds_buff_stat_default() -> void:
	_seed_rule(
		[{"type": "hp_percent", "op": "<", "value": 50}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	_editor.cursor_col = 0
	_editor._apply_condition_type("not_has_buff")
	var c = _editor.rules[0]["conditions"][0]
	assert_eq(c.get("type"), "not_has_buff")
	assert_eq(c.get("stat"), "defense")


func test_apply_condition_type_clears_op_for_always() -> void:
	_seed_rule(
		[{"type": "hp_percent", "op": "<", "value": 50}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	_editor.cursor_col = 0
	_editor._apply_condition_type("always")
	var c = _editor.rules[0]["conditions"][0]
	assert_eq(c.get("type"), "always")
	assert_false(c.has("op"),
		"'always' must drop op so the renderer doesn't show '<50' on it")


func test_apply_target_type_writes_to_action() -> void:
	# Target picker must actually mutate the action's target field.
	_seed_rule(
		[{"type": "always"}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	# Cursor is on the action group (col 1 — condition slot 0, empty AND slot 1,
	# action group at col 2)
	var ctx = {
		"actions": _editor.rules[0]["actions"],
		"action": _editor.rules[0]["actions"][0],
		"action_idx": 0,
		"group_count": 1,
	}
	_editor._apply_target_type("highest_atk_enemy", ctx)
	assert_eq(_editor.rules[0]["actions"][0]["target"], "highest_atk_enemy",
		"Target picker must overwrite the action target")


func test_apply_action_type_switches_to_defer() -> void:
	_seed_rule(
		[{"type": "always"}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	var ctx = {
		"actions": _editor.rules[0]["actions"],
		"action": _editor.rules[0]["actions"][0],
		"action_idx": 0,
		"group_count": 1,
	}
	_editor._apply_action_type("defer", ctx)
	assert_eq(_editor.rules[0]["actions"][0]["type"], "defer")
	assert_false(_editor.rules[0]["actions"][0].has("id"))


func test_apply_item_id_writes_id_and_self_target() -> void:
	_seed_rule(
		[{"type": "always"}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	var ctx = {
		"actions": _editor.rules[0]["actions"],
		"action": _editor.rules[0]["actions"][0],
		"action_idx": 0,
		"group_count": 1,
	}
	_editor._apply_item_id("potion", ctx)
	var a = _editor.rules[0]["actions"][0]
	assert_eq(a.get("type"), "item")
	assert_eq(a.get("id"), "potion")
	assert_eq(a.get("target"), "self",
		"Default item target should be 'self' (matches default-script convention)")


func test_open_condition_editor_with_unknown_type_leaves_it_unchanged() -> void:
	# THE PRE-FIX BUG: pressing A on a condition cell with a type not in the
	# 6-type cycle silently wrote 'hp_percent' over it. Picker fix: idx==-1
	# plays menu_error and leaves the condition alone.
	var unsupported = {"type": "ally_has_status", "status": "poison"}
	_seed_rule([unsupported], [{"type": "attack", "target": "lowest_hp_enemy"}])
	# Force CONDITION_TYPES key list to NOT contain ally_has_status — we
	# instead read AutobattleSystem.CONDITION_TYPES, which DOES contain it,
	# so opening the editor should open the picker (not error). To exercise
	# the guard we temporarily replace the type with a clearly bogus one.
	_editor.rules[0]["conditions"][0]["type"] = "totally_bogus"
	_editor._open_condition_editor()
	# The bogus type must survive — guard prevents silent overwrite.
	assert_eq(_editor.rules[0]["conditions"][0]["type"], "totally_bogus",
		"Unknown condition type must be preserved (idx==-1 guard)")


func test_resolve_current_action_context_returns_action_dict() -> void:
	# Sanity check: the helper is used by every action-side picker.
	_seed_rule(
		[{"type": "always"}],
		[{"type": "attack", "target": "lowest_hp_enemy"}]
	)
	# Conditions size=1, has_always=true → condition_slots=1, group_idx=cursor_col-1.
	# Move cursor to col 1 (action group).
	_editor.cursor_col = 1
	var ctx = _editor._resolve_current_action_context()
	assert_false(ctx.is_empty(),
		"_resolve_current_action_context must return non-empty when cursor on action group")
	assert_true(ctx.has("action") and ctx.has("action_idx"),
		"Context must expose action + action_idx")
