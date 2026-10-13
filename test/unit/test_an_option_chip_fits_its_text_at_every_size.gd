extends GutTest

## Settings rows scaled their FONTS with the Text Size setting and kept every position and box as a
## literal, so raising Text Size pushed the option values outside their own coloured chips and the
## description through the options row.
##
## Measured against the real rows before the fix (+ = overflow, - = clearance):
##
##            desc/options overlap   option text vs its chip
##   80%            -4 px                   -10 px
##   100%           -2 px                    -3 px
##   125%           +2 px                    +8 px
##   150%           +6 px                   +15 px
##   200%          +12 px                   +33 px     <- 73px of text in a 40px box
##
## So this is reachable by one accessibility setting, with nothing else changed, and it gets worse
## the more a player needs the larger text.
##
## `test_menu_chrome_visible_at_every_text_size_regression` already drives this menu at all five
## presets — it asserts the header and footer stay on screen and says nothing about the ROWS, which
## is the gap these arms fill.
##
## ⚠️ THREE BUILDERS make option rows, and patching two of them left the overlap exactly as it was
## because the third kept its literal. `_create_option_setting`, `_create_volume_setting` and
## `_create_option_setting_small` are all swept here BY STRUCTURE — any row carrying an
## "OptionsContainer" — rather than by naming the builders, so a fourth one cannot be missed.

const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
const LABELS: Array = ["80%", "100%", "125%", "150%", "200%"]

var _menu: Control = null
var _orig_scale: float = 1.0


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	## His setting, not the test's. Leaving 200% behind would change the menus of every later arm
	## in the process.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale
	_menu = null


func _build_at(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale
	_menu = SettingsMenuScript.new()
	_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu.position = Vector2.ZERO
	_menu.size = Vector2(1280, 720)
	add_child_autofree(_menu)
	await wait_frames(3)


## Every row that carries an options strip, whichever builder made it.
func _option_rows() -> Array:
	var out: Array = []
	var stack: Array = [_menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Control and n.get_node_or_null("OptionsContainer") != null:
			out.append(n)
	return out


func _content_w(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	if f == null:
		return 0.0
	var fs: int = l.get_theme_font_size("font_size")
	if fs <= 0:
		fs = 10
	return f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _line_h(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	if f == null:
		return 0.0
	var fs: int = l.get_theme_font_size("font_size")
	if fs <= 0:
		fs = 10
	return f.get_height(fs)


## [label, description] of a row, in the order the builders add them.
func _label_and_desc(row: Control) -> Array:
	var out: Array = []
	for c in row.get_children():
		if c is Label:
			out.append(c)
		if out.size() == 2:
			break
	return out


func _chips_of(row: Control) -> Array:
	var out: Array = []
	var oc := row.get_node_or_null("OptionsContainer") as Control
	if oc == null:
		return out
	for ob in oc.get_children():
		if ob is Control and (ob as Control).get_child_count() > 0:
			for ol in ob.get_children():
				if ol is Label:
					out.append({"chip": ob, "label": ol})
	return out


func test_control_the_menu_builds_option_rows_at_every_size() -> void:
	## Without rows, every arm below passes on an empty sweep.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		assert_gt(_option_rows().size(), 0,
			"Text Size %s must still build option rows" % [LABELS[i]])


func test_control_the_option_font_actually_grows_with_the_setting() -> void:
	## The premise. If the option labels did not scale, nothing here could overflow and the whole
	## file would be guarding a constant.
	await _build_at(1.0)
	var small := 0
	for row in _option_rows():
		for pair in _chips_of(row):
			small = maxi(small, (pair["label"] as Label).get_theme_font_size("font_size"))
	await _build_at(2.0)
	var big := 0
	for row in _option_rows():
		for pair in _chips_of(row):
			big = maxi(big, (pair["label"] as Label).get_theme_font_size("font_size"))
	assert_gt(small, 0, "CONTROL: option labels must carry a font size at 100%")
	assert_gt(big, small,
		"CONTROL: the option font must grow with Text Size (100%% -> %d, 200%% -> %d)" % [small, big])


func test_an_option_value_is_never_wider_than_its_chip() -> void:
	## THE DEFECT. A chip sized for 100% held 73px of text at 200% — the value drew over its
	## neighbour and outside its own coloured box.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		for row in _option_rows():
			for pair in _chips_of(row):
				var chip := pair["chip"] as Control
				var l := pair["label"] as Label
				assert_lte(_content_w(l), chip.size.x,
					"Text Size %s: option '%s' needs %.0f px in a %.0f px chip" % [
						LABELS[i], l.text, _content_w(l), chip.size.x])


func test_the_description_does_not_reach_the_options_row() -> void:
	## The other half: the options strip sat at a literal y under a description whose font scales.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		for row in _option_rows():
			var pair: Array = _label_and_desc(row)
			if pair.size() < 2:
				continue
			var desc := pair[1] as Label
			var oc := row.get_node_or_null("OptionsContainer") as Control
			if oc == null:
				continue
			assert_lte(desc.position.y + _line_h(desc), oc.position.y,
				"Text Size %s: the description ends at %.0f and the options start at %.0f" % [
					LABELS[i], desc.position.y + _line_h(desc), oc.position.y])


func test_the_options_row_fits_inside_its_own_row() -> void:
	## A taller chip must grow the ROW, or the strip spills into the next setting.
	for i in PRESETS.size():
		await _build_at(PRESETS[i])
		for row in _option_rows():
			var oc := row.get_node_or_null("OptionsContainer") as Control
			if oc == null:
				continue
			var chip_h := 0.0
			for pair in _chips_of(row):
				chip_h = maxf(chip_h, (pair["chip"] as Control).size.y)
			assert_lte(oc.position.y + chip_h, row.size.y,
				"Text Size %s: the options strip ends at %.0f in a %.0f-tall row" % [
					LABELS[i], oc.position.y + chip_h, row.size.y])


func test_an_option_label_cannot_draw_outside_its_chip() -> void:
	## Mechanism, and a belt for a chip that a future font makes too small anyway: an assigned size
	## is clamped up to the text's own content width unless the Label clips.
	await _build_at(2.0)
	var checked := 0
	for row in _option_rows():
		for pair in _chips_of(row):
			checked += 1
			var l := pair["label"] as Label
			assert_true(l.clip_text,
				"option '%s' must clip, or its box is undone by its own minimum size" % [l.text])
	assert_gt(checked, 0, "PRECONDITION: at least one chip must have been measured")
