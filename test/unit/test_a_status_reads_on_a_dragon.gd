extends GutTest

## A status motif reads on a battler of ANY size and colour (struktured 2026-11-07, relayed: the monster status
## indicators are "kinda stinky"; fix approved by cowir-main 24009 / 24022).
##
## Two defects, both in how StatusAura drew: a motif was one fixed size, so on a 250 px dragon it was a speck; and a
## motif was a flat fill with no edge, so it vanished on a body of its own colour. Its letters also came from the
## engine's fallback font while every other number in battle is PixelText.
## What this file can judge is the RULE (scale, rim, glyph source). Whether a motif READS as its status is judged by
## eye on the rendered collage (tmp/statusrender), not here.

const AURA_SRC := "res://src/battle/StatusAura.gd"


func _aura(statuses: Array, body: Rect2) -> StatusAura:
	var a := StatusAura.new()
	a.body = body
	add_child_autofree(a)
	a.set_statuses(statuses)
	return a


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _code() -> String:
	var out := ""
	for line in FileAccess.get_file_as_string(AURA_SRC).split("\n"):
		if not line.strip_edges().begins_with("#"):
			out += line + "\n"
	return out


func test_a_motif_grows_with_the_figure_and_never_shrinks() -> void:
	assert_gt(StatusAura.SCALE_MIN, 1.0, "CONTROL: the floor is above the drawn size (a slime's motif was a speck at 1.0)")
	assert_eq(StatusAura.scale_for(40.0), StatusAura.SCALE_MIN, "a small figure gets the floor, never less")
	assert_almost_eq(StatusAura.scale_for(StatusAura.REFERENCE_BODY_PX * 2.0), 2.0, 0.001, "a figure twice as tall draws its motifs twice as large")
	assert_eq(StatusAura.scale_for(5000.0), StatusAura.SCALE_MAX, "the growth is capped, so a screen-filling boss is not buried in its own status")
	var small := _aura(["sleep"], Rect2(-24, -64, 48, 64))
	var big := _aura(["sleep"], Rect2(-90, -192, 180, 192))
	assert_eq(small.motif_scale(), StatusAura.SCALE_MIN, "CONTROL: a 64 px body is at the floor")
	assert_gt(big.motif_scale(), 1.9, "a 192 px body draws its motifs about twice as large; got %.2f" % big.motif_scale())


func test_arrow_columns_spread_with_the_scale_so_big_arrows_do_not_overlap() -> void:
	var big := _aura(["attack_up", "defense_down", "magic_up", "speed_down"], Rect2(-90, -192, 180, 192))
	var k := big.motif_scale()
	assert_gt(k, 1.5, "CONTROL: this body scales its motifs; got %.2f" % k)
	var xs: Array = []
	for slot in 4:
		xs.append(big.arrow_x(slot, 4))
	for i in range(1, xs.size()):
		assert_gt(float(xs[i]) - float(xs[i - 1]), 12.0 * k - 0.1,
			"an arrow is 12 px wide at 1x, so at %.2fx columns %d and %d overlap: %s" % [k, i - 1, i, str(xs)])
	var small := _aura(["attack_up", "defense_down", "magic_up", "speed_down"], Rect2(-24, -64, 48, 64))
	var lead_drawn: float = (small.arrow_x(0, 4) - small.body.end.x) / small.motif_scale()
	assert_almost_eq((float(xs[0]) - big.body.end.x) / k, lead_drawn, 0.01,
		"the first column keeps its drawn place beside the figure's edge at every scale (%.1f px before scaling)" % lead_drawn)


func test_every_motif_has_a_rim_that_contrasts_with_it() -> void:
	var a := _aura([], Rect2(-24, -64, 48, 64))
	var kinds := {}
	for status in StatusAura.MOTIF:
		var kind := StatusAura.motif_for(status)
		if kind != "none":
			kinds[kind] = status
	kinds[StatusAura.FALLBACK] = "a_status_nobody_mapped"
	assert_gt(kinds.size(), 15, "CONTROL: the motif table loads; found %d kinds" % kinds.size())
	var flat: Array = []
	for kind in kinds:
		var colours: Array = StatusAura.STAT_COLOR.values() if kind == "arrow" else [a._color_of(str(kinds[kind]), str(kind))]
		for c in colours:
			var gap := absf(_lum(c) - _lum(StatusAura.rim_for(str(kind))))
			if gap < 0.2:
				flat.append("%s (%.2f)" % [kind, gap])
	assert_eq(flat, [], "a motif's rim is as dark (or as light) as the motif, so it is no rim: %s" % str(flat))
	assert_gt(_lum(StatusAura.rim_for("visor")), 0.8, "the blind visor is near-black: its rim is the light one")
	assert_lt(_lum(StatusAura.rim_for("stars")), 0.2, "CONTROL: a bright motif gets the dark rim")


