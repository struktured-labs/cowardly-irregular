extends GutTest

## The autobattle rule grid ends each row with small cells: the "+AND" / "+ACTION" empty slots, the "[++]" row insert
## and the "[ON]/[OFF]" toggle. They had fixed widths, and the "+ACTION" slot was built a full CELL_WIDTH wide while the
## row advanced only half a cell past it. At Text Size 2.0 the 2.0 frame read "+ACTI[++]" (the slot ran under [++]);
## at 2.0 / 2.5 the face's 2x / 3x step also made "+ACTION", "[++]", "[OFF]" and (at 2.5) "+AND" wider than their
## labels. Each tail cell is now as wide as its text needs (never narrower than before), and the row advances by it.
##
## ⛔ Fit is judged with the LABEL's own minimum size (a non-wrapping Label's minimum width is its text's), not with the
## font query the fix uses to size the cell.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const SCALES := [1.0, 2.0, 2.5]
const TAIL := ["empty_condition", "empty_action", "row_insert", "row_toggle"]
## One condition and one action (room for both empty slots), and a disabled row so "[OFF]" is drawn too.
const FIXTURE := [
	{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	{"conditions": [{"type": "hp_percent", "op": "<", "value": 30}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": false},
]

var _ed: Control = null
var _vp: SubViewport = null
var _saved_persist := false
var _saved_scale = null
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	GameState.text_size_scale = _saved_scale
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _open(scale: float) -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	GameState.text_size_scale = scale
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	_vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	(_ed.rules as Array).assign(FIXTURE.duplicate(true))
	_ed._refresh_grid()
	await get_tree().process_frame


## Every cell of one row (anything carrying cell_type), left to right.
func _row_cells(row: int) -> Array:
	var out: Array = []
	for c in _ed._grid_container.get_children():
		if c is Control and not c.is_queued_for_deletion() and c.has_meta("cell_type") and int(c.get_meta("row")) == row:
			out.append(c)
	out.sort_custom(func(a, b) -> bool: return a.position.x < b.position.x)
	return out


## What the player meets: the cell's own width and every child's (background, label, borders, click overlay).
func _right_edge(c: Control) -> float:
	var r: float = c.position.x + maxf(c.size.x, c.custom_minimum_size.x)
	for ch in c.get_children():
		if ch is Control:
			r = maxf(r, c.position.x + (ch as Control).position.x + (ch as Control).size.x)
	return r


func _label(c: Control) -> Label:
	for ch in c.get_children():
		if ch is Label:
			return ch
	return null


func test_no_row_cell_runs_under_the_next() -> void:
	for s in SCALES:
		await _open(s)
		for row in FIXTURE.size():
			var cells := _row_cells(row)
			var kinds: Array = cells.map(func(c) -> String: return str(c.get_meta("cell_type")))
			for k in TAIL:
				assert_true(kinds.has(k), "CONTROL @%s row %d: the row drew its %s cell (%s)" % [s, row, k, kinds])
			for i in range(cells.size() - 1):
				assert_lte(_right_edge(cells[i]), cells[i + 1].position.x,
					"@%s row %d: %s ends at %.0f, under %s at %.0f" % [s, row, kinds[i], _right_edge(cells[i]), kinds[i + 1], cells[i + 1].position.x])


func test_every_tail_label_is_whole() -> void:
	for s in SCALES:
		await _open(s)
		var seen := 0
		for row in FIXTURE.size():
			for c in _row_cells(row):
				if not TAIL.has(str(c.get_meta("cell_type"))):
					continue
				var l := _label(c)
				assert_not_null(l, "CONTROL @%s: %s has a label" % [s, c.get_meta("cell_type")])
				if l == null:
					continue
				seen += 1
				assert_lte(l.get_minimum_size().x, l.size.x,
					"@%s: '%s' needs %.0f px in a %.0f px label" % [s, l.text, l.get_minimum_size().x, l.size.x])
				assert_lte(l.position.x + l.size.x, c.custom_minimum_size.x + 0.5, "@%s: '%s' stays inside its cell" % [s, l.text])
		assert_eq(seen, 8, "CONTROL @%s: 4 tail labels on each of 2 rows were judged" % s)


func test_the_default_size_keeps_the_old_widths() -> void:
	## At 1.0 the floors hold: +AND, [++] and [ON]/[OFF] keep their old widths, and +ACTION gets the half cell the row
	## always advanced past (it was drawn 110 wide over [++] even at 1.0). So the row's positions at 1.0 are unchanged.
	await _open(1.0)
	var want := {"empty_condition": 55.0, "empty_action": 55.0, "row_insert": 40.0, "row_toggle": 50.0}
	for c in _row_cells(0):
		var k := str(c.get_meta("cell_type"))
		if want.has(k):
			assert_eq(c.custom_minimum_size.x, want[k], "@1.0 %s is %.0f wide, its floor" % [k, want[k]])
