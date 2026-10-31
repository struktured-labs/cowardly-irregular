extends GutTest

## The battle hint bar's LABEL scales (BattleScene:2156, TextScale.scaled(12)) and its PANEL does
## not: offsets -34/-6 are a hardcoded 28px, less 4+4 content margins = 20px of usable height.
## A 12px font draws ~17px, so 100% fits with 3px of slack and every larger preset does not.
##
## ⛔ AND THE DIRECTION IT FAILS IS THE POINT. :2126 sets grow_horizontal = BOTH, after someone
## measured a rendered frame and found the longest bar sitting 63.5px right of a preset named
## CENTER_BOTTOM (see test_battle_hint_bar_pad_family_regression:138-146). grow_vertical was never
## set, so it keeps the default END — DOWNWARD — on a panel anchored to the BOTTOM at offset -6.
## The fix for the horizontal twin is one line above the bug; this is its sibling.
##
## This bar is the LONG-TERM controls reference (tutorial hints fire once per session), so the
## player who most needs it is the one who turned the text up.

const SettingsMenuPath := "res://src/ui/SettingsMenu.gd"


## Through load().get_script_constant_map() so a RENAME reds this FLOOR by name. A const reach
## would resolve at PARSE time and take the whole file with it (EC=3, "nothing ran").
func _presets() -> Array:
	var consts: Dictionary = (load(SettingsMenuPath) as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve and hold more than one step, or every "
		+ "sweep below iterates nothing and passes having measured no preset at all")
	return p


func _saved_scale() -> float:
	return float(GameState.text_size_scale) if GameState else 1.0


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = 1.0


## Builds the REAL bar at a given scale and returns its measurements. Behavioural on the shipped
## panel: a source pin cannot see a layout property stop taking effect (the horizontal twin's note).
func _measure(scale: float) -> Dictionary:
	if GameState:
		GameState.text_size_scale = scale
	var scene: Node = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var bar := scene.get_node_or_null("UI/InputHintBar") as Control
	if bar == null:
		return {}
	var label := bar.get_node_or_null("HintLabel") as Label
	if label == null:
		return {}
	var fnt: Font = label.get_theme_font("font")
	var px: int = label.get_theme_font_size("font_size")
	return {
		"font": px,
		"drawn_h": fnt.get_height(px) if fnt else 0.0,
		"bar_h": bar.size.y,
		"bar_bottom": bar.position.y + bar.size.y,
		"parent_h": bar.get_parent_area_size().y,
	}


func test_the_hint_font_grows_at_every_preset() -> void:
	var seen: Array = []
	for s in _presets():
		var m: Dictionary = await _measure(float(s))
		assert_false(m.is_empty(), "PRECONDITION: the bar and its label must exist at %sx" % str(s))
		if m.is_empty():
			return
		seen.append(int(m["font"]))
	assert_gt(seen.size(), 1, "CONTROL: more than one preset must have been measured")
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1],
			"the hint font must GROW at every step, not only at 200%%: %s" % [seen])


func test_the_grown_bar_stays_on_screen() -> void:
	## The vertical twin of the centred arm: a bottom-anchored panel that grows DOWNWARD leaves
	## the viewport. Measured on the built node, never computed from the offsets.
	var bad: Array = []
	for s in _presets():
		var m: Dictionary = await _measure(float(s))
		if m.is_empty():
			continue
		if float(m["bar_bottom"]) > float(m["parent_h"]) + 0.5:
			bad.append("%sx: bottom %d past the %d-tall parent" %
				[str(s), int(m["bar_bottom"]), int(m["parent_h"])])
	assert_eq(bad, [],
		"the hint bar must stay inside the screen at every Text Size — grow_vertical must be "
		+ "GROW_DIRECTION_BEGIN on a CENTER_BOTTOM panel, or it grows off the bottom edge: %s" % [bad])


func test_the_bar_is_tall_enough_for_its_own_text() -> void:
	## The box must hold the line it draws. Measured on the BUILT label's font, not against a
	## literal, so a correct relayout cannot red this and a stale 28px cannot pass it.
	var bad: Array = []
	for s in _presets():
		var m: Dictionary = await _measure(float(s))
		if m.is_empty():
			continue
		if float(m["bar_h"]) + 0.5 < float(m["drawn_h"]):
			bad.append("%sx: %dpx box for a %dpx line" %
				[str(s), int(m["bar_h"]), int(m["drawn_h"])])
	assert_eq(bad, [], "the hint bar must be at least as tall as the text it draws: %s" % [bad])
