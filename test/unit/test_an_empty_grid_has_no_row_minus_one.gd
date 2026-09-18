extends GutTest

## Pressing DOWN in a rule editor that has no rules yet drove the cursor to row -1, and the editor
## then indexed its own array at -1.
##
## ⛔ THE FIRST-TIME PATH. A character with no autobattle script has `rules == []`, so this is what
## the editor does the first time anyone opens it and presses down:
##
##     cursor_row = min(rules.size() - 1, cursor_row + 1)      -> min(-1, 1) == -1
##     cursor_col = min(cursor_col, _get_max_col_for_row(-1))  -> rules[-1]
##
## Both accessors in both editors guard ONE end only — `rules[cursor_row] if cursor_row <
## rules.size() else {}` — and -1 satisfies that test. Measured: a five-step stick ramp on an empty
## grid produced 20 "Out of bounds get index '-1' (on base: 'Array')" errors across the two files.
##
## ⚠️ ui_up was never affected, because it clamps with `max(0, cursor_row - 1)`. One direction was
## written defensively and the other was not, in both editors, which is why it survived: the editor
## works perfectly the moment a single rule exists, and every test fixture has rules.
##
## 🔑 THE ARM IS `cursor_row >= 0` AND NOT THE ACCESSOR'S RETURN, deliberately. An aborted GDScript
## function yields its return type's default, so `_get_max_col_for_row(-1)` returns 0 whether it
## aborted or was guarded — the two states are indistinguishable from the caller. The cursor index
## is the one observable that differs, so it is what the behavioural arms assert; the accessor
## guards are pinned by source below and labelled as source pins rather than dressed as behaviour.

const RAMP := [0.55, 0.65, 0.75, 0.85, 0.95]

const EDITORS := [
	{"name": "AutobattleGridEditor", "path": "res://src/ui/autobattle/AutobattleGridEditor.gd"},
	{"name": "AutogrindGridEditor", "path": "res://src/ui/autogrind/AutogrindGridEditor.gd"},
]


const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

## ⛔ STANDING UP A GRID EDITOR REGISTERS A PROFILE ON THE AutobattleSystem AUTOLOAD, and this file
## never names the field. The write is three calls down — editor -> get_character_script ->
## _ensure_character_profiles — keyed by whatever character_id the editor holds, "" when nothing
## sets one. Measured with a whole-surface probe: this file left entries behind for the rest of the
## process. Restore the CONTAINER, not the keys anyone thought of.
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func after_each() -> void:
	Input.action_release("ui_down")
	Input.action_release("ui_up")


func _motion(v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = v
	return e


func _send(m: Node, ev: InputEvent) -> void:
	assert_true(m.has_method("_input"), "the editor must define _input, or this arm drives nothing")
	m.call("_input", ev)


func _open(spec: Dictionary) -> Node:
	var m: Node = load(spec["path"]).new()
	add_child_autofree(m)
	await get_tree().process_frame
	return m


func test_a_dpad_press_down_on_an_empty_grid_never_leaves_row_minus_one() -> void:
	for spec in EDITORS:
		var ed: Node = await _open(spec)
		assert_eq((ed.get("rules") as Array).size(), 0,
			"CONTROL: %s must start with no rules, or this arm is not about the empty grid" % spec["name"])
		ed.set("cursor_row", 0)
		var e := InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_DPAD_DOWN
		e.pressed = true
		Input.action_press("ui_down", 1.0)
		_send(ed, e)
		Input.action_release("ui_down")
		assert_gte(int(ed.get("cursor_row")), 0,
			"%s put the cursor on row %d with an empty rule list — the editor then indexes rules[-1]"
			% [spec["name"], int(ed.get("cursor_row"))])


func test_a_stick_ramp_on_an_empty_grid_never_leaves_row_minus_one() -> void:
	for spec in EDITORS:
		var ed: Node = await _open(spec)
		ed.set("cursor_row", 0)
		Input.action_press("ui_down", 1.0)
		for v in RAMP:
			_send(ed, _motion(v))
		Input.action_release("ui_down")
		assert_gte(int(ed.get("cursor_row")), 0,
			"%s: a stick ramp on an empty grid left the cursor on row %d"
			% [spec["name"], int(ed.get("cursor_row"))])


## CONTROL: the same press with ONE rule must still move nothing, because there is nowhere to go.
## Without this, clamping to 0 could be satisfied by an editor whose cursor never moves at all.
func test_the_cursor_still_moves_when_there_are_rules() -> void:
	for spec in EDITORS:
		var ed: Node = await _open(spec)
		var rules: Array = ed.get("rules")
		for i in range(4):
			rules.append({"conditions": [], "actions": []})
		ed.set("cursor_row", 0)
		var e := InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_DPAD_DOWN
		e.pressed = true
		Input.action_press("ui_down", 1.0)
		_send(ed, e)
		Input.action_release("ui_down")
		assert_eq(int(ed.get("cursor_row")), 1,
			"%s did not step to row 1 with 4 rules present — the clamp must bound the cursor, "
			% spec["name"] + "not freeze it")


## SOURCE PINS, and they are source pins because behaviour cannot see them: an aborted accessor and
## a guarded one both yield 0 to the caller.
func test_both_accessors_guard_the_low_end() -> void:
	for spec in EDITORS:
		var src := FileAccess.get_file_as_string(spec["path"])
		assert_false(src.is_empty(), "%s must load" % spec["name"])
		# ⚠️ The pattern must exclude the FIXED form. My first version searched
		# "cursor_row < rules.size() else {}", which is a substring of the guarded spelling too, so
		# it went on failing after the repair — a pin that cannot be satisfied by the fix it demands.
		assert_eq(src.count("if cursor_row < rules.size() else {}"), 0,
			"%s still has an accessor guarding only the upper bound — -1 satisfies it" % spec["name"])
		assert_gt(src.count("if cursor_row >= 0 and cursor_row < rules.size()"), 0,
			"%s must guard the low end where it reads rules[cursor_row]" % spec["name"])
		assert_eq(src.count("if row_idx >= rules.size():"), 0,
			"%s still has a row accessor open at the low end" % spec["name"])
