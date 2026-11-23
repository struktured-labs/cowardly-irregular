extends GutTest

## PartyChatMenu and InnRestSequence's moon used literal fonts, so Text Size did nothing to them (cowir-cutscenes
## 2026-11-06, controller's census 22685 / main 22699). The menu is built per open: its geometry now grows with its fonts
## and its height is clamped to the screen (the list scrolls). Arms per CLAUDE.md: the font grows at EVERY preset, the
## grown text fits the BUILT panel, the panel stays on screen. The corpus is every party chat, unlocked here.

const MENU := preload("res://src/ui/PartyChatMenu.gd")
const INN := preload("res://src/cutscene/InnRestSequence.gd")

var _held_constants: Dictionary = {}
var _saved_scale: float = 1.0


func before_each() -> void:
	_held_constants = GameState.game_constants.duplicate(true)
	_saved_scale = float(GameState.text_size_scale)
	for id in PartyChatSystem.REGISTRY:
		for flag in (PartyChatSystem.REGISTRY[id] as Dictionary).get("unlock", []):
			GameState.game_constants[str(flag)] = true


func after_each() -> void:
	GameState.game_constants = _held_constants
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func _open(scale: float) -> Control:
	GameState.text_size_scale = scale
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var menu = MENU.new()
	layer.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


func _px(l: Label) -> int:
	return l.get_theme_font_size("font_size")


func _width(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(l)).x


func _readout_px(scale: float) -> int:
	GameState.text_size_scale = scale
	return INN.readout_px()


func test_the_corpus_was_read() -> void:
	assert_gt(_presets().size(), 2, "floor: the Text Size ladder was read")
	var menu = await _open(1.0)
	assert_gt(menu._row_nodes.size(), 10, "CONTROL: every chat unlocked here shows as a row (%d)" % menu._row_nodes.size())


func test_every_font_grows_at_every_preset() -> void:
	var last: Array = []
	for p in _presets():
		var menu = await _open(float(p))
		var now: Array = [_px(menu._title_label), _px(menu._hint_label), _px(menu._row_nodes[0]), _readout_px(float(p))]
		if not last.is_empty():
			for i in now.size():
				assert_gt(now[i], last[i], "font %d (title/hint/row/the inn's readout pixel) grows past %d at Text Size %s" % [i, last[i], p])
		last = now


func test_the_grown_text_fits_the_built_panel() -> void:
	for p in _presets():
		var menu = await _open(float(p))
		var title: Label = menu._title_label
		var hint: Label = menu._hint_label
		## Judged against the PANEL's inner width, not the label's: a Label with trimming off grows its own size to its
		## text, so `size.x` always holds it and an arm against it can never fail (cowir-controller 22795).
		var inner: float = (title.get_parent() as Control).size.x - 2.0 * title.position.x
		assert_lte(_width(title), inner, "the title fits inside the panel at Text Size %s" % p)
		assert_lte(_width(hint), inner, "the control hint fits inside the panel at Text Size %s (%.0f > %.0f)" % [p, _width(hint), inner])
		assert_lte(hint.position.y + hint.get_theme_font("font").get_height(_px(hint)), menu._ph,
			"the hint stays inside the panel at Text Size %s" % p)
		var widest := 0.0
		for row in menu._row_nodes:
			row.text = "▸ " + str(row.text).strip_edges()
			widest = maxf(widest, _width(row))
		assert_lte(widest, menu._scroll.size.x, "the widest selected chat title fits the list at Text Size %s" % p)


func test_the_panel_stays_on_screen() -> void:
	for p in _presets():
		var menu = await _open(float(p))
		var panel: Control = menu._title_label.get_parent()
		var vp: Vector2 = menu.get_viewport_rect().size
		assert_gte(panel.position.y, 0.0, "the panel's top is on screen at Text Size %s" % p)
		assert_lte(panel.position.y + panel.size.y, vp.y, "the panel's bottom is on screen at Text Size %s" % p)
		assert_lte(panel.position.x + panel.size.x, vp.x, "the panel's right edge is on screen at Text Size %s" % p)


func test_the_default_size_is_the_authored_menu() -> void:
	GameState.text_size_scale = 1.0
	for v in [12.0, 20.0, 28.0, 36.0, 420.0, 520.0]:
		assert_eq(MENU.k(v), v, "%.0f is unchanged at 1.0x" % v)
