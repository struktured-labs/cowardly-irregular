extends GutTest

## struktured 2026-11-11: "I like this digital old school font look you got going on for victory / dmg numbers
## ... lets use that as much as we are able for all fonts as general theme". One face, one source (UiFont),
## built from the SAME drawings the damage numbers use, with the old face and the symbols behind it.

const DISPLAY_CLASSES := ["Label", "Button", "CheckBox", "OptionButton", "ItemList", "TabBar"]  # Controls only: PopupMenu is a Window


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
	var size := Vector2i(UiFont.nominal(), 0)
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
	var one: float = f.get_string_size("Attack", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.nominal()).x
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


## The debt register, per FILE (adhoc census 2026-11-14 on .802: 40 sites in 26 files, 2 of them read-tier misses:
## CutsceneDialogue._box_metrics and BattleDialogue._dialogue_metrics, where one fallback font sizes a RichTextLabel
## body). The rest measure a Label or draw_string with the font they draw with, so they are right today; each lane
## converts its own to UiFont.of(node) / display() / body(). A conversion must lower or delete its row, and a new
## site anywhere reds: the assert is on the difference, so a stale or emptied table cannot pass quietly.
const FALLBACK_SITES := {
	"res://src/GameLoop.gd": 3,
	"res://src/ui/AbilitiesMenu.gd": 1,
	"res://src/ui/CutsceneGallery.gd": 1,
	"res://src/ui/DayClockWidget.gd": 1,
	"res://src/ui/EquipmentMenu.gd": 1,
	"res://src/ui/JobMenu.gd": 3,
	"res://src/ui/LensMenu.gd": 1,
	"res://src/ui/MenuChrome.gd": 1,
	"res://src/ui/QuestLog.gd": 1,
	"res://src/ui/RadialPicker.gd": 2,
	"res://src/ui/SettingsMenu.gd": 1,
	"res://src/ui/StatusMenu.gd": 1,
	"res://src/ui/Toast.gd": 1,
	"res://src/ui/Win98Menu.gd": 1,
	"res://src/ui/autobattle/AutobattleToggleUI.gd": 1,
	"res://src/ui/autogrind/AutogrindStatsStrip.gd": 1,
	"res://src/ui/autogrind/AutogrindSummary.gd": 2,
}


func test_no_new_site_measures_with_the_engine_fallback() -> void:
	var found := {}
	var files := _gd_files("res://src")
	assert_gt(files.size(), 300, "CONTROL: the sweep reads the source tree (%d files)" % files.size())
	for path in files:
		if path.ends_with("/UiFont.gd") or path.ends_with("/FontFallbacks.gd"):
			continue
		var n: int = FileAccess.get_file_as_string(path).count("ThemeDB.fallback_font")
		if n > 0:
			found[path] = n
	assert_gt(found.size(), 0, "CONTROL: the sweep finds today's sites (a sweep that reads nothing passes everything)")
	var wrong: Array = []
	for path in found:
		if int(found[path]) != int(FALLBACK_SITES.get(path, 0)):
			wrong.append("%s: %d in source, %d in FALLBACK_SITES" % [path, found[path], FALLBACK_SITES.get(path, 0)])
	for path in FALLBACK_SITES:
		if not found.has(path):
			wrong.append("%s: converted, delete its FALLBACK_SITES row" % path)
	assert_eq(wrong, [], "measure with UiFont.of(node) / display() / body(), not ThemeDB.fallback_font; keep FALLBACK_SITES exact")


## COWIR_UIFONT=off, a failed install, uninstall: a Label draws the ENGINE face, so a site converted to display()
## or body() must get that face too, or the off path recreates the very mismatch the conversion removes (controller 25431).
func test_off_the_accessors_hand_back_the_face_that_draws() -> void:
	UiFont.uninstall()
	assert_false(UiFont.is_installed(), "CONTROL: uninstalled")
	var lbl := Label.new()
	var drawn: Font = lbl.get_theme_font("font")
	lbl.free()
	assert_ne(drawn, UiFont._display, "CONTROL: uninstalled, a Label is not drawing the pixel face")
	assert_eq(UiFont.display(), drawn, "display() is the face a Label draws when the pixel face is off")
	assert_eq(UiFont.body(), ThemeDB.fallback_font, "body() too")
	assert_eq(UiFont.of(null), drawn, "of() with no node falls back to that same face")


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
