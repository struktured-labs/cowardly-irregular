extends GutTest

## tick 89 regression: TERRAIN_PALETTES must have entries for every
## TerrainType that BACKDROP_PATHS covers. Without a palette entry,
## the procedural fallback at line ~444 falls back to PLAINS colors
## (green) — wrong for SUBURBAN/STEAMPUNK/INDUSTRIAL/DIGITAL/ABSTRACT.
##
## In practice the artist backdrop loads, so the palette is unused —
## but the moment a backdrop .png goes missing or fails to import,
## a player's W3 Steampunk battle would render with the PLAINS
## green-fields palette instead of brass/copper. Defense in depth.

const BATTLE_BG := "res://src/battle/BattleBackground.gd"


## TerrainType keys that must have a TERRAIN_PALETTES entry.
const REQUIRED_TERRAIN_KEYS: Array[String] = [
	"PLAINS", "CAVE", "FOREST", "VILLAGE", "BOSS",
	"ICE", "DESERT", "SWAMP", "COAST", "VOLCANIC",
	"SUBURBAN", "STEAMPUNK", "INDUSTRIAL", "DIGITAL", "ABSTRACT",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _terrain_palettes_body() -> String:
	var src := _read(BATTLE_BG)
	var idx: int = src.find("const TERRAIN_PALETTES")
	assert_gt(idx, -1, "TERRAIN_PALETTES const must exist")
	# Scope to the closing brace of the const declaration. The const
	# ends with the matching `}` at column 0.
	var search_from: int = idx
	var depth: int = 0
	var pos: int = src.find("{", search_from)
	assert_gt(pos, -1, "TERRAIN_PALETTES opening brace must exist")
	depth = 1
	pos += 1
	while pos < src.length() and depth > 0:
		var ch: String = src.substr(pos, 1)
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
		pos += 1
	return src.substr(idx, pos - idx)


func test_every_required_terrain_has_palette_entry() -> void:
	# Pin: each REQUIRED_TERRAIN_KEYS entry must appear as a key in
	# the TERRAIN_PALETTES const body.
	var body := _terrain_palettes_body()
	for key in REQUIRED_TERRAIN_KEYS:
		var pattern: String = "TerrainType." + key + ":"
		assert_true(body.contains(pattern),
			"TERRAIN_PALETTES must have entry for TerrainType.%s — procedural fallback at line ~444 falls back to PLAINS green when missing" % key)


func test_w2_w6_palettes_distinct_from_plains() -> void:
	# Negative pin: each W2-W6 palette must NOT be a verbatim copy of
	# PLAINS. Otherwise the procedural fallback would render PLAINS-
	# looking but pretend to be world-themed.
	var body := _terrain_palettes_body()
	# PLAINS sky_top is Color(0.08, 0.12, 0.32) — distinctive enough to
	# be a sanity anchor.
	const PLAINS_SKY_TOP: String = "Color(0.08, 0.12, 0.32)"
	# Count occurrences — should appear EXACTLY ONCE (only in PLAINS).
	# If a W2-W6 entry accidentally copy-pasted PLAINS values, this
	# string would appear more than once.
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = body.find(PLAINS_SKY_TOP, pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 1,
		"Color(0.08, 0.12, 0.32) (PLAINS sky_top) must appear EXACTLY ONCE in TERRAIN_PALETTES — multiple occurrences mean a W2-W6 entry copy-pasted PLAINS colors")


func test_each_w2_w6_palette_has_minimum_fields() -> void:
	# Defensive: each palette dict must have the same required keys
	# the procedural draw paths read (sky_top, sky_mid, sky_bottom,
	# ground, ground_dark, ground_light, accent, horizon). A missing
	# key would crash _draw_gradient.
	var body := _terrain_palettes_body()
	var required_fields: Array[String] = [
		"sky_top", "sky_mid", "sky_bottom",
		"ground", "ground_dark", "ground_light",
		"accent", "horizon",
	]
	# Scope each W2-W6 palette block.
	for terrain in ["SUBURBAN", "STEAMPUNK", "INDUSTRIAL", "DIGITAL", "ABSTRACT"]:
		var key: String = "TerrainType." + terrain + ":"
		var start: int = body.find(key)
		assert_gt(start, -1, "TerrainType.%s must exist" % terrain)
		# Block ends at the next TerrainType. line or the closing of TERRAIN_PALETTES.
		var next_terrain: int = body.find("TerrainType.", start + 1)
		var block: String = body.substr(start, next_terrain - start) if next_terrain > -1 else body.substr(start)
		for field in required_fields:
			assert_true(block.contains("\"" + field + "\":"),
				"TerrainType.%s palette must have '%s' field — procedural _draw_gradient depends on it" % [terrain, field])
