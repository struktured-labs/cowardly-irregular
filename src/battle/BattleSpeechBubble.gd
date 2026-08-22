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

## Victory frames stacked 4 bubbles from different triggers over the party panel — cap and evict oldest.
const MAX_CONCURRENT: int = 2
static var _live: Array = []


## Spawns a bubble above anchor_global_pos. Returns null when suppressed.
## audio_key: optional SFX/voice clip (phase-2 voice acting hook for cowir-sfx).
static func spawn(parent: Node, anchor_global_pos: Vector2, speaker_name: String, line: String,
		border_color: Color = Color(1.0, 0.85, 0.2), hold_time: float = 1.5,
		audio_key: String = "", prefer_right: bool = true) -> BattleSpeechBubble:
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
	b.z_index = 120
	parent.add_child(b)
	b._present(anchor_global_pos, speaker_name, line, border_color, prefer_right)
	b._play_voice(audio_key)
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
	position.y = maxf(position.y, TOP_MARGIN)
	modulate.a = 0.0

	var anchor_x: float = anchor_global_pos.x
	bubble.ready.connect(func():
		if not (is_instance_valid(pointer) and is_instance_valid(bubble) and is_instance_valid(self)):
			return
		var bw: float = bubble.size.x
		position.x = _side_placed_x(anchor_x, bw, prefer_right)
		_build_tail(pointer, bubble.size, anchor_x - position.x)
	, CONNECT_ONE_SHOT)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(self, "position:y", position.y - 10, _hold_time * 0.5)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3).set_delay(_hold_time)
	tween.tween_callback(queue_free)


## Places the bubble BESIDE the speaker, flipping side when the clamp would drag it back onto them — centring on the anchor is what covered the sprite (struktured 2026-08-22).
func _side_placed_x(anchor_x: float, bubble_width: float, prefer_right: bool) -> float:
	var first: float = (anchor_x + SIDE_GAP_PX) if prefer_right else (anchor_x - SIDE_GAP_PX - bubble_width)
	var placed: float = _clamped_x(first, bubble_width)
	if not _covers_anchor(placed, bubble_width, anchor_x):
		return placed
	var second: float = (anchor_x - SIDE_GAP_PX - bubble_width) if prefer_right else (anchor_x + SIDE_GAP_PX)
	var alt: float = _clamped_x(second, bubble_width)
	return alt if not _covers_anchor(alt, bubble_width, anchor_x) else placed


## True when the speaker falls inside the bubble's horizontal span — the bubble is ON them.
func _covers_anchor(x: float, bubble_width: float, anchor_x: float) -> bool:
	return anchor_x > x - CLEAR_SLACK_PX and anchor_x < x + bubble_width + CLEAR_SLACK_PX


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

## Phase-2 voice hook: plays the clip alongside the bubble when authored.
func _play_voice(audio_key: String) -> void:
	if audio_key == "":
		return
	var sm := get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play_ui"):
		sm.play_ui(audio_key)


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
