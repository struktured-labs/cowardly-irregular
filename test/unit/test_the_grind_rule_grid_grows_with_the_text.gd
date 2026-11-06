extends GutTest

## The autogrind rule grid drew its condition and action cells at a literal 11 px in fixed 120x44 cells, so Text Size never
## reached the screen where a player writes grind rules (controller census 22697, routed by main 22699). It now follows the
## autobattle twin's design (test_the_rule_grid_grows_with_the_text): fonts through TextScale, the width fixed, the HEIGHT
## derived by measuring every real cell through the same break rule the labels draw with. Fixed-box glyphs (AND, OR, +AND,
## [+R], [++], the row toggle) take the setting until it would leave their box. Arms: grows · fits · never spills · floor.

const GE := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Real formatters: a two-line cast, a member status, and ONE unbreakable token, without which WORD and WORD_SMART wrap alike.
const RULES: Array = [
	{"enabled": true,
	 "conditions": [{"type": "party_hp_min", "op": "<", "value": 30}, {"type": "member_status", "member": "cleric", "value": "petrification"}],
	 "actions": [{"type": "member_ability", "member": "cleric", "ability": "cure"}, {"type": "heal_party"}]},
	{"enabled": true,
	 "conditions": [{"type": "battles_done", "op": ">=", "value": 50}],
	 "actions": [{"type": "member_ability", "member": "mage", "ability": "unbreakablethaumaturgy"}]},
]
## Every cell one short line, so the authored 44 is held by the floor and nothing else.
const SHORT_RULES: Array = [
	{"enabled": true, "conditions": [{"type": "member_dead"}], "actions": [{"type": "stop_grinding"}]},
]

var _ag: Dictionary
var _saved: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


func _editor_at(scale: float, rules_in: Array = []) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var ed: Control = load(GE).new()
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ed)
	await get_tree().process_frame
	ed.setup()
	ed.rules = (rules_in if not rules_in.is_empty() else RULES).duplicate(true)
	ed._refresh_grid()
	await get_tree().process_frame
	await get_tree().process_frame
	return ed


## Every Label inside a grid cell, with its cell, plus the loose glyphs (OR) drawn straight on the grid.
func _grid_labels(ed: Control) -> Array:
	var out: Array = []
	for c in ed._grid_container.get_children():
		if c is Label and not (c as Node).is_queued_for_deletion():
			out.append({"cell": null, "label": c as Label})
		elif c is Control and (c as Control).has_meta("cell_type") and not (c as Node).is_queued_for_deletion():
			for l in (c as Control).get_children():
				if l is Label:
					out.append({"cell": c as Control, "label": l as Label})
	return out


## Read off the LABEL, never the subject's constant, so reverting the wrap mode changes what this measures.
func _break_flags_of(l: Label) -> int:
	match l.autowrap_mode:
		TextServer.AUTOWRAP_WORD:
			return TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		TextServer.AUTOWRAP_WORD_SMART:
			return TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		_:
			return TextServer.BREAK_MANDATORY


func _cell_label_px(ed: Control) -> int:
	for pair in _grid_labels(ed):
		var cell: Control = pair["cell"]
		if cell != null and str(cell.get_meta("cell_type")) in ["condition", "action"]:
			return int((pair["label"] as Label).get_theme_font_size("font_size"))
	return -1


func test_the_cell_font_grows_at_every_preset() -> void:
	var prev := -1
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		var px := _cell_label_px(ed)
		assert_gt(px, 0, "FLOOR: no condition/action cell was built at %sx" % scale)
		if prev > 0:
			assert_gt(px, prev, "the cell text did not grow from the step below %sx (%d -> %d)" % [scale, prev, px])
		prev = px


## The DRAWN text (line count x line height) fits its cell, at every preset.
func test_no_cell_text_overflows_its_cell_at_any_preset() -> void:
	var bad: Array = []
	var judged := 0
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		var h: float = float(ed._cell_h())
		for pair in _grid_labels(ed):
			var cell: Control = pair["cell"]
			if cell == null or not (str(cell.get_meta("cell_type")) in ["condition", "action"]):
				continue
			var l: Label = pair["label"] as Label
			judged += 1
			var drawn: float = float(l.get_line_count()) * float(l.get_line_height())
			if drawn > h:
				bad.append("%sx: '%s' draws %.0f in a %.0f cell" % [scale, l.text.replace("\n", "/"), drawn, h])
	assert_gt(judged, 20, "FLOOR: %d cell labels judged" % judged)
	assert_eq(bad, [], "cell text must fit its cell at every Text Size step: %s" % [bad])


## And sideways: a cell's text measured THROUGH its wrap, a fixed-box glyph (+AND, [+R], [++], AND, the toggle) by its width, against its cell.
func test_no_grid_text_spills_sideways_at_any_preset() -> void:
	var bad: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		for pair in _grid_labels(ed):
			var l: Label = pair["label"] as Label
			var fnt: Font = l.get_theme_font("font")
			var px: int = l.get_theme_font_size("font_size")
			if fnt == null:
				continue
			var cell: Control = pair["cell"]
			if cell != null and str(cell.get_meta("cell_type")) in ["condition", "action"]:
				var wrapped: float = fnt.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, l.size.x, px, -1, _break_flags_of(l)).x
				if wrapped > l.size.x + 1.0:
					bad.append("%sx: '%s' wraps to %.0f in %.0f" % [scale, l.text.replace("\n", "/"), wrapped, l.size.x])
			elif cell != null:
				var room: float = cell.custom_minimum_size.x - l.position.x
				var w: float = fnt.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
				if w > room + 1.0:
					bad.append("%sx: '%s' is %.0f wide with %.0f of room" % [scale, l.text, w, room])
	assert_eq(bad, [], "grid text must stay inside its box: %s" % [bad])


## The floor holds only in its own direction: no preset renders a cell under the authored 44, and the height never shrinks as the setting rises.
func test_the_cell_height_only_ever_grows() -> void:
	var consts: Dictionary = (load(GE) as GDScript).get_script_constant_map()
	var authored: int = int(consts.get("CELL_HEIGHT", -1))
	assert_gt(authored, 0, "FLOOR: the authored CELL_HEIGHT must still exist")
	var seen: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale), SHORT_RULES)
		var h: int = int(ed._cell_h())
		assert_gte(h, authored, "at %sx the cell height %d fell below the authored %d" % [scale, h, authored])
		seen.append(h)
	for i in range(1, seen.size()):
		assert_gte(int(seen[i]), int(seen[i - 1]), "the cell height shrank as Text Size rose: %s" % [seen])
