extends GutTest

## The autobattle editor's flash line ("Imported <file>. Undo: Ctrl+Z, or Ⓨ on an empty slot") was one unwrapped
## line, 18 px tall, sitting directly on the legend strip. At Text Size 2.0 the cell font takes the face's 3x step, so
## a 28+ character file name ran past BOTH screen edges (the label is centered), and even one line was taller than
## its box. It now wraps at its width and grows UP from the legend.
##
## ⛔ The arms measure with the LABEL's own line layout (get_line_count x get_line_height), never with a width-limited
## font query: that is how the fix places the label, so it would agree with any bug in it.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const LONG := "Imported bram_aggressive_lategame_backup_v2.json. Undo: Ctrl+Z, or Ⓨ on an empty slot"
const SHORT := "Deleted. Undo: Ctrl+Z"

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
	GameState.text_size_scale = scale
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	_vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame


func _flash(text: String) -> Label:
	_ed._flash_status(text)
	await get_tree().process_frame
	return _ed._flash_label


func _legend_top() -> float:
	return _ed.size.y - float(_ed._legend_h)  # the strip as laid out; it grows up when its lines wrap


func _check(l: Label, tag: String) -> void:
	var lines: int = l.get_line_count()
	var drawn_h: float = lines * l.get_line_height()
	assert_gt(lines, 0, "CONTROL %s: the label laid its text out" % tag)
	assert_lte(drawn_h, l.size.y + 0.5, "%s: %d line(s) x %d px fit the label's %.0f px height" % [tag, lines, l.get_line_height(), l.size.y])
	assert_lte(l.position.y + l.size.y, _legend_top(), "%s: the message ends above the legend strip (%.0f <= %.0f)" % [tag, l.position.y + l.size.y, _legend_top()])
	assert_gte(l.position.x, 0.0, "%s: starts on screen" % tag)
	assert_lte(l.position.x + l.size.x, _ed.size.x, "%s: ends on screen" % tag)
	assert_gt(l.position.y, float(load(ED).GRID_BASE_POS.y), "%s: stays below the grid's top" % tag)


func test_a_long_file_name_wraps_on_screen_at_2x() -> void:
	await _open(2.0)
	var l := await _flash(LONG)
	var px: int = l.get_theme_font_size("font_size")
	var one_line: float = l.get_theme_font("font").get_string_size(LONG, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_gt(one_line, l.size.x, "CONTROL: on one line the message is wider than the screen (%.0f > %.0f), so it must wrap" % [one_line, l.size.x])
	assert_gt(l.get_line_count(), 1, "the long message wraps onto more than one line")
	_check(l, "@2.0 long")


func test_every_flash_clears_the_legend_at_each_text_size() -> void:
	for s in [1.0, 1.25, 2.0, 2.5]:
		await _open(s)
		for t in [SHORT, LONG]:
			_check(await _flash(t), "@%s '%s'" % [s, t.substr(0, 12)])
		_ed.queue_free()


func test_a_short_message_stays_one_line() -> void:
	await _open(1.0)
	var l := await _flash(SHORT)
	assert_eq(l.get_line_count(), 1, "a short message is not broken up")
