extends Control
class_name BattleSpeechBubble

## Comic-style speech bubble anchored to a battle sprite (playtest brief msg 2101).
## Non-interactive, auto-sized, viewport-clamped, short-lived; optional voice clip.

## Right column reserved for UI/PartyStatusPanel (200px) + margin — never occlude it.
const RESERVED_RIGHT_PX: float = 210.0
const EDGE_MARGIN: float = 8.0
const TOP_MARGIN: float = 48.0  # 2026-07-16 smoke: head-anchored bubbles on tall party sprites climbed into the AUTO button row (y 6..36) — keep bubbles below it
const MAX_TEXT_WIDTH: float = 260.0
## Gap between the speaker and the bubble's near edge — the bubble sits BESIDE the head, not on it.
const SIDE_GAP_PX: float = 22.0
## Speaker counts as covered when it falls inside the bubble span plus this slack.
const CLEAR_SLACK_PX: float = 10.0
## Suppress only at 4x+ (doc'd intent); pre-fix code suppressed at 2x so users at 2x saw no bubbles.
const SUPPRESS_TIME_SCALE: float = 4.0

var _hold_time: float = 1.5

## Beat after a spoken line finishes before the bubble starts fading, so the last word is read
## rather than raced.
const VOICE_TAIL_S: float = 0.3

## Victory frames stacked 4 bubbles from different triggers over the party panel — cap and evict oldest.
const MAX_CONCURRENT: int = 2
## Float-up distance for a bubble with headroom; a ceiling-pinned bubble floats only as far as the ceiling allows.
const FLOAT_UP_PX: float = 10.0
static var _live: Array = []

## Rendered half-width of the speaker's sprite; 0 when the caller does not know it.
var _speaker_half_width: float = 0.0
## Lowest y a bubble may occupy — the caller passes the SELECT banner's bottom so flavor never covers selection.
var _ceiling_y: float = TOP_MARGIN
## Extra sideways clearance, set when the ceiling forced the bubble down into its speaker's body.
var _side_clear: float = 0.0
var _float_px: float = FLOAT_UP_PX
var _panel: PanelContainer = null
## Returns screen Rect2s the player is reading (the open command menu) — read at layout time, when the menu exists.
var _keep_out: Callable = Callable()


## Spawns a bubble above anchor_global_pos. Returns null when suppressed.
## audio_key: optional SFX/voice clip (phase-2 voice acting hook for cowir-sfx).
static func spawn(parent: Node, anchor_global_pos: Vector2, speaker_name: String, line: String,
		border_color: Color = Color(1.0, 0.85, 0.2), hold_time: float = 1.5,
		audio_key: String = "", prefer_right: bool = true, speaker_half_width: float = 0.0,
		ceiling_y: float = TOP_MARGIN, keep_out: Callable = Callable()) -> BattleSpeechBubble:
	if parent == null or not is_instance_valid(parent):
		return null
	if Engine.time_scale >= SUPPRESS_TIME_SCALE:
		return null
	_live = _live.filter(func(e): return is_instance_valid(e["bubble"]) and not e["bubble"].is_queued_for_deletion())
	for e in _live.duplicate():
		if e["speaker"] == speaker_name:
			e["bubble"].queue_free()
			_live.erase(e)
	while _live.size() >= MAX_CONCURRENT:
		var oldest: Dictionary = _live.pop_front()
		if is_instance_valid(oldest["bubble"]):
			oldest["bubble"].queue_free()
	var b := BattleSpeechBubble.new()
	# Faster battle speed shortens the hold so bubbles never outlive their turn.
	b._hold_time = hold_time / maxf(1.0, Engine.time_scale)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Below the command menu (100) and target highlight (99): flavor never covers the
	# player's selection (struktured 2026-09-02: "cant see ur selection until it fades").
	b.z_index = 95
	parent.add_child(b)
	## BEFORE _present, which builds the fade tween from _hold_time. The voice extends the hold,
	## and a tween created first would keep the old 2.0s and fade over a line still being spoken.
	b._play_voice(audio_key)
	b._speaker_half_width = maxf(0.0, speaker_half_width)
	b._ceiling_y = maxf(TOP_MARGIN, ceiling_y)
	b._keep_out = keep_out
	b._present(anchor_global_pos, speaker_name, line, border_color, prefer_right)
	_live.append({"bubble": b, "speaker": speaker_name})
	return b


