extends GutTest

## struktured 2026-11-11: "I like this digital old school font look you got going on for victory / dmg numbers
## ... lets use that as much as we are able for all fonts as general theme". One face, one source (UiFont),
## built from the SAME drawings the damage numbers use, with the old face and the symbols behind it.

const DISPLAY_CLASSES := ["Label", "Button", "CheckBox", "OptionButton", "ItemList", "TabBar", "PopupMenu"]


func after_each() -> void:
	UiFont.read_tier = UiFont.READ_TIER_DEFAULT
	UiFont.install(UiFont.READ_TIER_DEFAULT)


func _built(cls: String) -> Control:
	var c: Control = ClassDB.instantiate(cls)
	add_child_autofree(c)
	return c


func test_every_plain_control_draws_the_pixel_face_in_and_out_of_the_tree() -> void:
	assert_true(UiFont.is_installed(), "CONTROL: FontFallbacks installed the face at startup")
	for cls in DISPLAY_CLASSES:
		var c := _built(cls)
		assert_eq(c.get_theme_font("font"), UiFont.display(), "%s in the tree" % cls)
		var loose: Control = ClassDB.instantiate(cls)
		assert_eq(loose.get_theme_font("font"), UiFont.display(), "%s measured BEFORE add_child draws the same face" % cls)
		loose.free()
	assert_eq(ThemeDB.fallback_font, UiFont.display(), "a site that still names ThemeDB.fallback_font measures the drawn face")


func test_the_face_is_the_damage_numbers_drawing_not_a_lookalike() -> void:
	var f: FontFile = UiFont.display()
	var size := Vector2i(UiFont.NOMINAL_SIZE, 0)
	var img: Image = f.get_texture_image(0, size, 0)
	var checked := 0
	for ch in PixelText.GLYPHS:
		if UiFontGlyphs.OVERRIDES.has(ch):
			continue
		var rows: Array = PixelText.GLYPHS[ch]
		var r: Rect2 = f.get_glyph_uv_rect(0, size, ch.unicode_at(0))
		assert_eq(Vector2i(r.size), Vector2i(str(rows[0]).length(), rows.size()), "'%s' cell" % ch)
		var same := true
		for y in rows.size():
			for x in str(rows[y]).length():
				var lit: bool = img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.5
				if lit != (str(rows[y])[x] == "#"):
					same = false
		assert_true(same, "'%s' is PixelText's own rows, pixel for pixel" % ch)
		checked += 1
	assert_gt(checked, 40, "CONTROL: the whole PixelText table was compared (%d)" % checked)


func test_a_sentence_and_a_url_never_leave_the_face() -> void:
	var missing := ""
	for ch in "The quick brown fox jumps over the lazy dog, 0123456789! http://localhost:11434/v1 api_key=sk-A_b (x) [y] \"z\" 50% #1 & @ ; < > * + - ? ' … — · → ← ↑ ↓ ▶ ◀ ✓ ’ “ ”":
		if not UiFont.draws(ch):
			missing += ch
	assert_eq(missing, "", "characters a menu, a sentence or a typed URL needs that the face does not draw")
	var f: FontFile = UiFont.display()
	for ch in "aZ0/_":
		assert_true(f.has_char(ch.unicode_at(0)), "the built font answers for '%s'" % ch)


func test_nothing_turns_to_tofu() -> void:
	var f: Font = UiFont.display()
	var missing := ""
	for ch in "⚔☠♪⚡⚙★⌫⇧💬🔥❄é":
		var found: bool = f.has_char(ch.unicode_at(0))
		for fb in f.fallbacks:
			found = found or (fb != null and fb.has_char(ch.unicode_at(0)))
		if not found:
			missing += ch
	assert_eq(missing, "", "symbols the pixel face does not draw must resolve in the chain behind it")
	assert_gte(f.fallbacks.size(), 5, "the old face and its four symbol fonts are chained (%d)" % f.fallbacks.size())


func test_sizes_snap_to_whole_pixels_never_a_blur() -> void:
	var f: Font = UiFont.display()
	var one: float = f.get_string_size("Attack", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.NOMINAL_SIZE).x
	assert_gt(one, 0.0, "CONTROL: the face measures")
	for size in [8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 40]:
		var w: float = f.get_string_size("Attack", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		assert_eq(w, one * UiFont.scale_for(size), "size %d draws at a whole multiple (%dx), and scale_for() predicts it" % [size, UiFont.scale_for(size)])


func test_the_read_tier_is_one_switch() -> void:
	UiFont.install(UiFont.READ_TIER_DEFAULT)
	var rt := RichTextLabel.new()
	add_child_autofree(rt)
	var le := LineEdit.new()
	add_child_autofree(le)
	assert_ne(rt.get_theme_font("normal_font"), UiFont.display(), "default tier: dialogue keeps the reading face")
	assert_ne(le.get_theme_font("font"), UiFont.display(), "default tier: typed text keeps the reading face")
	assert_eq(UiFont.of(rt), rt.get_theme_font("normal_font"), "of() answers with the slot a RichTextLabel draws")
	UiFont.install(UiFont.READ_TIER_PIXEL)
	assert_eq(rt.get_theme_font("normal_font"), UiFont.display(), "pixel tier: dialogue is the pixel face")
	assert_eq(rt.get_theme_font("bold_font"), UiFont.display(), "pixel tier: [b] does not fall back to the old face")
	assert_eq(le.get_theme_font("font"), UiFont.display(), "pixel tier: typed text too")
	assert_eq(UiFont.body(), UiFont.display(), "body() follows the switch")


func test_no_source_file_names_the_engine_fallback_any_more() -> void:
	# The debt register: sites that still measure with ThemeDB.fallback_font. They are CORRECT today (install
	# points it at the pixel face) but each should ask UiFont.of(node); lanes shrink this as they convert.
	var known := 41
	var n := 0
	for path in _gd_files("res://src"):
		if path.ends_with("/UiFont.gd") or path.ends_with("/FontFallbacks.gd"):
			continue
		n += FileAccess.get_file_as_string(path).count("ThemeDB.fallback_font")
	assert_lte(n, known, "sites naming ThemeDB.fallback_font outside UiFont/FontFallbacks may only go DOWN (now %d)" % n)


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_gd_files(dir + "/" + sub))
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	return out
