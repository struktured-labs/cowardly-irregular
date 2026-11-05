extends GutTest

## Since .766 the console's bottom strip rewrites itself on every cursor move (Delete / Operator / Undo), but it was anchored
## by the height it had when the console was BUILT. A word that wrapped the strip onto one more line at a large Text Size
## pushed that line off the bottom of the screen. The strip now re-anchors by its own height whenever its text changes.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _ag: Dictionary
var _scale_was: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


func _console(scale: float, box: Vector2) -> Node:
	GameState.text_size_scale = scale
	assert_true(AutogrindSystem.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "party_hp_avg", "op": "<", "value": 50}],
		 "actions": [{"type": "heal_party"}, {"type": "stop_grinding"}]},
	]), "FLOOR: the fixture's rule must be accepted")
	var ui: Node = load(UI).new()
	ui.size = box
	add_child_autofree(ui)
	## setup() is what loads the rules into the console; without it the grid is empty and there is no cell to move onto.
	ui.setup(_party())
	## Built with the cursor OFF a cell, as a stop leaves it (on "+ Add Rule"): the strip is anchored for its SHORT text.
	ui.cursor_row = ui.rules.size()
	ui.cursor_col = 0
	await wait_frames(3)
	return ui


func _party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": nm, "max_hp": 100, "max_mp": 50})
		out.append(c)
	return out


func _at(ui: Node, row: int, col: int) -> void:
	ui.cursor_row = row
	ui.cursor_col = col
	ui._update_cursor()


func _bottom(ui: Node) -> float:
	var f: Label = ui._footer_label
	return f.position.y + float(f.get_line_count() * f.get_line_height())


func _action_col(ui: Node) -> int:
	for col in 12:
		_at(ui, 0, col)
		if ui._cell_type_at_cursor() == "action":
			return col
	return -1


func test_the_strip_stays_on_screen_as_the_cursor_moves() -> void:
	var grew := 0
	var judged := 0
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		for box in [Vector2(1280, 720), Vector2(960, 720)]:
			var ui: Node = await _console(float(scale), box)
			assert_not_null(ui._footer_label, "CONTROL: the console built its strip")
			assert_eq(ui._cell_type_at_cursor(), "add_rule", "CONTROL: the console was built with the cursor off a cell")
			var lines_off: int = ui._footer_label.get_line_count()
			var col := _action_col(ui)
			assert_gt(col, -1, "CONTROL: the rule shows an action cell")
			if lines_off != ui._footer_label.get_line_count():
				grew += 1
			judged += 1
			assert_true(_bottom(ui) <= box.y + 0.5,
				"at %.2fx in %s the strip's last line ends at %.0f, past the screen's %.0f" % [float(scale), box, _bottom(ui), box.y])
			ui.queue_free()
			await wait_frames(1)
	assert_gt(judged, 3, "FLOOR: every Text Size step was judged")
	assert_gt(grew, 0, "CONTROL: at least one size and width must wrap the strip onto a new line when the cursor reaches a cell, or this arm proves nothing")
