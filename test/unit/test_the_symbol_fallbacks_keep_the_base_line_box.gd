extends GutTest

## struktured: "some of the fonts are crap in battle". The bundled Noto fallbacks declared taller line boxes than Open
## Sans (NotoSansSymbols ascent 1480/1000, Symbols2 descent 630, Math descent 423), and Godot takes the CHAIN's max for
## every Label, even one drawing only Latin text: baselines sat 6px low at 16px, descenders were clipped in every 24px
## menu row, and wrapped text was double-spaced. Their hhea/typo ascent/descent were rewritten to 1069/293 (OFL permits
## it; no Reserved Font Name). A fallback added later with a taller box reds here, naming the font and the size.

const SIZES := [9, 10, 12, 13, 15, 16, 20, 24, 32, 48]


func test_no_fallback_reaches_past_the_base_line_box() -> void:
	var chain: Font = ThemeDB.fallback_font
	assert_gt(chain.fallbacks.size(), 3, "CONTROL: FontFallbacks chained the symbol fonts (%d)" % chain.fallbacks.size())
	var base: Font = chain.duplicate()
	base.fallbacks = []
	for fs in SIZES:
		for fb in chain.fallbacks:
			var name: String = (fb as Font).resource_path.get_file()
			assert_true(fb.get_ascent(fs) <= base.get_ascent(fs), "%s ascent %.0f > base %.0f at %dpx" % [name, fb.get_ascent(fs), base.get_ascent(fs), fs])
			assert_true(fb.get_descent(fs) <= base.get_descent(fs), "%s descent %.0f > base %.0f at %dpx" % [name, fb.get_descent(fs), base.get_descent(fs), fs])


func test_the_chain_measures_as_the_base_font() -> void:
	var chain: Font = ThemeDB.fallback_font
	var base: Font = chain.duplicate()
	base.fallbacks = []
	for fs in SIZES:
		assert_eq(chain.get_height(fs), base.get_height(fs), "a %dpx line is the base font's height, not the tallest fallback's" % fs)
