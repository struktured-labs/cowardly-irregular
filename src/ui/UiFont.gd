extends RefCounted
class_name UiFont

## The one place the UI's typeface comes from (struktured 2026-11-11: "I like this digital old school font look
## you got going on for victory / dmg numbers ... lets use that as much as we are able for all fonts").
##
## The damage numbers are PixelText: drawn glyphs, not a font, so a Label could never use them. This builds a
## real bitmap FontFile from the SAME glyph table (plus UiFontGlyphs' lowercase and punctuation), so Labels,
## Buttons, wrapping and BBCode all work, and anything the table does not draw falls through to the old face and
## its Noto chain instead of turning to tofu.
##
## Two tiers. DISPLAY (headings, menu rows, labels, numbers) is the pixel face and is the theme default.
## BODY (text you read in sentences, text you type) is whatever `read_tier` says: the old face, or the pixel one.
##
## A 5x7 face is only sharp at whole multiples, so sizes SNAP: a requested size draws at
## round(size / nominal()) times the drawn pixels (never below 1x). Measure with the font, not with arithmetic.
##
## Anything that measures or draws text itself asks here, never ThemeDB.fallback_font:
##   UiFont.of(node)      the font that node really draws with (use this when you have the node)
##   UiFont.display()     the pixel face     UiFont.body()    the reading face

const FACE_NAME := "Cowir Pixel 5x7"
## The requested size that draws the glyphs 1:1; a size draws at round(size / nominal) times that, never below 1x.
## It decides where the steps fall: 10 = 1x up to 14 px, 2x from 15 (the first collage: rows and their small
## print came out one size) · 9 = 2x from 14 · 8 = 2x from 12, 3x from 20. COWIR_UIFONT_NOMINAL overrides it
## for a render; the shipped value is this constant.
const NOMINAL_SIZE := 9
const NOMINAL_CHOICES := [8, 9, 10]
static var _nominal: int = 0
const ROWS := 7
const DESCENT_ROWS := 2
const ASCENT := 9
const DESCENT := 3
const SPACE_ADVANCE := 3
const ATLAS_COLS := 16
const READ_TIER_DEFAULT := "default"
const READ_TIER_PIXEL := "pixel"
## Theme slots that carry text you READ or TYPE; they follow read_tier.
const READ_SLOTS := {
	"RichTextLabel": ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"],
	"LineEdit": ["font"],
	"TextEdit": ["font"],
	"TooltipLabel": ["font"],
}

static var read_tier: String = READ_TIER_DEFAULT
static var _display: FontFile = null
static var _outlined: FontFile = null
static var _body: Font = null
static var _stock: Dictionary = {}
static var _installed: bool = false


## Every character the face draws itself, as { char: rows }.
static func glyph_table() -> Dictionary:
	var t: Dictionary = PixelText.GLYPHS.duplicate()
	for k in UiFontGlyphs.GLYPHS:
		t[k] = UiFontGlyphs.GLYPHS[k]
	for k in UiFontGlyphs.OVERRIDES:
		t[k] = UiFontGlyphs.OVERRIDES[k]
	for k in UiFontGlyphs.ALIASES:
		t[k] = t[UiFontGlyphs.ALIASES[k]]
	return t


static func draws(ch: String) -> bool:
	return ch == " " or glyph_table().has(ch)


## The pixel face. `outlined` bakes PixelText's dark rim and shadow in, for light text over art; never use it
## with a dark text colour (the rim and the ink become one blob).
static func display(outlined: bool = false) -> Font:
	_ensure_built()
	return _outlined if outlined else _display


## The reading face: the engine's own, with the symbol chain FontFallbacks hangs behind it.
static func body() -> Font:
	_ensure_built()
	return _display if read_tier == READ_TIER_PIXEL else _body


## The font a node draws with, so a measurement and the drawing can never be two fonts.
static func of(c: Control, slot: StringName = &"") -> Font:
	if c == null or not is_instance_valid(c):
		return display()
	var key: StringName = slot
	if key == &"":
		key = &"normal_font" if c is RichTextLabel else &"font"
	var f: Font = c.get_theme_font(key)
	return f if f != null else display()


## Put a node in the reading tier whatever its class (a wrapped Label that holds a description).
static func as_body(c: Control, slot: StringName = &"font") -> void:
	if c != null and is_instance_valid(c):
		c.add_theme_font_override(slot, body())


static func nominal() -> int:
	if _nominal == 0:
		var asked: int = int(OS.get_environment("COWIR_UIFONT_NOMINAL"))
		_nominal = asked if asked in NOMINAL_CHOICES else NOMINAL_SIZE
	return _nominal


static func scale_for(font_size: int) -> int:
	return maxi(1, roundi(float(font_size) / float(nominal())))


static func is_installed() -> bool:
	return _installed


## Make the pixel face the default everywhere. Called once by FontFallbacks after it has chained the symbols.
static func install(tier: String = "") -> void:
	# The one switch back to the old face (the collage's "before" frames; a way out if a screen is unreadable).
	if OS.get_environment("COWIR_UIFONT") == "off":
		print("[UIFONT] face=engine-default (COWIR_UIFONT=off)")
		return
	_ensure_built()
	var env: String = OS.get_environment("COWIR_UIFONT_READ")
	if tier != "":
		read_tier = tier
	elif env == READ_TIER_PIXEL or env == READ_TIER_DEFAULT:
		read_tier = env
	var theme: Theme = ThemeDB.get_default_theme()
	if _display == null or theme == null:
		push_error("[UIFONT] NOT installed: face=%s theme=%s. The UI is drawing the engine default." % [_display, theme])
		return
	# Before the default changes: a read slot the engine left empty resolves to the default font, so read
	# afterwards it would "be" the pixel face and the read tier could never keep the old one.
	_capture_stock(theme)
	theme.default_font = _display
	ThemeDB.fallback_font = _display
	_apply_read_tier(theme)
	_installed = true
	print("[UIFONT] face=%s glyphs=%d nominal=%d read_tier=%s" % [FACE_NAME, glyph_table().size(), nominal(), read_tier])


