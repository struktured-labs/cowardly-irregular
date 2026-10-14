extends GutTest

## Settings → the selection highlight stopped less than halfway across the row it was selecting.
##
## All six of SettingsMenu's row builders set `highlight.size = Vector2(400, row_h)` on a plain
## ColorRect. The rows live in a VBoxContainer with SIZE_EXPAND_FILL, which stretches each row to
## the panel width — about 1020px at 1280 — so the highlight covered 400 of it and the rest of the
## row sat outside the selection. On a wide options row the right-hand chips drew outside the
## highlight entirely, and the gap grows with Text Size, because the chips are scaled and the 400
## is not.
##
## Every sibling menu already anchors instead — JobMenu and AbilitiesMenu, four sites,
## `set_anchors_preset(Control.PRESET_FULL_RECT)` — which follows the row at any width and any
## text scale. SettingsMenu was the one screen that did not.
##
## 🛑 MEASURES THE BUILT SCENE. A source arm could assert "the literal 400 is gone" and would pass
## on any other wrong width; what the player sees is whether the blue box reaches the end of the
## row it is highlighting, so that is what is asserted.

const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")

## The row may be a hair wider than the highlight from rounding, but not a column.
const COVERAGE_SLACK := 1.0


func _menu() -> Control:
	var m = SettingsMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## Every built row that carries a Highlight, as [row, highlight] pairs.
func _rows(m: Control) -> Array:
	var out: Array = []
	for item in m._settings_items:
		var row: Control = item.get("control")
		if row == null:
			continue
		var hl := row.get_node_or_null("Highlight") as ColorRect
		if hl != null:
			out.append([row, hl, str(item.get("id", "?"))])
	return out


## CONTROL: the rows must actually be STRETCHED past the old literal, or this file proves nothing —
## a panel narrower than 400 would make a 400px highlight look correct and every arm pass.
func test_the_rows_are_wider_than_the_old_literal() -> void:
	var m = await _menu()
	var rows := _rows(m)
	assert_gt(rows.size(), 5, "PRECONDITION: Settings must build rows, got %d" % rows.size())
	var widest := 0.0
	for r in rows:
		widest = maxf(widest, (r[0] as Control).size.x)
	assert_gt(widest, 400.0,
		"CONTROL: the VBox must stretch rows past 400px or the defect cannot appear — widest %.0f"
		% widest)


## THE REGRESSION: the blue box must reach the end of the row it is highlighting.
func test_every_row_highlight_spans_its_row() -> void:
	var m = await _menu()
	var short: Array[String] = []
	for r in _rows(m):
		var row: Control = r[0]
		var hl: ColorRect = r[1]
		if hl.size.x < row.size.x - COVERAGE_SLACK:
			short.append("%s: highlight %.0f of %.0f" % [r[2], hl.size.x, row.size.x])
	assert_eq(short, [] as Array[String],
		"a Settings row's selection highlight stops short of the row it selects: %s"
		% [", ".join(short)])


## And nothing the row draws may sit OUTSIDE the selection — the chips are what the player is
## actually choosing between, and they are the part that overflowed a fixed 400.
func test_no_row_draws_its_options_outside_the_highlight() -> void:
	var m = await _menu()
	var outside: Array[String] = []
	var measured := 0
	for r in _rows(m):
		var row: Control = r[0]
		var hl: ColorRect = r[1]
		var opts := row.get_node_or_null("OptionsContainer") as Control
		if opts == null:
			continue
		measured += 1
		var right: float = opts.position.x + opts.size.x
		if right > hl.size.x + COVERAGE_SLACK:
			outside.append("%s: options reach %.0f, highlight %.0f" % [r[2], right, hl.size.x])
	assert_gt(measured, 2,
		"CONTROL: several rows must carry an OptionsContainer — only %d did, so this arm is "
		% measured + "measuring almost nothing")
	assert_eq(outside, [] as Array[String],
		"a Settings row draws its option chips outside its own selection highlight: %s"
		% [", ".join(outside)])
