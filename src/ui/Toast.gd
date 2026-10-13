extends RefCounted
class_name Toast

## Reusable top-banner toast. Call Toast.show(parent, "text") or use variants.
## Fires on CanvasLayer(layer=80). 0.3s fade-in, 2s hold, 0.5s fade-out.

const DEFAULT_COLOR := Color(1.0, 1.0, 0.4)
const SUCCESS_COLOR := Color(0.5, 1.0, 0.5)
const WARNING_COLOR := Color(1.0, 0.6, 0.3)
const DANGER_COLOR := Color(1.0, 0.4, 0.4)

# Tick 205: row offset between stacked toasts. Font-size 20 + 28px breathing room reads cleanly without crowding the screen.
const STACK_ROW_HEIGHT := 48.0
const BASE_Y := 80.0
const FONT_SIZE := 20
# The band a single-line toast occupies. STACK_ROW_HEIGHT - LINE_BAND is the gap between rows.
const LINE_BAND := 40.0
# Tick 206: hard cap on visible stack so a burst of events (corruption cascade, status proc storm) can't fill the screen. Newer events are usually more relevant — evict oldest.
const MAX_STACK := 5

# Tick 205: track live toast layers so simultaneous events stack vertically instead of all rendering at y=80 as unreadable mush.
static var _active_layers: Array = []


static func show(parent: Node, text: String, color: Color = DEFAULT_COLOR, hold_s: float = 2.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# Tick 205: prune dead layers (parent freed, manual queue_free elsewhere) before computing stack offset so a finished toast doesn't keep its slot.
	_active_layers = _active_layers.filter(func(l): return is_instance_valid(l))
	# Tick 206: evict oldest while at cap so the new toast can spawn without pushing the stack off-screen. Hard queue_free is fine — by the time we hit cap, the user can't read all 5+ anyway.
	while _active_layers.size() >= MAX_STACK:
		var oldest: Node = _active_layers.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var stack_offset: float = _active_layers.size() * STACK_ROW_HEIGHT
	# Tick 207: a wrapped message is taller than one row, so the count above under-counts the
	# space already taken and the next toast printed through it. Each layer records what it used
	# beyond one row; a single-line toast records 0, leaving the stride exactly as it was.
	for live in _active_layers:
		stack_offset += float(live.get_meta("toast_extra_h", 0.0))

	var layer := CanvasLayer.new()
	layer.layer = 80
	parent.add_child(layer)
	_active_layers.append(layer)

	var vp_size := Vector2(1280, 720)
	if parent.has_method("get_viewport"):
		var vp := parent.get_viewport()
		if vp:
			vp_size = vp.get_visible_rect().size
			if vp_size.x <= 0:
				vp_size = Vector2(1280, 720)

	var y: float = BASE_Y + stack_offset

	var shadow := Label.new()
	shadow.text = text
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shadow.position = Vector2(2, y + 2)
	shadow.add_theme_font_size_override("font_size", FONT_SIZE)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.6))

	## Tick 207: neither label carried an autowrap_mode, so a message of ANY length was drawn as
	## ONE line at content width and the ends fell off both screen edges. That is not a
	## hypothetical length: GameLoop's bug-report toast interpolates an ABSOLUTE path on purpose
	## ("a tester cannot act on user://"), so the length is the player's home directory. Measured
	## at font size 20 in Open Sans SemiBold, that message is 1282px wide on a 1280px viewport —
	## it clips once the username reaches 9 characters.
	##
	## Both labels are sized BEFORE add_child, which is correct ONLY because they now wrap:
	## with autowrap the content can never be wider than the width assigned, so there is nothing
	## for the Control to expand to. Assigning the width while wrap is still OFF instead lets the
	## content win (measured: 1280 became 1331, and it then wrapped at 1331 and still clipped),
	## and assigning the size AFTER add_child leaves the minimum size that was cached at width
	## zero, giving a correct 2-line draw inside a 3892px rect.
	var band_h: float = LINE_BAND
	var font: Font = shadow.get_theme_font("font")
	if font != null:
		band_h = maxf(LINE_BAND, font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, vp_size.x, FONT_SIZE).y)

	shadow.size = Vector2(vp_size.x, band_h)
	shadow.modulate.a = 0.0
	layer.add_child(shadow)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector2(0, y)
	label.size = Vector2(vp_size.x, band_h)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 0.0
	layer.add_child(label)

	layer.set_meta("toast_extra_h", band_h - LINE_BAND)

	var tween := layer.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(shadow, "modulate:a", 1.0, 0.3)
	tween.tween_interval(hold_s)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(shadow, "modulate:a", 0.0, 0.5)
	# Tick 205: drop layer from active list as it fades — next toast won't inherit a stale slot.
	tween.tween_callback(func(): _active_layers.erase(layer))
	tween.tween_callback(layer.queue_free)


static func show_save(parent: Node, location: String = "") -> void:
	## "Game Saved ✓" plus an optional location tag so the player can confirm
	## WHERE they saved at a glance (useful when juggling multiple save slots
	## across worlds). Empty location keeps the legacy short form.
	var text = "Game Saved ✓"
	if location != "":
		text = "Game Saved ✓ — " + location
	show(parent, text, SUCCESS_COLOR)


static func show_success(parent: Node, text: String) -> void:
	show(parent, text, SUCCESS_COLOR)


static func show_warning(parent: Node, text: String) -> void:
	show(parent, text, WARNING_COLOR)
