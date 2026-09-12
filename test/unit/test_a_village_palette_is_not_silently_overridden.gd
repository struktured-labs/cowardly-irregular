extends GutTest

## A village's hand-chosen cliff palette is OVERRIDDEN the moment its WORLD gets a tile sheet with
## cliff/overlay art — BaseVillage.gd:272 says so in as many words, and the override is silent.
##
## Today nothing is overridden, because `medieval` is the only sheet and no medieval village binds
## it. That is an OCCUPANCY fact, not a design one: generating the suburban atlas (free, no API
## cost, the tool is in tools/) would replace MapleHeights' NINE hand-picked colours with no test
## turning red and no line in any diff saying so.
##
## The established remedy is already in the tree: five villages carry `_get_cliff_sheet_key() -> ""`
## which forces the procedural palette. Grimhollow and Ironhaven got it in 7781579df; MapleHeights
## was in that same commit, got the richest palette of the three, and did NOT get the opt-out.
##
## So this arm does not forbid world art — it forbids world art arriving WITHOUT that decision.
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const VILLAGE_DIR := "res://src/maps/villages"
const MANIFEST := "res://data/sprite_manifest.json"
## The two source claims this whole file rests on. If either moves, the arms below are measuring
## a contract that no longer exists, so they are pinned rather than assumed.
const COUPLING_SITE := "res://src/maps/villages/BaseVillage.gd"
const ART_WINS_SITE := "res://src/exploration/EnvironmentTileSets.gd"


func _code(path: String) -> String:
	return GdSource.code_of(path)


## Body of `func <name>` up to the next top-level func, or EOF.
func _func_body(code: String, fname: String) -> String:
	var at := code.find("func %s" % fname)
	if at < 0:
		return ""
	var nxt := code.find("\nfunc ", at + 1)
	return code.substr(at) if nxt < 0 else code.substr(at, nxt - at)


func _village_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(VILLAGE_DIR)
	assert_not_null(dir, "village dir must open: %s" % VILLAGE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [VILLAGE_DIR, f])
	out.sort()
	return out


## key -> true when that sheet actually carries cliff or overlay regions (a props-only sheet
## does not touch the cliff palette, so it is not an override).
func _sheets_with_cliff_art() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	var parsed = JSON.parse_string(raw)
	var out: Dictionary = {}
	if not (parsed is Dictionary) or not (parsed.get("tile_sheets") is Dictionary):
		return out
	for key in parsed["tile_sheets"]:
		var entry = parsed["tile_sheets"][key]
		if entry is Dictionary and ((entry.get("cliff") is Dictionary and not entry["cliff"].is_empty()) \
				or (entry.get("overlay") is Dictionary and not entry["overlay"].is_empty())):
			out[key] = true
	return out


## The world key a village binds, by reading its generator's own `_get_sheet_key`.
func _world_key_of(code: String) -> String:
	var re := RegEx.new()
	re.compile("res://src/exploration/([A-Za-z]+TileGenerator)\\.gd")
	var m := re.search(code)
	if m == null:
		return ""
	var gen_path := "res://src/exploration/%s.gd" % m.get_string(1)
	if not ResourceLoader.exists(gen_path) and not FileAccess.file_exists(gen_path):
		return ""
	var body := _func_body(_code(gen_path), "_get_sheet_key")
	var kre := RegEx.new()
	kre.compile("return \"([^\"]*)\"")
	var km := kre.search(body)
	return "" if km == null else km.get_string(1)


func _survey() -> Array:
	var rows: Array = []
	for path in _village_files():
		var code := _code(path)
		var pal := _func_body(code, "_get_cliff_palette")
		var custom := pal.contains("Color(")
		var key_body := _func_body(code, "_get_cliff_sheet_key")
		var opted_out := key_body != "" and key_body.contains("return \"\"")
		rows.append({
			"file": path.get_file(),
			"custom_palette": custom,
			"opted_out": opted_out,
			"world": "" if opted_out else _world_key_of(code),
		})
	return rows


func test_no_village_palette_is_silently_overridden_by_its_world_sheet() -> void:
	var sheets := _sheets_with_cliff_art()
	var offenders: Array = []
	for r in _survey():
		if r["custom_palette"] and not r["opted_out"] and sheets.has(r["world"]):
			offenders.append("%s: hand-picked palette, binds sheet '%s' which has cliff/overlay art — the palette is DEAD. Either add `func _get_cliff_sheet_key() -> String: return \"\"` (as Grimhollow/Ironhaven do), or delete _get_cliff_palette() to say the sheet is intended." % [r["file"], r["world"]])
	assert_eq(offenders.size(), 0,
		"a village's cliff palette is overridden by its world sheet with nothing saying so:\n  %s" % "\n  ".join(offenders))


## ⛔ ANTI-VACUITY. Every arm above passes trivially on an empty survey, a survey where nothing has
## a palette, or one where no world key ever resolved. Each of those is a plausible breakage.
func test_the_survey_actually_found_villages_palettes_and_worlds() -> void:
	var rows := _survey()
	assert_gt(rows.size(), 5, "village survey found %d files — the walk is broken" % rows.size())
	var with_palette := 0
	var with_optout := 0
	var with_world := 0
	for r in rows:
		if r["custom_palette"]:
			with_palette += 1
		if r["opted_out"]:
			with_optout += 1
		if r["world"] != "":
			with_world += 1
	assert_gt(with_palette, 0, "no village has a custom cliff palette — _get_cliff_palette parsing is broken")
	assert_gt(with_optout, 0, "no village opts out — _get_cliff_sheet_key parsing is broken, so nothing can be excused")
	assert_gt(with_world, 0, "no village resolved a world key — generator preload parsing is broken, so nothing can be flagged")


## The guard is only meaningful while a sheet BEATS the palette. Pinned from source, not assumed.
func test_the_override_this_file_guards_against_is_still_the_contract() -> void:
	var base := _code(COUPLING_SITE)
	assert_true(base.contains("tile_generator._get_sheet_key()"),
		"BaseVillage no longer derives its cliff sheet key from the tile generator — this file's world mapping is stale")
	var env := _code(ART_WINS_SITE)
	var art_or := _func_body(env, "_art_or")
	assert_true(art_or.contains("TileSheetManifest.region"),
		"_art_or no longer consults TileSheetManifest — art may no longer beat the palette, re-derive this guard")
	assert_true(art_or.contains("procedural"),
		"_art_or no longer falls back to the procedural image — the override shape has changed")


## The manifest reader must actually see the sheet that EXISTS, or the offender test is vacuous:
## an empty sheet set excuses every village by construction.
func test_the_manifest_reader_sees_the_medieval_sheet() -> void:
	var sheets := _sheets_with_cliff_art()
	assert_true(sheets.has("medieval"),
		"medieval has cliff/overlay regions in data/sprite_manifest.json but the reader did not see it — every village would be excused: %s" % str(sheets.keys()))
