extends GutTest

## Bubbles lifted by half the FRAME. The artists' 256px frames hold figures at different offsets, so the bubble floated above the head by a different amount per speaker — fighter 114px, rogue 84, bard 62, mage 37, cleric 12 (measured 2026-09-16).

const Loader = preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const STARTERS := ["fighter", "rogue", "bard", "mage", "cleric"]

const FRAME := 64
const TOP_MARGIN := 20
const FIGURE_H := 40


## A frame whose opaque figure starts TOP_MARGIN down, so frame-based and figure-based lifts differ by a known amount.
func _sprite(scale_y: float) -> AnimatedSprite2D:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(TOP_MARGIN, TOP_MARGIN + FIGURE_H):
		for x in range(20, 44):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_frame("idle", ImageTexture.create_from_image(img))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = "idle"
	s.scale = Vector2(scale_y, scale_y)
	add_child_autofree(s)
	return s


## The property: the lift reaches the figure's top, not the frame's.
func test_lift_reaches_the_figure_top() -> void:
	var s := _sprite(1.0)
	var got: float = BattleSpeechBubble.head_lift(s)
	assert_almost_eq(got, float(FRAME) * 0.5 - float(TOP_MARGIN), 0.01,
		"lift %.1f must reach the figure's top (%d), not the frame's (%d) — the difference IS the float" % [got, FRAME / 2 - TOP_MARGIN, FRAME / 2])


## CONTROL: the frame-based lift is a DIFFERENT number here, or this harness cannot tell them apart.
func test_control_the_frame_based_lift_would_differ() -> void:
	var s := _sprite(1.0)
	var frame_based: float = float(FRAME) * 0.5 * absf(s.scale.y)
	assert_ne(frame_based, BattleSpeechBubble.head_lift(s),
		"the fixture must have a top margin, else frame and figure lifts coincide and every assert here is free")
	assert_eq(frame_based - BattleSpeechBubble.head_lift(s), float(TOP_MARGIN),
		"and they must differ by exactly the transparent margin")


## Scale multiplies the float, which is why the Fighter (1.72) floated worst.
func test_the_lift_scales_with_the_sprite() -> void:
	var got: float = BattleSpeechBubble.head_lift(_sprite(2.0))
	assert_almost_eq(got, (float(FRAME) * 0.5 - float(TOP_MARGIN)) * 2.0, 0.01,
		"lift must scale with the sprite; a 2x sprite doubles both the frame and the margin")


## No frame at all: no geometry to read, so the caller keeps its own anchor.
func test_a_sprite_with_no_frame_lifts_nothing() -> void:
	var s := AnimatedSprite2D.new()
	add_child_autofree(s)
	assert_eq(BattleSpeechBubble.head_lift(s), 0.0,
		"no sprite_frames means no geometry to read; the caller keeps its own anchor")
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	s.sprite_frames = frames
	s.animation = "idle"
	assert_eq(BattleSpeechBubble.head_lift(s), 0.0, "an animation with no frames must not throw")


## A frame that EXISTS but cannot be read falls back to the old half-frame, never to zero — zero anchors the bubble on the waist.
func test_an_unreadable_frame_falls_back_to_the_half_frame() -> void:
	var ph := PlaceholderTexture2D.new()
	ph.size = Vector2(FRAME, FRAME)
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_frame("idle", ph)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = "idle"
	add_child_autofree(s)
	assert_eq(BattleSpeechBubble.head_lift(s), float(FRAME) * 0.5,
		"an unreadable frame must degrade to the pre-2026-09-16 half-frame lift, not to 0 (bubble on the waist)")


## Non-AnimatedSprite2D speakers (procedural party sprites) must not break the anchor path.
func test_a_plain_node2d_speaker_is_handled() -> void:
	var n := Node2D.new()
	add_child_autofree(n)
	assert_eq(BattleSpeechBubble.head_lift(n), 0.0, "a non-AnimatedSprite2D has no figure rect and must return 0, not error")
## centered=false puts the frame's TOP at the origin, so the figure top is BELOW it and the anchor must move down.
func test_an_uncentered_sprite_reads_its_own_origin() -> void:
	var s := _sprite(1.0)
	s.centered = false
	assert_eq(BattleSpeechBubble.head_lift(s), -float(TOP_MARGIN),
		"with the origin at the frame's top-left the figure starts %dpx BELOW it — the lift is negative, not the centered half-frame" % TOP_MARGIN)


## `offset` shifts where the frame is drawn, so it shifts the head with it.
func test_the_sprite_offset_moves_the_head() -> void:
	var s := _sprite(1.0)
	s.offset = Vector2(0, -10)
	assert_eq(BattleSpeechBubble.head_lift(s), float(FRAME) * 0.5 - float(TOP_MARGIN) + 10.0,
		"a frame drawn 10px higher puts its head 10px higher")


## REAL SHEETS. Expectation comes from the ENGINE's own frame rect (get_rect honours centered + offset),
## so this arm does not re-derive head_lift's arithmetic — it checks it against the draw geometry.
func test_the_real_job_sheets_land_on_their_own_figures() -> void:
	var tops: Array = []
	for job in STARTERS:
		var sf: SpriteFrames = Loader.load_sprite_frames(null, job, "", "", "", "")
		assert_true(sf != null and sf.has_animation(&"idle") and sf.get_frame_count(&"idle") > 0,
			"%s must have an idle frame to measure" % job)
		if sf == null or not sf.has_animation(&"idle") or sf.get_frame_count(&"idle") == 0:
			continue
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = sf
		spr.animation = &"idle"
		spr.scale = Vector2(1.23, 1.23)
		add_child_autofree(spr)
		var tex: Texture2D = sf.get_frame_texture(&"idle", 0)
		var img: Image = tex.get_image()
		var used_top: float = float(img.get_used_rect().position.y)
		tops.append(used_top)
		# Sprite2D.get_rect() is the ENGINE's own centered+offset rule for a frame this size — the oracle for where the frame hangs off the origin. AnimatedSprite2D exposes no get_rect.
		var oracle := Sprite2D.new()
		oracle.texture = tex
		oracle.centered = spr.centered
		oracle.offset = spr.offset
		add_child_autofree(oracle)
		var expected: float = -(oracle.get_rect().position.y + used_top) * 1.23
		assert_almost_eq(BattleSpeechBubble.head_lift(spr), expected, 0.01,
			"%s: the lift must reach the engine's frame top plus its own transparent margin" % job)
	tops.sort()
	assert_gt(tops[-1] - tops[0], 20.0,
		"ANTI-VACUITY: the starter sheets must still place their figures at different heights (%s), else the frame rule and the figure rule agree and every arm above is free" % str(tops))
