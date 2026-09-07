extends GutTest

## Regression (web-smoke find 2026-07-10): ObjectiveArrow's directional
## chevrons (▲▼◄►◤◥◣◢), MapBorderIndicator's edge arrows, and QuestTracker's
## ►/◇ prefixes ALL rendered as tofu boxes — the bundled Open Sans has no
## geometric-shape glyphs, and web has no system-font fallback. The widget's
## entire purpose (direction) was invisible. These always-on-HUD files must
## only use characters the runtime fallback font can actually draw.

const HUD_FILES := [
	"res://src/exploration/ObjectiveArrow.gd",
	"res://src/exploration/MapBorderIndicator.gd",
	"res://src/exploration/QuestTracker.gd",
]


func test_nav_hud_string_literals_have_font_coverage() -> void:
	var font := ThemeDB.fallback_font
	assert_not_null(font, "runtime fallback font must exist")
	var literal_rx := RegEx.create_from_string("\"([^\"\\n]*)\"")
	var missing: Dictionary = {}
	for path in HUD_FILES:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.is_empty(), "%s must be readable" % path)
		for m in literal_rx.search_all(src):
			for ch in m.get_string(1):
				if ch.unicode_at(0) > 127 and not font.has_char(ch.unicode_at(0)):
					missing["%s (U+%04X)" % [ch, ch.unicode_at(0)]] = path
	assert_eq(missing.size(), 0,
		"nav-HUD glyphs with NO font coverage render as tofu boxes (char → file): %s" % str(missing))


func test_objective_arrow_table_is_directional() -> void:
	# The 8-way table must stay distinguishable per direction — the tofu bug
	# made all 8 render identically, which is the failure mode to pin against.
	var seen := {}
	for key in ObjectiveArrow.ARROWS:
		var v: String = ObjectiveArrow.ARROWS[key]
		assert_false(seen.has(v), "arrow text '%s' reused for %s and %s" % [v, seen.get(v, ""), key])
		seen[v] = key
	assert_eq(seen.size(), 8, "all 8 directions present")
