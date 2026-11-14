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


## Side gutter a capped toast keeps from each screen edge, and the padding a short one keeps around its words.
const SIDE_MARGIN := 16.0
const TEXT_PAD := 12.0
## Space kept between a toast and a HUD block it settles under.
const HUD_GAP := 6.0
## TutorialHint joins this group so a toast can settle below an open hint (OverworldMinimap.HUD_GROUP is the HUD's).
const HINT_GROUP := &"tutorial_hints"


## The y of the first band [x, x+w) × `band_h` that overlaps no live toast and no HUD block already on screen; -1 if none
## fits above `view_h`. Candidates are the stack rows (BASE_Y + n rows), then the line just under each block in the way,
## so with nothing else up the rows are exactly the old stride.
static func _free_y(band_h: float, x: float = 0.0, w: float = 1280.0, view_h: float = 720.0, blocks: Array = []) -> float:
	var taken: Array = blocks.duplicate()
	var ys: Array = []
	for row in MAX_STACK:
		ys.append(BASE_Y + row * STACK_ROW_HEIGHT)
	for r in blocks:
		ys.append((r as Rect2).end.y + HUD_GAP)
	for live in _active_layers:
		if is_instance_valid(live) and (live as CanvasLayer).visible:
			var t := Rect2(float(live.get_meta("toast_x", 0.0)), float(live.get_meta("toast_y", BASE_Y)),
				float(live.get_meta("toast_w", 1280.0)), float(live.get_meta("toast_h", LINE_BAND)))
			taken.append(t)
			ys.append(t.end.y + STACK_ROW_HEIGHT - LINE_BAND)  # under a toast, the stack's own row gap
	ys.sort()
	for y in ys:
		if y < BASE_Y or y + band_h > view_h:
			continue
		var band := Rect2(x, y, w, band_h)
		var clear := true
		for r in taken:
			if band.intersects(r):
				clear = false
				break
		if clear:
			return y
	return -1.0


## Every HUD block a toast must not land on: the reserved HUD (minimap, quest tracker, zone banner) and an open hint.
static func _hud_blocks(parent: Node) -> Array:
	var out: Array = []
	if parent == null or not parent.is_inside_tree():
		return out
	for n in parent.get_tree().get_nodes_in_group(OverworldMinimap.HUD_GROUP):
		if n.has_method("reserved_rect"):
			var r: Rect2 = n.reserved_rect()
			if r.has_area():
				out.append(r)
	for h in parent.get_tree().get_nodes_in_group(HINT_GROUP):
		if h.has_method("panel_rect"):
			var r: Rect2 = h.panel_rect()
			if r.has_area():
				out.append(r)
	return out


static func show(parent: Node, text: String, color: Color = DEFAULT_COLOR, hold_s: float = 2.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# Tick 205: prune dead layers (parent freed, manual queue_free elsewhere) before computing stack offset so a finished toast doesn't keep its slot.
	_active_layers = _active_layers.filter(func(l): return is_instance_valid(l))
	var vp_size := Vector2(1280, 720)
	if parent.has_method("get_viewport"):
		var vp := parent.get_viewport()
		if vp:
			vp_size = vp.get_visible_rect().size
			if vp_size.x <= 0:
				vp_size = Vector2(1280, 720)

	# Text Size: built per show, so the live scale is read here; the band below is measured at it.
	var px: int = TextScale.scaled(FONT_SIZE)
	var band_h: float = LINE_BAND
	## As wide as its words, centred, never past the side gutters: a full-screen-wide label lay across the minimap and the
	## quest tracker on every row (field census, .801).
	var w: float = vp_size.x - 2.0 * SIDE_MARGIN
	var font: Font = ThemeDB.fallback_font
	if font != null:
		w = minf(w, ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x) + 2.0 * TEXT_PAD)
		band_h = maxf(LINE_BAND, font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, w, px).y)
	var x: float = floorf((vp_size.x - w) / 2.0)
	var blocks: Array = _hud_blocks(parent)

	## A toast takes the first ROW whose band is clear of every live toast, by their recorded rects. The stack used to
	## place by COUNT (`size() * row`), so once an older toast had faded the next one landed on a row still in use, and
	## a burst past MAX_STACK put every extra toast on the last row, one on top of another (struktured 2026-11-11).
	## At the cap, or with no clear row, the oldest goes at once (hidden this frame, not just queued) and its row is free.
	while not _active_layers.is_empty() and (_active_layers.size() >= MAX_STACK or _free_y(band_h, x, w, vp_size.y, blocks) < 0.0):
		var oldest: Node = _active_layers.pop_front()
		if is_instance_valid(oldest):
			oldest.visible = false
			oldest.queue_free()
	var y: float = maxf(BASE_Y, _free_y(band_h, x, w, vp_size.y, blocks))

	var layer := CanvasLayer.new()
	layer.layer = 80
	layer.name = "Toast"
	layer.set_meta("toast_x", x)
	layer.set_meta("toast_w", w)
	layer.set_meta("toast_y", y)
	layer.set_meta("toast_h", band_h)
	parent.add_child(layer)
	_active_layers.append(layer)

	var shadow := Label.new()
	shadow.name = "Shadow"
	shadow.text = text
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shadow.position = Vector2(x + 2, y + 2)
	shadow.add_theme_font_size_override("font_size", px)
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
	shadow.size = Vector2(w, band_h)
	shadow.modulate.a = 0.0
	layer.add_child(shadow)

	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector2(x, y)
	label.size = Vector2(w, band_h)
	label.add_theme_font_size_override("font_size", px)
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
