extends RefCounted
class_name MenuChrome

## Header and footer placement for menus whose fonts follow TextScale.
## A Label will not stay in a 24px row: its box grows to the font's line height,
## so a fixed y puts the title under the next panel and the footer off the screen.
## The words are unchanged. A footer that does not fit shrinks, then wraps.


## Lock the label to the size Godot will actually draw.
static func lock(label: Label) -> Vector2:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.custom_minimum_size = Vector2.ZERO
	var needed := label.get_minimum_size()
	if needed.y < 1.0:
		needed = _fallback_size(label, -1.0)
	label.custom_minimum_size = needed
	label.size = needed
	return needed


## Title on the left, optional counter on the right. Returns the y content below may use.
static func place_header(title: Label, counter: Label, width: float, top: float = 16.0, center_title: bool = false, margin: float = 16.0) -> float:
	var gap := 12.0
	var inner := maxf(40.0, width - margin * 2.0)
	if counter == null:
		var title_only := _fit_width(title, inner)
		var x := margin
		if center_title:
			x = maxf(margin, (width - title_only.x) * 0.5)
		title.position = Vector2(x, top)
		return top + title_only.y
	var counter_cap := inner
	var title_sz := _fit_width(title, inner)
	var counter_sz := _fit_width(counter, counter_cap)
	if title_sz.x + gap + counter_sz.x > inner:
		counter_sz = _fit_width(counter, maxf(40.0, inner - title_sz.x - gap))
	if title_sz.x + gap + counter_sz.x <= inner + 0.5:
		var row_h := maxf(title_sz.y, counter_sz.y)
		counter.position = Vector2(width - margin - counter_sz.x, top)
		var title_x := margin
		if center_title:
			var space := counter.position.x - gap - margin
			title_x = margin + maxf(0.0, (space - title_sz.x) * 0.5)
			if title_x + title_sz.x > counter.position.x - gap:
				title_x = maxf(margin, counter.position.x - gap - title_sz.x)
		title.position = Vector2(title_x, top)
		return top + row_h
	var stacked_x := margin
	if center_title:
		stacked_x = maxf(margin, (width - title_sz.x) * 0.5)
	title.position = Vector2(stacked_x, top)
	counter.position = Vector2(width - margin - counter_sz.x, top + title_sz.y + 4.0)
	return counter.position.y + counter_sz.y


## One counter, right edge inset by `margin`. Returns the y content below may use.
static func place_counter(counter: Label, width: float, top: float = 16.0, margin: float = 16.0) -> float:
	var sz := _fit_width(counter, maxf(40.0, width - margin * 2.0))
	counter.position = Vector2(width - margin - sz.x, top)
	return top + sz.y


## Pin the footer inside `bounds`. The label's current font size is the start; it may shrink or wrap.
static func place_footer(label: Label, bounds: Vector2, margin: float = 16.0) -> Rect2:
	var start_px := _authored_px(label)
	if not label.has_meta(&"footer_font"):
		label.set_meta(&"footer_font", start_px)
	var width := maxf(40.0, bounds.x - margin * 2.0)
	var max_h := maxf(8.0, bounds.y - margin * 2.0)
	var height := _footer_height(label, width, int(label.get_meta(&"footer_font")), max_h)
	var text_h := label.get_minimum_size().y
	label.custom_minimum_size = Vector2(width, height)
	label.size = Vector2(width, height)
	var y := bounds.y - margin - height
	if y < margin:
		y = margin
	label.position = Vector2(margin, y)
	label.clip_text = text_h > height + 1.0
	return Rect2(label.position, label.size)


## Keep `slot` (so the panels above do not move) and fit new words into it.
static func fit_footer_text(label: Label, slot: Rect2) -> void:
	var start_px := int(label.get_meta(&"footer_font", label.get_theme_font_size(&"font_size")))
	var floor_px := maxi(8, int(round(float(start_px) * 0.65)))
	var px := start_px
	var height := slot.size.y
	while px >= floor_px:
		label.add_theme_font_size_override(&"font_size", px)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2.ZERO
		label.size = Vector2(slot.size.x, 4.0)
		height = label.get_minimum_size().y
		if height <= slot.size.y + 1.0 or px == floor_px:
			break
		px -= 1
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = height > slot.size.y + 1.0
	label.custom_minimum_size = slot.size
	label.size = slot.size
	label.position = slot.position


static func _authored_px(label: Label) -> int:
	if not label.has_meta(&"chrome_font"):
		label.set_meta(&"chrome_font", label.get_theme_font_size(&"font_size"))
	return int(label.get_meta(&"chrome_font"))


static func _fit_width(label: Label, max_w: float) -> Vector2:
	var start := _authored_px(label)
	var floor_px := maxi(8, int(round(float(start) * 0.65)))
	var px := start
	while px > floor_px:
		label.add_theme_font_size_override(&"font_size", px)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = false
		label.custom_minimum_size = Vector2.ZERO
		var sz := label.get_minimum_size()
		if sz.x <= max_w + 0.5 and sz.y >= 1.0:
			label.custom_minimum_size = sz
			label.size = sz
			return sz
		px -= 1
	label.add_theme_font_size_override(&"font_size", floor_px)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	label.custom_minimum_size = Vector2.ZERO
	label.size = Vector2(max_w, 4.0)
	var wrapped := Vector2(max_w, maxf(label.get_minimum_size().y, label.get_line_height()))
	if wrapped.y < 1.0:
		wrapped = _fallback_size(label, max_w)
	label.custom_minimum_size = wrapped
	label.size = wrapped
	return wrapped


static func _footer_height(label: Label, width: float, start_px: int, max_h: float) -> float:
	var floor_px := maxi(8, int(round(float(start_px) * 0.65)))
	var px := start_px
	var height := 0.0
	while px >= floor_px:
		label.add_theme_font_size_override(&"font_size", px)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2.ZERO
		label.size = Vector2(width, 4.0)
		height = label.get_minimum_size().y
		var line := maxf(1.0, label.get_line_height())
		var fits := height <= line * 2.25 + 1.0 and height <= max_h + 1.0
		if fits or px == floor_px:
			break
		px -= 1
	if height < 1.0:
		height = _fallback_size(label, width).y
	if height > max_h:
		height = max_h
	return height


static func _fallback_size(label: Label, width: float) -> Vector2:
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		font = ThemeDB.fallback_font
	var fsz := label.get_theme_font_size(&"font_size")
	if font == null or fsz <= 0:
		return Vector2(64, 24)
	var sz := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, fsz)
	var h := font.get_height(fsz)
	if h > sz.y:
		sz.y = h
	if width > 0.0:
		sz.x = minf(sz.x, width)
	return sz