func test_its_letters_are_the_battle_face_not_the_engine_font() -> void:
	var code := _code()
	assert_gt(code.length(), 2000, "CONTROL: StatusAura's source reads")
	assert_true(code.contains("PixelText.glyph_texture"), "CONTROL: the letters are drawn from PixelText's glyphs")
	assert_false(code.contains("fallback_font"), "StatusAura draws a letter with the engine's fallback font")
	assert_false(code.contains("draw_string"), "StatusAura draws text through a font, not through the battle's pixel glyphs")
	assert_gt(StatusAura.TEXT_GLYPHS.size(), 1, "CONTROL: the file names the letters it draws")
	for ch in StatusAura.TEXT_GLYPHS:
		assert_true(PixelText.GLYPHS.has(ch), "'%s' is not a PixelText glyph, so it would draw as the unknown mark" % ch)
		assert_true(code.contains('_glyph("%s"' % ch), "TEXT_GLYPHS names '%s' and nothing draws it" % ch)


func test_a_big_battler_with_every_motif_draws_a_frame() -> void:
	var statuses: Array = StatusAura.MOTIF.keys()
	var a := _aura(statuses, Rect2(-90, -192, 180, 192))
	assert_gt(a.shown_kinds().size(), 25, "CONTROL: every mapped status is shown; got %d" % a.shown_kinds().size())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(a.visible and a.is_processing(), "the aura is still drawing after two frames with every motif on a large body")
	assert_eq(a.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pixel glyphs scaled with a smoothing filter blur")


func test_a_motif_over_the_head_starts_above_the_badge_row() -> void:
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(scene_src.contains("aura.head_clear = (STATUS_ROW_LIFT + STATUS_ROW_CLEAR) * STATUS_ROW_ZOOM"),
		"the scene tells each aura how tall the badge band above its figure is, from the badge row's own constants")
	var consts: Dictionary = load("res://src/battle/BattleScene.gd").get_script_constant_map()
	var band: float = (float(consts.get("STATUS_ROW_LIFT", 0.0)) + float(consts.get("STATUS_ROW_CLEAR", 0.0))) * float(consts.get("STATUS_ROW_ZOOM", 0.0))
	assert_gt(band, 20.0, "CONTROL: the badge row's constants read; band = %.1f px" % band)
	var code := _code()
	assert_true(code.contains("body.position.y - head_clear"), "the head anchor is lifted by the band")
	assert_eq(_aura([], Rect2(-24, -64, 48, 64)).head_clear, 0.0, "an aura nobody placed (a test, a preview) keeps the bare head anchor")


## main 24548: evasion's outline of the figure's bounding box read as a selection cursor. It is now after-images of
## the sprite's own frame. What this can pin is that no box is drawn and the copies come from the live sprite; whether
## it READS as "hard to hit" is judged on the collage.
func test_evasion_is_after_images_of_the_sprite_not_a_box() -> void:
	var code := _code()
	var arm := code.substr(code.find('"shadow":'), 200)
	assert_true(arm.contains("_after_images("), "CONTROL: the evasion motif draws after-images")
	assert_false(arm.contains("draw_rect"), "evasion still outlines the figure's bounding box")
	assert_gt(StatusAura.AFTER_IMAGES, 1, "one copy is a ghost, not a trail")
	var tex := ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.add_frame("idle", tex)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.animation = "idle"
	add_child_autofree(spr)
	var a := StatusAura.new()
	spr.add_child(a)
	a.set_statuses(["evasion"])
	assert_eq(a.shown_kinds(), ["shadow"], "CONTROL: evasion is shown on a real sprite")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(a.visible and a.is_processing(), "the after-images are still drawing after two frames on a live sprite")
	var bare := _aura(["evasion"], Rect2(-24, -64, 48, 64))
	await get_tree().process_frame
	assert_true(bare.visible, "an aura with no sprite above it draws nothing for evasion and does not stop")

