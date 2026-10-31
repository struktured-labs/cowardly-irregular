extends Control
class_name BattleSpeechBubble

## Comic-style speech bubble anchored to a battle sprite (playtest brief msg 2101).
## Non-interactive, auto-sized, viewport-clamped, short-lived; optional voice clip.

## Right column reserved for UI/PartyStatusPanel (200px) + margin — never occlude it.
const RESERVED_RIGHT_PX: float = 210.0
const EDGE_MARGIN: float = 8.0
const TOP_MARGIN: float = 48.0  # 2026-07-16 smoke: head-anchored bubbles on tall party sprites climbed into the AUTO button row (y 6..36) — keep bubbles below it
const MAX_TEXT_WIDTH: float = 260.0
## A quip too long for two rows WIDENS before it grows a third. struktured 2026-08-29 and after: a
## tall bubble clips the crown of the enemy it is next to, and height is what occludes — width is
## already managed (clamped to the viewport, kept off the party panel by RESERVED_RIGHT_PX, slid past
## the command menu by the keep-out rects). Measured with the shaper at the bubble's own font (13):
##   of the 25 scripted party lines at 260px:  1 row 1 · 2 rows 11 · 3 rows 13
##                              at 420px:      1 row 11 · 2 rows 14 · 3 rows 0
## and a 140-char LLM line (MAX_PARTY_LINE_CHARS) goes 4 rows -> 3. This changes no authored line,
## which is the half struktured has open: shortening the Mage/Cleric/Bard lines is still his call,
## and this removes the clipping those lines caused without making it.
const MAX_TEXT_WIDTH_WIDE: float = 420.0
const WIDEN_STEP: float = 40.0
## Two rows is the target, not a limit: a line that cannot reach it by WIDTH keeps its rows.
const WIDEN_TARGET_ROWS: int = 2
## Gap between the speaker and the bubble's near edge — the bubble sits BESIDE the head, not on it.
const SIDE_GAP_PX: float = 22.0
## Speaker counts as covered when it falls inside the bubble span plus this slack.
const CLEAR_SLACK_PX: float = 10.0
## Suppress only at 4x+ (doc'd intent); pre-fix code suppressed at 2x so users at 2x saw no bubbles.
const SUPPRESS_AT_LABEL: float = 4.0
## A label is engine*4 (speed scale v3): the bare 4.0 here used to read as the label and meant 16x.
const LABEL_PER_ENGINE: float = 4.0
const SUPPRESS_TIME_SCALE: float = SUPPRESS_AT_LABEL / LABEL_PER_ENGINE

## The figure-bounds scan has ONE owner; the aura disc seats on the same measurement.
const AdvanceAuraClass = preload("res://src/battle/AdvanceAura.gd")

var _hold_time: float = 1.5

## Beat after a spoken line finishes before the bubble starts fading, so the last word is read
## rather than raced.
const VOICE_TAIL_S: float = 0.3

## Victory frames stacked 4 bubbles from different triggers over the party panel — cap and evict oldest.
const MAX_CONCURRENT: int = 2
## Float-up distance for a bubble with headroom; a ceiling-pinned bubble floats only as far as the ceiling allows.
const FLOAT_UP_PX: float = 10.0
static var _live: Array = []
## Texture instance id -> head point in that frame's pixels (see head_point_of).
static var _head_cache: Dictionary = {}
const HEAD_BAND: float = 0.05
const HEAD_FILL: float = 0.6
const HEAD_ROWS: int = 6

## Rendered half-width of the speaker's sprite; 0 when the caller does not know it.
var _speaker_half_width: float = 0.0
## Lowest y a bubble may occupy — the caller passes the SELECT banner's bottom so flavor never covers selection.
var _ceiling_y: float = TOP_MARGIN
## Extra sideways clearance, set when the ceiling forced the bubble down into its speaker's body.
var _side_clear: float = 0.0
var _float_px: float = FLOAT_UP_PX
## The speaker's head in global space, kept so the tail can aim at it in y as well as x.
var _anchor_global: Vector2 = Vector2.ZERO
## Longest tail, px: long enough to reach back from an edge-clamped bubble, short enough not to cross the field.
const TAIL_MAX_PX: float = 56.0
## True once a voice clip set the hold — that hold is in real seconds, so the tween must be too.
var _voiced: bool = false
var _panel: PanelContainer = null
## Returns screen Rect2s the player is reading (the open command menu) — read at layout time, when the menu exists.
var _keep_out: Callable = Callable()

## The narrowest width at which `text` fits WIDEN_TARGET_ROWS, stepping up to MAX_TEXT_WIDTH_WIDE.
## Monotone by construction: it can only ever return a width that needs the same rows or fewer than
## the one before it, and a line that already fits takes the first return untouched.
static func wrap_width_for(text: String, font: Font, font_size: int) -> float:
	if text.is_empty() or font == null or font_size <= 0:
		return MAX_TEXT_WIDTH
	var steps: int = int(ceil((MAX_TEXT_WIDTH_WIDE - MAX_TEXT_WIDTH) / WIDEN_STEP))
	var w: float = MAX_TEXT_WIDTH
	for i in steps + 1:
		w = minf(MAX_TEXT_WIDTH + WIDEN_STEP * float(i), MAX_TEXT_WIDTH_WIDE)
		if _rows_at(text, w, font, font_size) <= WIDEN_TARGET_ROWS:
			return w
	return MAX_TEXT_WIDTH_WIDE


