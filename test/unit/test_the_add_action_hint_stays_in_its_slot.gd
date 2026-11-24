extends GutTest

## The grind rule editor's empty action slot ("[+R]") was built a full CELL_WIDTH wide, but _draw_rule_row advances only
## CELL_WIDTH / 2 + CELL_PADDING past it before placing the row's "[++]" insert button. So the hint ran under "[++]":
## at Text Size 2.0 the two labels touched with no gap, and at every size the hint's click overlay and the cursor
## frame (which sizes itself from the cell) covered the left of "[++]". The "+AND" hint beside it was already half-width.

const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const SCALES := [1.0, 2.0, 2.5]

var _ag_state: Dictionary
var _ab_profiles_entry: Dictionary = {}
var _saved_scale = null
var _vp: SubViewport = null
var _ed: Node = null


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_vp.add_child(_ed)
	await get_tree().process_frame


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null
	AutogrindSystem._test_disable_persistence = false
	AutogrindState.restore(_ag_state)


## One rule with a free action slot, so the row draws both the "[+R]" hint and the "[++]" insert button.
func _build(scale: float) -> void:
	GameState.text_size_scale = scale
	_ed.rules = [{
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "heal_party"}],
		"enabled": true,
	}]
	_ed._refresh_grid()
	await get_tree().process_frame


func _cell(kind: String) -> Control:
	for c in _ed._grid_container.get_children():
		if c is Control and not c.is_queued_for_deletion() and c.has_meta("cell_type") and str(c.get_meta("cell_type")) == kind:
			return c
	return null


## The cell's footprint as the player meets it: the widest of its own size, its children (background, label,
## click overlay), all in grid coordinates.
func _right_edge(cell: Control) -> float:
	var r: float = cell.position.x + maxf(cell.size.x, cell.custom_minimum_size.x)
	for ch in cell.get_children():
		if ch is Control:
			r = maxf(r, cell.position.x + (ch as Control).position.x + (ch as Control).size.x)
	return r


func _label(cell: Control) -> Label:
	for ch in cell.get_children():
		if ch is Label:
			return ch
	return null


func test_the_add_action_hint_ends_before_the_row_insert_button() -> void:
	for s in SCALES:
		await _build(s)
		var hint := _cell("empty_action")
		var ins := _cell("row_insert")
		assert_not_null(hint, "CONTROL @%s: the row drew an empty action hint" % s)
		assert_not_null(ins, "CONTROL @%s: the row drew a row insert button" % s)
		if hint == null or ins == null:
			continue
		assert_lte(_right_edge(hint), ins.position.x,
			"@%s: the [+R] hint (background, label and click area) ends at %.0f, under [++] which starts at %.0f"
			% [s, _right_edge(hint), ins.position.x])


func test_the_hint_label_is_whole_and_inside_its_slot() -> void:
	for s in SCALES:
		await _build(s)
		var hint := _cell("empty_action")
		var lbl := _label(hint) if hint else null
		assert_not_null(lbl, "CONTROL @%s: the hint has its label" % s)
		if lbl == null:
			continue
		var f: Font = lbl.get_theme_font("font")
		var px: int = lbl.get_theme_font_size("font_size")
		var w: float = f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		assert_lte(w, lbl.size.x, "@%s: '%s' at %d px is %.0f wide in a %.0f px label (clip_text would cut it)" % [s, lbl.text, px, w, lbl.size.x])
		assert_lte(lbl.position.x + lbl.size.x, maxf(hint.size.x, hint.custom_minimum_size.x),
			"@%s: the label stays inside the hint" % s)


func test_the_two_hints_share_one_width() -> void:
	## The +AND hint is the precedent the layout was written for; pinning the pair keeps them from drifting apart again.
	GameState.text_size_scale = 1.0
	_ed.rules = [{"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}], "actions": [{"type": "heal_party"}], "enabled": true}]
	_ed._refresh_grid()
	await get_tree().process_frame
	var a := _cell("empty_condition")
	var b := _cell("empty_action")
	assert_not_null(a, "CONTROL: the row drew a +AND hint")
	assert_not_null(b, "CONTROL: the row drew a [+R] hint")
	if a and b:
		assert_eq(b.custom_minimum_size.x, a.custom_minimum_size.x, "the [+R] hint is as wide as the +AND hint")
