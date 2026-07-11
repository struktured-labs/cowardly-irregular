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