## Rows the shaper itself would wrap this text into — the same engine the Label uses, synchronously.
## ⛔ NOT Label.size / get_content_height: those need a layout pass and answer 1 row headless.
static func _rows_at(text: String, width: float, font: Font, font_size: int) -> int:
	var tp := TextParagraph.new()
	tp.width = width
	tp.add_string(text, font, font_size)
	return tp.get_line_count()


## Screen px from a sprite's centre UP TO ITS HEAD.
## The artists' 256px frames hold figures of different heights at different offsets, so lifting by
## half the FRAME floated the bubble 12-114px above the head, per job (2026-09-16). The figure's TOP
## is not the head either: the Cleric's staff and its wisps rise ~50px above her hood and to her right,
## so a figure-top anchor put her bubble over the staff (struktured, 2026-10-31). See head_point_of.
static func head_lift(sprite: Node2D) -> float:
	var tex := _frame_tex(sprite)
	if tex == null:
		return 0.0
	var anim: AnimatedSprite2D = sprite
	var top: float = head_point_of(tex).y + anim.offset.y
	if anim.centered:
		top -= float(tex.get_height()) * 0.5
	return -top * absf(anim.scale.y)


## Screen px from the sprite's origin ACROSS to its head, mirrored with flip_h. A figure is rarely
## centred in its frame, so the frame's centre x put the bubble's tail beside the speaker.
static func head_dx(sprite: Node2D) -> float:
	var tex := _frame_tex(sprite)
	if tex == null:
		return 0.0
	var anim: AnimatedSprite2D = sprite
	var w := float(tex.get_width())
	var px: float = head_point_of(tex).x
	## A flipped frame is mirrored inside its own rect, so column px draws at w - px.
	if anim.flip_h:
		px = w - px
	var lx: float = px + anim.offset.x - (w * 0.5 if anim.centered else 0.0)
	return lx * anim.scale.x


## The frame the head is read from: idle frame 0 when the sheet has one, else the frame on screen.
## A pose is not a head: an attack frame's highest wide row can be the artist's own slash smear
## (fighter/attack f0), and a bubble that hopped with every frame would not read as one speaker's.
static func _frame_tex(sprite: Node2D) -> Texture2D:
	if not (sprite is AnimatedSprite2D):
		return null
	var anim: AnimatedSprite2D = sprite
	if anim.sprite_frames == null:
		return null
	if anim.sprite_frames.has_animation("idle") and anim.sprite_frames.get_frame_count("idle") > 0:
		return anim.sprite_frames.get_frame_texture("idle", 0)
	if not anim.sprite_frames.has_animation(anim.animation):
		return null
	if anim.sprite_frames.get_frame_count(anim.animation) == 0:
		return null
	return anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)


