extends GutTest

## The grind Dashboard drew all 20 of its font sizes as literals, so Text Size never reached it (routed by cowir-main 22699).
## It is a full-screen layout of fixed bands (header, panel titles, ~20 px stat rows, a 20 px battle-log view), so each label now
## takes the setting only until its own longest real text would leave its band. Arms: grows where there is room · nothing
## collides or leaves its panel at any preset, with the widest real content on screen · 100% keeps the authored sizes.

const DASHBOARD := "res://src/ui/autogrind/AutogrindDashboard.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

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


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


## The widest content the Dashboard shows: big numbers, PAUSED, LUDICROUS, permadeath ON, a full log, a five-line readout.
func _dashboard_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	## Hosted in a 1280x720 SubViewport: the Dashboard lays out from its viewport, and a bare host can measure 2560x1440,
	## where the ~20 px rows double and no cap ever binds (main 23143). The CONTROL below proves the screen is the player's.
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var d: Control = load(DASHBOARD).new()
	d.size = Vector2(1280, 720)
	vp.add_child(d)
	await wait_frames(3)
	assert_eq(d.get_viewport().get_visible_rect().size, Vector2(1280, 720), "CONTROL: the Dashboard is laid out on the player's 1280x720 screen")
	d.refresh({"battles_won": 9999, "total_exp": 9999999, "total_gold": 9999999, "consecutive_wins": 999}, "")
	d.set_paused(true)
	d.set_ludicrous_mode(true)
	for i in 4:
		d.add_battle_result(i % 2 == 0, 99, 99999)
	d._readout_round = 99
	d._readout_action = "Cleric casts Anima Reddita on the Fighter"
	d._readout_last_hit = "Fighter hits Glacius for 9999"
	d._refresh_battle_readout()
	await wait_frames(2)
	return d


func _labels(n: Node, acc: Array) -> Array:
	if n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text).strip_edges() != "" and not (n as Node).is_queued_for_deletion():
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)
	return acc


func _rect(l: Label) -> Rect2:
	return Rect2(l.position, l.get_minimum_size())


func _row_px(d: Control, text: String) -> int:
	for l in _labels(d, []):
		if (l as Label).text == text:
			return (l as Label).get_theme_font_size("font_size")
	return -1


func test_the_stat_rows_grow_where_they_have_room() -> void:
	var seen: Array = []
	for scale in _presets():
		var d: Control = await _dashboard_at(float(scale))
		var px := _row_px(d, "Items Used:")
		assert_gt(px, 0, "FLOOR: the 'Items Used:' row was built at %sx" % scale)
		seen.append(px)
	var at100: int = int(seen[_presets().find(1.0)])
	var at125: int = int(seen[_presets().find(1.25)])
	assert_gt(at125, at100, "a stat row must GROW from 100%% to 125%% where its row has room: %s across %s" % [seen, _presets()])
	for i in range(1, seen.size()):
		assert_gte(int(seen[i]), int(seen[i - 1]), "a stat row shrank as Text Size rose: %s" % [seen])


func test_nothing_collides_or_leaves_its_panel_at_any_preset() -> void:
	var bad: Array = []
	var judged := 0
	for scale in _presets():
		var d: Control = await _dashboard_at(float(scale))
		var by_parent: Dictionary = {}
		for l in _labels(d, []):
			var parent: Control = (l as Label).get_parent() as Control
			if parent == null:
				continue
			judged += 1
			var r := _rect(l)
			if parent == d and r.position.y < 44.0 and r.end.y > 44.0:
				bad.append("%sx: header '%s' runs below the header (ends %.0f)" % [scale, (l as Label).text, r.end.y])
			if parent != d and not (parent is VBoxContainer) and parent.size.x > 0.0 and not Rect2(Vector2.ZERO, parent.size).encloses(r):
				bad.append("%sx: '%s' %s leaves its %s panel" % [scale, str((l as Label).text).left(24), r, parent.size])
			if parent is VBoxContainer and r.size.y > (parent.get_parent() as Control).size.y + 0.5:
				bad.append("%sx: log line '%s' is %.0f tall in a %.0f view" % [scale, (l as Label).text, r.size.y, (parent.get_parent() as Control).size.y])
			var k := parent.get_instance_id()
			if not by_parent.has(k):
				by_parent[k] = []
			by_parent[k].append(l)
		for k in by_parent:
			var g: Array = by_parent[k]
			if (g[0] as Node).get_parent() is VBoxContainer:
				continue
			for i in g.size():
				for j in range(i + 1, g.size()):
					if _rect(g[i]).intersects(_rect(g[j])):
						bad.append("%sx: '%s' overlaps '%s'" % [scale, str((g[i] as Label).text).left(20), str((g[j] as Label).text).left(20)])
	assert_gt(judged, 100, "FLOOR: %d labels judged across the presets" % judged)
	assert_eq(bad, [], "the Dashboard drew text outside its room: %s" % [bad])


func test_100_percent_keeps_the_authored_sizes() -> void:
	var d: Control = await _dashboard_at(1.0)
	assert_eq(_row_px(d, "AUTOGRIND DASHBOARD"), 14, "the title stays 14 px at 100%")
	assert_eq(_row_px(d, "Items Used:"), 11, "a stat row stays 11 px at 100%")
	assert_eq(_row_px(d, "SESSION STATS"), 10, "a panel title stays 10 px at 100%")