func _present(anchor_global_pos: Vector2, speaker_name: String, line: String, border_color: Color, prefer_right: bool = true) -> void:
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	# struktured playtest 2026-08-22: the opaque fill hid the sprite behind it — see through it.
	style.bg_color = Color(0.04, 0.03, 0.09, 0.55)
	style.border_color = border_color
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	# Rounded like a comic bubble rather than a panel (same playtest note).
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	bubble.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(vbox)

	var name_label := Label.new()
	name_label.text = speaker_name
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(9))
	name_label.add_theme_color_override("font_color", border_color)
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.0, 0.9))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var text_label := Label.new()
	text_label.text = '"%s"' % line
	text_label.add_theme_font_size_override("font_size", TextScale.scaled(13))
	text_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	# Outline carries legibility now that the fill is see-through.
	text_label.add_theme_constant_override("outline_size", 4)
	text_label.add_theme_color_override("font_outline_color", Color(0.2, 0.15, 0.0))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_label.custom_minimum_size = Vector2(MAX_TEXT_WIDTH, 0)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(text_label)
	add_child(bubble)

	# Tail geometry is rebuilt once the bubble has a real size; fill-coloured so it reads as part of the bubble, not a separate arrow.
	var pointer := Polygon2D.new()
	pointer.color = Color(style.bg_color.r, style.bg_color.g, style.bg_color.b, minf(1.0, style.bg_color.a + 0.14))
	add_child(pointer)

	# Height estimate keeps wrapped bubbles clear of the sprite head pre-layout.
	var est_lines: int = int(ceil(float(line.length()) / 20.0))
	var est_height: int = est_lines * 16 + 24
	position = anchor_global_pos + Vector2(SIDE_GAP_PX, -float(est_height + 28))
	# Top clamp happens HERE (pre-tween) so the float-up tween's captured y never jumps.
	position.y = maxf(position.y, _ceiling_y)
	# Pushed below the head top, the bubble now sits on its speaker — clear the body sideways instead (top party slot).
	if position.y + float(est_height) > anchor_global_pos.y:
		_side_clear = _speaker_half_width
	_float_px = minf(FLOAT_UP_PX, position.y - _ceiling_y)
	modulate.a = 0.0

	var anchor_x: float = anchor_global_pos.x
	# NOT bubble.ready: spawn() adds this node to the tree BEFORE _present runs, so add_child(bubble) above makes the panel ready SYNCHRONOUSLY and a later connect misses the signal forever. Measured 2026-08-22 — is_node_ready() is already true here, so the whole layout pass had been DEAD since the 2026-07-01 extraction.
	_finalize_layout(bubble, pointer, anchor_x, prefer_right)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(self, "position:y", position.y - _float_px, _hold_time * 0.5)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3).set_delay(_hold_time)
	tween.tween_callback(queue_free)


## Runs one frame after build, when the PanelContainer finally has a real size.
func _finalize_layout(bubble: PanelContainer, pointer: Polygon2D, anchor_x: float, prefer_right: bool) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not (is_instance_valid(pointer) and is_instance_valid(bubble) and is_instance_valid(self)):
		return
	var bw: float = bubble.size.x
	position.x = _side_placed_x(anchor_x, bw, prefer_right)
	position.x = _clear_keep_out(position.x, bubble.size, anchor_x)
	_build_tail(pointer, bubble.size, anchor_x - position.x)
	_panel = bubble
	_retire_overlapped_elders()


## Places the bubble BESIDE the speaker, flipping side when the clamp would drag it back onto them — centring on the anchor is what covered the sprite (struktured 2026-08-22).
func _side_placed_x(anchor_x: float, bubble_width: float, prefer_right: bool) -> float:
	var gap: float = SIDE_GAP_PX + _side_clear
	var first: float = (anchor_x + gap) if prefer_right else (anchor_x - gap - bubble_width)
	var placed: float = _clamped_x(first, bubble_width)
	if not _covers_anchor(placed, bubble_width, anchor_x):
		return placed
	var second: float = (anchor_x - gap - bubble_width) if prefer_right else (anchor_x + gap)
	var alt: float = _clamped_x(second, bubble_width)
	return alt if not _covers_anchor(alt, bubble_width, anchor_x) else placed


