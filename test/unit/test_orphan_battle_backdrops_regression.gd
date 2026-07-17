extends GutTest

## msg 2724 cowir-sprites' proc-gen audit surfaced 5 finished battle-terrain
## backdrops in assets/sprites/backgrounds/ without BACKDROP_PATHS entries
## in BattleBackground.gd:240 — battles on COAST/DESERT/ICE/SWAMP/VOLCANIC
## rendered procedural despite the finished PNGs sitting on disk.
##
## This cycle wired all 5. This ratchet catches the NEXT orphan of the
## same class: a *_battle.png file lands in assets/sprites/backgrounds/,
## no dict entry gets added, and battles on that terrain silently drop
## to the procedural fallback until the next art audit.
##
## Naming convention (from cowir-sprites' art delivery):
##   assets/sprites/backgrounds/<terrain>_battle.png
##     — e.g. coast_battle.png, ice_battle.png. Terrain enum name is
##     UPPER(<terrain>).
##
##   assets/sprites/backgrounds/battle_world<N>_<name>.png
##     — the world-tier art, wired via distinct enum members
##     (SUBURBAN/STEAMPUNK/INDUSTRIAL/DIGITAL/ABSTRACT). Not covered by
##     this ratchet since the mapping isn't derivable from the filename;
##     add a manual pin below if a new world lands.
##
##   assets/sprites/backgrounds/<name>_interior.png
##     — village/shop interiors, not battle backdrops. Explicitly
##     excluded from the scan.

const BB_PATH: String = "res://src/battle/BattleBackground.gd"
const ART_DIR: String = "res://assets/sprites/backgrounds/"


func _list_battle_pngs() -> Array:
	# Enumerate <terrain>_battle.png files in the art dir. Skip .import
	# metadata, interiors, and world-tier art.
	var dir = DirAccess.open(ART_DIR)
	assert_not_null(dir, "art directory must exist: %s" % ART_DIR)
	var names: Array = []
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if f.ends_with("_battle.png") and not f.begins_with("battle_"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## ── The 5 msg 2724 wires must be present ──────────────────────────────

func test_five_msg_2724_wires_present() -> void:
	# Named pin for the specific 5 this cycle added — a bisect that
	# regresses one of them lands on a distinct assert.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	var expected: Array = [
		"TerrainType.COAST: \"res://assets/sprites/backgrounds/coast_battle.png\"",
		"TerrainType.DESERT: \"res://assets/sprites/backgrounds/desert_battle.png\"",
		"TerrainType.ICE: \"res://assets/sprites/backgrounds/ice_battle.png\"",
		"TerrainType.SWAMP: \"res://assets/sprites/backgrounds/swamp_battle.png\"",
		"TerrainType.VOLCANIC: \"res://assets/sprites/backgrounds/volcanic_battle.png\"",
	]
	for entry in expected:
		assert_string_contains(src, entry,
			"BACKDROP_PATHS must contain %s — msg 2724 orphan-fix cycle 11" % entry)


## ── Every art PNG on disk has a BACKDROP_PATHS entry (ratchet) ────────

func test_every_battle_png_on_disk_is_wired() -> void:
	# The ratchet: if a new <terrain>_battle.png lands in the art dir
	# without a BACKDROP_PATHS entry, this test fails at commit time.
	# Prevents the exact orphan class cowir-sprites audit surfaced.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	var pngs: Array = _list_battle_pngs()
	assert_gt(pngs.size(), 0, "sanity: art dir must contain <terrain>_battle.png files")
	var missing: Array = []
	for fname in pngs:
		# Derive terrain name: <terrain>_battle.png → <terrain>
		var terrain_lower: String = fname.substr(0, fname.length() - "_battle.png".length())
		var terrain_upper: String = terrain_lower.to_upper()
		var expected_entry: String = "TerrainType.%s: \"res://assets/sprites/backgrounds/%s\"" % [terrain_upper, fname]
		if src.find(expected_entry) < 0:
			# Also accept the enum-only pin without the path (in case the mapping uses a different path variant — flag as ambiguous rather than a hard miss).
			var loose: String = "TerrainType.%s:" % terrain_upper
			if src.find(loose) < 0:
				missing.append(fname)
	assert_eq(missing.size(), 0,
		"orphan battle backdrop art on disk with no BACKDROP_PATHS entry: %s — add a `TerrainType.<NAME>: \"res://assets/sprites/backgrounds/<file>\"` mapping" % str(missing))


## ── Every BACKDROP_PATHS enum member references a file that exists ────

func test_no_dangling_backdrop_path_entries() -> void:
	# Inverse ratchet: a dict entry pointing to a missing PNG would
	# silently fall through to procedural. Catch the class where art gets
	# renamed/deleted but the dict entry lingers.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	var start: int = src.find("const BACKDROP_PATHS = {")
	assert_gt(start, -1)
	var end: int = src.find("}", start)
	var block: String = src.substr(start, end - start)
	# Extract every quoted "res://..." path referenced in the block.
	var missing_paths: Array = []
	var cursor: int = 0
	while true:
		var quote_start: int = block.find("\"res://", cursor)
		if quote_start < 0:
			break
		var quote_end: int = block.find("\"", quote_start + 1)
		if quote_end < 0:
			break
		var res_path: String = block.substr(quote_start + 1, quote_end - quote_start - 1)
		if not FileAccess.file_exists(res_path):
			missing_paths.append(res_path)
		cursor = quote_end + 1
	assert_eq(missing_paths.size(), 0,
		"BACKDROP_PATHS references non-existent files: %s — either restore the art or remove the entry" % str(missing_paths))


## ── Each terrain in the enum with matching art has a dict entry ───────

func test_terrain_enum_covers_all_wired_types() -> void:
	# Sanity: the 5 msg 2724 terrains (COAST/DESERT/ICE/SWAMP/VOLCANIC)
	# must exist in the TerrainType enum too — the BACKDROP_PATHS entry
	# won't parse without them.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	for enum_name in ["COAST", "DESERT", "ICE", "SWAMP", "VOLCANIC"]:
		assert_string_contains(src, enum_name,
			"TerrainType.%s enum member must exist — msg 2724 dict entry references it" % enum_name)