## Undo install (tests, and the collage's "before" frames).
static func uninstall() -> void:
	if not _installed:
		return
	var theme: Theme = ThemeDB.get_default_theme()
	theme.default_font = _body
	ThemeDB.fallback_font = _body
	for type in READ_SLOTS:
		for slot in READ_SLOTS[type]:
			var key := "%s/%s" % [type, slot]
			if _stock.get(key) != null:
				theme.set_font(slot, type, _stock[key])
			else:
				theme.clear_font(slot, type)
	_installed = false


static func _capture_stock(theme: Theme) -> void:
	for type in READ_SLOTS:
		for slot in READ_SLOTS[type]:
			var key := "%s/%s" % [type, slot]
			if _stock.has(key):
				continue
			var f: Font = theme.get_font(slot, type) if theme.has_font(slot, type) else null
			_stock[key] = f if (f != null and f != _display) else null


static func _apply_read_tier(theme: Theme) -> void:
	for type in READ_SLOTS:
		for slot in READ_SLOTS[type]:
			var key := "%s/%s" % [type, slot]
			match read_tier:
				READ_TIER_PIXEL:
					theme.set_font(slot, type, _display)
				_:
					theme.set_font(slot, type, _stock.get(key) if _stock.get(key) != null else _body)


static func _ensure_built() -> void:
	if _display != null:
		return
	_body = ThemeDB.fallback_font
	_display = _build(false)
	_outlined = _build(true)
	if _body != null:
		# Flat, so "the symbol fonts are on the default font's chain" stays true for everything that walks it.
		var chain: Array[Font] = [_body]
		for fb in _body.fallbacks:
			chain.append(fb)
		_display.fallbacks = chain
		_outlined.fallbacks = chain


static func _build(rim: bool) -> FontFile:
	var table: Dictionary = glyph_table()
	var nom: int = nominal()
	var pad: int = 1 if rim else 0
	var cell := Vector2i(5 + pad * 2 + 2, ROWS + DESCENT_ROWS + pad * 2 + 2)
	var chars: Array = table.keys()
	var grid_rows: int = int(ceil(float(chars.size()) / float(ATLAS_COLS)))
	var img := Image.create(cell.x * ATLAS_COLS, cell.y * grid_rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var f := FontFile.new()
	f.font_name = FACE_NAME
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.generate_mipmaps = false
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.fixed_size = nom
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	var size := Vector2i(nom, 0)
	f.set_cache_ascent(0, nom, ASCENT)
	f.set_cache_descent(0, nom, DESCENT)
	f.set_cache_underline_position(0, nom, 1.0)
	f.set_cache_underline_thickness(0, nom, 1.0)
	f.set_cache_scale(0, nom, 1.0)
	var rects: Dictionary = {}
	for i in chars.size():
		var ch: String = chars[i]
		var rows: Array = table[ch]
		var w: int = str(rows[0]).length()
		var origin := Vector2i((i % ATLAS_COLS) * cell.x, (i / ATLAS_COLS) * cell.y)
		var ink := {}
		for y in rows.size():
			for x in w:
				if str(rows[y])[x] == "#":
					ink[origin + Vector2i(x + pad, y + pad)] = true
		if rim:
			var edge := {}
			for p in ink:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var q: Vector2i = p + Vector2i(dx, dy)
						if not ink.has(q):
							edge[q] = true
			for p in edge.keys() + ink.keys():
				var s: Vector2i = p + Vector2i(1, 1)
				if not ink.has(s) and not edge.has(s):
					img.set_pixelv(s, PixelText.SHADOW)
			for p in edge:
				img.set_pixelv(p, PixelText.OUTLINE)
		for p in ink:
			img.set_pixelv(p, Color.WHITE)
		rects[ch] = Rect2(origin, Vector2(w + pad * 2 + pad, rows.size() + pad * 2 + pad))
	f.set_texture_image(0, size, 0, img)
	for ch in rects:
		var code: int = ch.unicode_at(0)
		var r: Rect2 = rects[ch]
		f.set_glyph_advance(0, nom, code, Vector2(str(table[ch][0]).length() + 1, 0))
		f.set_glyph_offset(0, size, code, Vector2(-pad, -ROWS - pad))
		f.set_glyph_size(0, size, code, r.size)
		f.set_glyph_uv_rect(0, size, code, r)
		f.set_glyph_texture_idx(0, size, code, 0)
	var space: int = " ".unicode_at(0)
	f.set_glyph_advance(0, nom, space, Vector2(SPACE_ADVANCE, 0))
	f.set_glyph_offset(0, size, space, Vector2.ZERO)
	f.set_glyph_size(0, size, space, Vector2.ZERO)
	f.set_glyph_uv_rect(0, size, space, Rect2())
	f.set_glyph_texture_idx(0, size, space, -1)
	return f