## True when the speaker falls inside the bubble's horizontal span — the bubble is ON them.
func _covers_anchor(x: float, bubble_width: float, anchor_x: float) -> bool:
	var slack: float = CLEAR_SLACK_PX + _side_clear
	return anchor_x > x - slack and anchor_x < x + bubble_width + slack


## Slides past the open command menu, away from the speaker; if it cannot fit on screen it stays put and the menu (z 100) draws over it.
func _clear_keep_out(x: float, size: Vector2, anchor_x: float) -> float:
	if not _keep_out.is_valid():
		return x
	var rects = _keep_out.call()
	if not (rects is Array) or (rects as Array).is_empty():
		return x
	var off: Vector2 = global_position - position
	var go_left: bool = x + size.x * 0.5 < anchor_x
	var candidate: float = x
	for _step in range(6):
		var mine := Rect2(Vector2(candidate, position.y - _float_px) + off, Vector2(size.x, size.y + _float_px))
		var hit := Rect2()
		for r in rects:
			if r is Rect2 and (r as Rect2).size != Vector2.ZERO and mine.intersects(r):
				hit = r
				break
		if hit.size == Vector2.ZERO:
			return candidate
		var next: float = (hit.position.x - off.x - SIDE_GAP_PX - size.x) if go_left else (hit.end.x - off.x + SIDE_GAP_PX)
		var clamped: float = _clamped_x(next, size.x)
		if absf(clamped - next) > 0.5:
			return x
		candidate = clamped
	return x


## Screen rect of the laid-out panel; empty until the layout pass has run.
func _screen_rect() -> Rect2:
	if _panel == null or not is_instance_valid(_panel):
		return Rect2()
	return Rect2(global_position, _panel.size)


## Two stacked bubbles are unreadable (store capture v3.33.345) — the newer line wins; the older is already in the battle log.
func _retire_overlapped_elders() -> void:
	var mine := _screen_rect()
	if mine.size == Vector2.ZERO:
		return
	for e in _live.duplicate():
		var other = e["bubble"]
		if other == self or not is_instance_valid(other) or other.is_queued_for_deletion():
			continue
		var theirs: Rect2 = other._screen_rect()
		if theirs.size != Vector2.ZERO and mine.intersects(theirs):
			other.queue_free()
			_live.erase(e)


## Tail base on the bubble's bottom edge, tip leaning back toward the speaker, so a diagonally-offset bubble still reads as belonging to that character.
func _build_tail(pointer: Polygon2D, bubble_size: Vector2, anchor_local_x: float) -> void:
	var bw: float = bubble_size.x
	var bh: float = bubble_size.y
	var base_cx: float = clampf(anchor_local_x, 16.0, maxf(16.0, bw - 16.0))
	var tip_x: float = clampf(anchor_local_x, -34.0, bw + 34.0)
	pointer.polygon = PackedVector2Array([
		Vector2(base_cx - 8.0, bh - 2.0),
		Vector2(base_cx + 8.0, bh - 2.0),
		Vector2(tip_x, bh + 16.0),
	])

## Plays the clip and holds the bubble for as long as the line actually lasts.
func _play_voice(audio_key: String) -> void:
	if audio_key == "":
		return
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null or not sm.has_method("play_voice"):
		return
	var clip_len: float = sm.play_voice(audio_key)
	if clip_len <= 0.0:
		return
	## NOT divided by time_scale: the clip plays at real-time length whatever the battle speed, so
	## scaling the hold would re-create the mismatch at 2x. The default hold still scales above.
	## No cap, deliberately — a ceiling here would be a coincidental number that silently truncates
	## whichever line is longest. If a line is too long for battle, that is a content call.
	_hold_time = maxf(_hold_time, clip_len + VOICE_TAIL_S)


## Clamp so the bubble stays on-screen AND out of the reserved right column.
func _clamped_x(desired_x: float, bubble_width: float) -> float:
	var vp_w: float = 1280.0
	var vp := get_viewport()
	if vp:
		var r := vp.get_visible_rect().size
		if r.x > 0:
			vp_w = r.x
	var max_x: float = vp_w - RESERVED_RIGHT_PX - bubble_width
	return clampf(desired_x, EDGE_MARGIN, maxf(EDGE_MARGIN, max_x))
