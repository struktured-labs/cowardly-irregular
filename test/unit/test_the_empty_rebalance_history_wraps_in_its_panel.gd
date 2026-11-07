extends GutTest

## The history panel's empty-state line ("No applied history yet…", shown on every save with no applied rebalance) set its
## text and size BEFORE autowrap, so the Label's width clamped to the whole unwrapped sentence and ran past the panel at
## EVERY Text Size (overworld's wrap-order scan 22866; the same trap autogrind 22854 / overworld 22858 / controller 22863
## hit). Judged on the BUILT Label against the box the panel gives it, never against the Label's own size.

const PanelScript := preload("res://src/ui/RebalanceHistoryPanel.gd")
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS

var _orig_scale: float = 1.0


func before_each() -> void:
	_orig_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _orig_scale


## The room the panel authors for this line: its width less the 40 px inset on each side.
func _room() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	return minf(720.0, vp.x - 80) - 80.0


func _built_panel():
	var panel = PanelScript.new()
	add_child_autofree(panel)
	return panel


func test_the_sentence_cannot_fit_one_line() -> void:
	var px: int = TextScale.scaled(PanelScript.EMPTY_FONT)
	var one_line: float = ThemeDB.fallback_font.get_string_size(PanelScript.EMPTY_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_gt(one_line, _room(), "CONTROL: unwrapped, the empty-state sentence is wider than its room, so the case is live")


func test_the_built_line_stays_in_its_room_at_every_text_size() -> void:
	assert_gt(PRESETS.size(), 1, "CONTROL: the Text Size ladder exists")
	var room: float = _room()
	for p in PRESETS:
		GameState.text_size_scale = float(p)
		var panel = _built_panel()
		var l: Label = panel._empty_label
		assert_not_null(l, "CONTROL: the panel builds its empty-state label")
		if l == null:
			return
		assert_eq(l.text, PanelScript.EMPTY_TEXT, "CONTROL: it holds the empty-state sentence")
		assert_lte(l.size.x, room + 0.5,
			"THE DEFECT: at %.2fx the empty-state line is %.0f px in %.0f px of room (it clamped to the unwrapped sentence)" % [float(p), l.size.x, room])
		assert_gt(l.get_line_count(), 1, "at %.2fx the sentence wraps rather than running on" % float(p))
		## The wrapped lines grow the Label DOWN; it draws exactly lines x font height (autogrind's probe 22941: no line gap).
		var px: int = TextScale.scaled(PanelScript.EMPTY_FONT)
		var drawn: float = l.get_line_count() * ThemeDB.fallback_font.get_height(px)
		assert_lt(l.position.y + drawn, panel._reset_btn.position.y,
			"at %.2fx the wrapped line (%.0f px tall) reaches the Reset button" % [float(p), drawn])