## Where a frame's HEAD is, in that frame's pixels. The body column is the median x of the opaque
## pixels in the figure's lower half, which a thin staff or instrument barely moves. The head top is
## the first row where a band around that column is mostly filled (HEAD_FILL), for HEAD_ROWS rows
## running: a head is the widest thing atop the body, while a prop crossing the band is thin there.
## Measured on the five starters' idle frames: a first-opaque-pixel rule put the Cleric's anchor on
## her staff's wisp and the Bard's on her instrument's scroll. Cached per texture; frame centre and
## figure top if unreadable.
static func head_point_of(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var key: int = tex.get_instance_id()
	if _head_cache.has(key):
		return _head_cache[key]
	var fig: Rect2 = AdvanceAuraClass.figure_rect_of(tex)
	var head := Vector2(float(tex.get_width()) * 0.5, fig.position.y)
	var img: Image = tex.get_image()
	if img != null and not img.is_empty() and fig.size.x > 0 and fig.size.y > 0:
		if img.is_compressed():
			img.decompress()
		var x0 := int(fig.position.x)
		var x1 := int(fig.end.x)
		var y_mid := int(fig.position.y + fig.size.y * 0.5)
		var cols := PackedInt32Array()
		cols.resize(x1 - x0)
		var total := 0
		for y in range(y_mid, int(fig.end.y), 2):
			for x in range(x0, x1):
				if img.get_pixel(x, y).a > 0.5:
					cols[x - x0] += 1
					total += 1
		if total > 0:
			var seen := 0
			var body_x := x0
			for i in cols.size():
				seen += cols[i]
				if seen * 2 >= total:
					body_x = x0 + i
					break
			var band: int = maxi(6, int(img.get_width() * HEAD_BAND))
			var bx0: int = maxi(x0, body_x - band)
			var bx1: int = mini(x1, body_x + band + 1)
			var need: int = int(float(2 * band + 1) * HEAD_FILL)
			var top_y := int(fig.position.y)
			var run := 0
			for y in range(int(fig.position.y), int(fig.end.y)):
				var filled := 0
				for x in range(bx0, bx1):
					if img.get_pixel(x, y).a > 0.5:
						filled += 1
				run = run + 1 if filled >= need else 0
				if run >= HEAD_ROWS:
					top_y = y - HEAD_ROWS + 1
					break
			head = Vector2(float(body_x) + 0.5, float(top_y))
	_head_cache[key] = head
	return head


## Spawns a bubble above anchor_global_pos. Returns null when suppressed.
## audio_key: optional SFX/voice clip (phase-2 voice acting hook for cowir-sfx).
static func spawn(parent: Node, anchor_global_pos: Vector2, speaker_name: String, line: String,
		border_color: Color = Color(1.0, 0.85, 0.2), hold_time: float = 1.5,
		audio_key: String = "", prefer_right: bool = true, speaker_half_width: float = 0.0,
		ceiling_y: float = TOP_MARGIN, keep_out: Callable = Callable(), voice_stream: AudioStream = null) -> BattleSpeechBubble:
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
	# No divisor: `/ maxf(1.0, Engine.time_scale)` could only divide above engine 1.0, which is
	# exactly where the suppression above has already returned null — inert at every spawnable
	# speed. The tween already scales, so a voiceless hold is 2 BATTLE seconds at any of them.
	b._hold_time = hold_time
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Below the command menu (100) and target highlight (99): flavor never covers the
	# player's selection (struktured 2026-09-02: "cant see ur selection until it fades").
	b.z_index = 95
	parent.add_child(b)
	## BEFORE _present, which builds the fade tween from _hold_time. The voice extends the hold,
	## and a tween created first would keep the old 2.0s and fade over a line still being spoken.
	b._play_voice(audio_key, voice_stream)
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
	# SMALLEST width that fits the target rows — a short quip keeps the narrow bubble it has today.
	text_label.custom_minimum_size = Vector2(wrap_width_for(text_label.text,
		text_label.get_theme_font("font"), TextScale.scaled(13)), 0)
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
	_anchor_global = anchor_global_pos
	# NOT bubble.ready: spawn() adds this node to the tree BEFORE _present runs, so add_child(bubble) above makes the panel ready SYNCHRONOUSLY and a later connect misses the signal forever. Measured 2026-08-22 — is_node_ready() is already true here, so the whole layout pass had been DEAD since the 2026-07-01 extraction.
	_finalize_layout(bubble, pointer, anchor_x, prefer_right)

	var tween := create_tween()
	# A voiced hold is measured on the audio clock; a scaled tween stretched it 4x at default speed and would desync on a mid-hold speed change.
	if _voiced:
		tween.set_ignore_time_scale(true)
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
	_build_tail(pointer, bubble.size, Vector2(anchor_x - position.x, _anchor_global.y - position.y))
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
## The tail AIMS at the speaker's head: an edge-clamped bubble sits well off to one side and the head
## below it, and a tip fixed 16px under the bubble pointed at nobody (cowir-main, from the 2026-10-31 shots).
func _build_tail(pointer: Polygon2D, bubble_size: Vector2, anchor_local: Vector2) -> void:
	var bw: float = bubble_size.x
	var bh: float = bubble_size.y
	var base_cx: float = clampf(anchor_local.x, 16.0, maxf(16.0, bw - 16.0))
	var base := Vector2(base_cx, bh - 2.0)
	var to: Vector2 = anchor_local - base
	## Always leave downward: a head level with the bubble still reads from a tail that dips to it.
	to.y = maxf(to.y, 10.0)
	var dir: Vector2 = to.normalized()
	var tip: Vector2 = base + dir * minf(to.length(), TAIL_MAX_PX)
	## The base spans ACROSS the aim, not along the edge: aimed sideways at a head level with the bubble,
	## an edge-aligned base made a sliver a few px thick (the 2026-10-31 Fighter shot showed no tail at all).
	var half: Vector2 = Vector2(-dir.y, dir.x) * 8.0
	pointer.polygon = PackedVector2Array([base - half, base + half, tip])

## Plays the line's audio (a synthesized stream wins over a shipped clip) and holds the bubble for as long as it lasts.
func _play_voice(audio_key: String, voice_stream: AudioStream = null) -> void:
	if audio_key == "" and voice_stream == null:
		return
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null:
		return
	var clip_len: float = 0.0
	if voice_stream != null and sm.has_method("play_voice_stream"):
		clip_len = sm.play_voice_stream(voice_stream)
	elif audio_key != "" and sm.has_method("play_voice"):
		clip_len = sm.play_voice(audio_key)
	if clip_len <= 0.0:
		return
	## The clip plays in REAL seconds, so this hold is real seconds too — and _present puts a voiced
	## bubble's tween on the real clock to match. A scaled tween held a 5.3s line ≈24s at default
	## speed (measured 2026-09-14). Voiceless bubbles keep battle-relative pacing.
	## No cap, deliberately — a ceiling here would be a coincidental number that silently truncates
	## whichever line is longest. If a line is too long for battle, that is a content call.
	_hold_time = maxf(_hold_time, clip_len + VOICE_TAIL_S)
	_voiced = true


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
