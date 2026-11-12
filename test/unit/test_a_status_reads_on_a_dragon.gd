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
	assert_eq(StatusAura.scale_for(StatusAura.REFERENCE_BODY_PX), 1.0, "CONTROL: a figure of the reference height draws at 1x")
	assert_eq(StatusAura.scale_for(40.0), 1.0, "a small figure keeps the 1x motif: 1x is the readable floor")
	assert_almost_eq(StatusAura.scale_for(StatusAura.REFERENCE_BODY_PX * 2.0), 2.0, 0.001, "a figure twice as tall draws its motifs twice as large")
	assert_eq(StatusAura.scale_for(5000.0), StatusAura.SCALE_MAX, "the growth is capped, so a screen-filling boss is not buried in its own status")
	var small := _aura(["sleep"], Rect2(-24, -64, 48, 64))
	var big := _aura(["sleep"], Rect2(-90, -192, 180, 192))
	assert_eq(small.motif_scale(), 1.0, "CONTROL: a party-sized body is 1x")
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
	assert_gt(float(xs[0]), big.body.end.x, "the first column stands outside the figure")


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
