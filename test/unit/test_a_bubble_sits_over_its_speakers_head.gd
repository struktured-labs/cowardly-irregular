extends GutTest

## struktured 2026-10-31: "when the Cleric speaks a quip in battle, her speech bubble isn't positioned
## correctly over her." The anchor lifted to the FIGURE's top and stayed on the FRAME's centre x. The
## Cleric's staff and its wisps rise ~38px above her hood and to her right, so the figure's top was the
## wisp and the bubble pointed at her staff. The anchor is now her HEAD (BattleSpeechBubble.head_point_of),
## across as well as up, mirrored with flip_h. Screens: tools/bubble_anchor_shots.sh.

const AuraScript := preload("res://src/battle/AdvanceAura.gd")
const FRAME := 64
const JOBS_DIR := "res://assets/sprites/jobs"
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]


## A figure with a head atop a wider body, and a thin staff rising THROUGH the head's column above it.
## `shift` moves the whole figure left of the frame centre (the body column is what the head is found from).
func _figure_tex(shift: int = 0) -> ImageTexture:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(30, 64):
		for x in range(20 - shift, 45 - shift):
			img.set_pixel(x, y, Color.WHITE)
	for y in range(18, 30):
		for x in range(26 - shift, 38 - shift):
			img.set_pixel(x, y, Color.WHITE)
	for y in range(0, 18):
		for x in range(36 - shift, 39 - shift):
			img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _sprite(tex: Texture2D, flip: bool = false, scale: float = 1.0, offset: Vector2 = Vector2.ZERO) -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_frame("idle", tex)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = "idle"
	s.flip_h = flip
	s.scale = Vector2(scale, scale)
	s.offset = offset
	add_child_autofree(s)
	return s


func test_a_prop_rising_above_the_head_is_not_the_head() -> void:
	var tex := _figure_tex()
	var fig: Rect2 = AuraScript.figure_rect_of(tex)
	assert_eq(fig.position.y, 0.0, "CONTROL: the staff makes the figure's top 0, which the old anchor used")
	var head: Vector2 = BattleSpeechBubble.head_point_of(tex)
	assert_eq(head.y, 18.0, "the head starts at row 18, under the staff; got %s" % str(head))
	assert_almost_eq(BattleSpeechBubble.head_lift(_sprite(tex)), float(FRAME) * 0.5 - 18.0, 0.01,
		"the lift must reach the head, not the staff tip")


func test_the_anchor_follows_the_head_across_and_mirrors_with_the_flip() -> void:
	var tex := _figure_tex(12)
	var dx: float = BattleSpeechBubble.head_dx(_sprite(tex))
	assert_lt(dx, 0.0, "CONTROL: this fixture's body column sits left of the frame centre (dx %.1f)" % dx)
	assert_almost_eq(BattleSpeechBubble.head_dx(_sprite(tex, true)), -dx, 0.01,
		"a flipped frame draws its head on the other side of the origin")
	assert_almost_eq(BattleSpeechBubble.head_dx(_sprite(tex, false, 2.0, Vector2(5, 0))), (dx + 5.0) * 2.0, 0.01,
		"offset moves it and scale multiplies it, as they move the drawn frame")


## Measured on the shipped art 2026-10-31: the two starters with a prop above the head.
func test_the_cleric_and_bard_anchor_on_their_heads_not_their_props() -> void:
	for job in ["cleric", "bard"]:
		var tex: Texture2D = load("%s/%s/idle.png" % [JOBS_DIR, job])
		assert_not_null(tex, "%s idle sheet must load" % job)
		if tex == null:
			continue
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(0, 0, 256, 256)
		var top: float = AuraScript.figure_rect_of(at).position.y
		var head: Vector2 = BattleSpeechBubble.head_point_of(at)
		assert_gte(head.y - top, 20.0,
			"%s: the head (%s) must sit under the prop that tops the figure (y %.0f), or the bubble points at the prop" % [job, str(head), top])


## Every starter's idle sheet, every world costume: the anchor lands on the figure, near its top.
func test_every_starter_costume_has_a_head_on_its_figure() -> void:
	var checked := 0
	for job in STARTERS:
		for f in DirAccess.get_files_at("%s/%s" % [JOBS_DIR, job]):
			if not (f.begins_with("idle") and f.ends_with(".png")) or f.contains("pre_artist") or f.contains("_128"):
				continue
			var tex: Texture2D = load("%s/%s/%s" % [JOBS_DIR, job, f])
			if tex == null:
				continue
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(0, 0, 256, 256)
			var fig: Rect2 = AuraScript.figure_rect_of(at)
			var head: Vector2 = BattleSpeechBubble.head_point_of(at)
			checked += 1
			assert_true(fig.has_point(head), "%s/%s: head %s must be on the figure %s" % [job, f, str(head), str(fig)])
			assert_lt(head.y, fig.position.y + fig.size.y * 0.5, "%s/%s: the head must be in the figure's upper half" % [job, f])
	assert_gte(checked, 25, "CONTROL: 5 starters x 6 costumes must be found (got %d)" % checked)


func test_the_scene_moves_the_anchor_across_to_the_head() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var body := src.substr(src.find("func _spawn_quip_bubble"), 3000)
	assert_true("anchor.x += BattleSpeechBubble.head_dx(sprite)" in body,
		"_spawn_quip_bubble must shift the anchor across to the head, not keep the frame's centre")
