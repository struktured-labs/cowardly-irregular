extends Node

## FontFallbacks — chains Noto Sans Symbols 2 + Noto Emoji (both OFL, see
## assets/fonts/fallback/OFL.txt) behind the default UI font. The bundled
## Open Sans has zero symbol coverage, so every authored icon glyph
## (⚔ ✓ ★ 🔥 ⌫ …) rendered as a tofu box on web, where no system-font
## fallback exists (2026-07-10 web-smoke find). Runs as an autoload so the
## chain is live before any UI draws.

const FALLBACK_PATHS := [
	"res://assets/fonts/fallback/NotoSansSymbols2-Regular.ttf",
	"res://assets/fonts/fallback/NotoSansSymbols-Regular.ttf",
	"res://assets/fonts/fallback/NotoSansMath-Regular.ttf",
	"res://assets/fonts/fallback/NotoEmoji-Regular.ttf",
]


func _enter_tree() -> void:
	# Headless roots are 64x64: canvas_items scales them 0.05x and font metrics inflate (16px measures 48), so tests keep the 720p frame.
	if DisplayServer.get_name() == "headless":
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var chain: Array[Font] = []
	for path in FALLBACK_PATHS:
		var f = load(path)
		if f is Font:
			chain.append(f)
		else:
			push_warning("[FontFallbacks] failed to load %s" % path)
	if chain.is_empty():
		push_warning("[FontFallbacks] no fallback fonts loaded — symbol glyphs will tofu")
		return
	var base := ThemeDB.fallback_font
	if base != null:
		base.fallbacks = chain
	get_tree().node_added.connect(_on_node_added)


## Every Label inherits the stretch below; correct each one that has not chosen its own line_spacing.
func _on_node_added(n: Node) -> void:
	if not (n is Label):
		return
	_correct_label(n)
	if not n.theme_changed.is_connected(_correct_label.bind(n)):
		n.theme_changed.connect(_correct_label.bind(n))


## Marked with LSC_META so a label's OWN line_spacing override is never replaced, and a font-size change re-measures.
const LSC_META := &"fallback_line_spacing"


func _correct_label(l: Label) -> void:
	if not is_instance_valid(l):
		return
	if l.has_theme_constant_override("line_spacing") and not l.has_meta(LSC_META):
		return
	var v: int = cached_correction(l.get_theme_font("font"), l.get_theme_font_size("font_size"))
	if l.has_meta(LSC_META) and int(l.get_meta(LSC_META)) == v:
		return
	l.set_meta(LSC_META, v)
	l.add_theme_constant_override("line_spacing", v)


static var _corrections: Dictionary = {}


static func cached_correction(font: Font, font_size: int) -> int:
	if font == null:
		return 0
	var key := "%d:%d" % [font.get_instance_id(), font_size]
	if not _corrections.has(key):
		_corrections[key] = line_spacing_correction(font, font_size)
	return int(_corrections[key])


## How far the symbol fallbacks stretch a line past the base font's own height (NotoSansSymbols: 28 vs ~18 at 13px), as a line_spacing correction.
static func line_spacing_correction(font: Font, font_size: int) -> int:
	if font == null or font.fallbacks.is_empty():
		return 0
	var solo: Font = font.duplicate()
	solo.fallbacks = []
	return mini(0, int(solo.get_height(font_size) - font.get_height(font_size)))


static var _baseline_lifts: Dictionary = {}


## How far to raise a top-aligned single-line Label so the BASE font's glyphs sit centred in a row of row_h (NotoSansSymbols lifts the chain ascent 18 -> 24 at 16px).
static func row_label_y(font: Font, font_size: int, row_h: float) -> int:
	if font == null:
		return 0
	var key := "%d:%d:%d" % [font.get_instance_id(), font_size, int(row_h)]
	if not _baseline_lifts.has(key):
		var solo: Font = font.duplicate()
		solo.fallbacks = []
		var glyph_h: float = solo.get_ascent(font_size) + solo.get_descent(font_size)
		_baseline_lifts[key] = roundi((row_h - glyph_h) * 0.5 + solo.get_ascent(font_size) - font.get_ascent(font_size))
	return int(_baseline_lifts[key])
