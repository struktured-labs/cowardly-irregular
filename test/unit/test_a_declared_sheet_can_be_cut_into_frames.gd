extends GutTest

## `HybridSpriteLoader` computes `cols_per_row = texture.get_width() / frame_width` and then indexes
## with `frame_idx % cols_per_row`. Integer modulo by zero RAISES in GDScript, so a sheet narrower
## than ONE declared frame does not render badly — it aborts the loader and the monster gets no
## frames at all.
##
## ⛔ THE CODE IS NOW GUARDED AT BOTH SITES, and this arm guards the INPUT, because the guard turns
## an abort into a silently wrong single-column layout. Refusing to divide is not the same as
## having something sensible to divide.
##
## 🔑 A DIVISOR, NOT AN INDEX. This lane's empty-list sweep came back clean on this file — no
## `size() - 1`, no clamp — because the hazard reaches `/` and `%` instead of `[]`. cowir-sfx named
## the class 2026-09-17; it is the second instance found in this lane the same morning, after
## MasteriteEncounter's frame divisor.
const MANIFEST := "res://data/sprite_manifest.json"
const SECTIONS: Array[String] = ["monster_sheets", "sheets", "battle_effects"]


func test_every_declared_sheet_is_at_least_one_frame_wide() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse")
	var m: Dictionary = parsed

	var bad: Array = []
	var checked := 0
	for section in SECTIONS:
		var node = m.get(section, {})
		if not (node is Dictionary):
			continue
		for id in node:
			var e = node[id]
			if not (e is Dictionary):
				continue
			if not (e as Dictionary).has("frame_width"):
				continue
			var fw: int = int((e as Dictionary)["frame_width"])
			if fw <= 0:
				bad.append("%s/%s: declares frame_width %d — the loader divides by this" % [section, id, fw])
				continue
			var path := str((e as Dictionary).get("path", ""))
			if path == "" or not path.ends_with(".png") or not ResourceLoader.exists(path):
				continue
			var tex := load(path) as Texture2D
			if tex == null:
				continue
			checked += 1
			if tex.get_width() / fw < 1:
				bad.append("%s/%s: %dpx wide but declares %dpx frames — cols_per_row is 0 and the "
					% [section, id, tex.get_width(), fw]
					+ "frame loop does `frame_idx %% cols_per_row`")
	assert_gt(checked, 100,
		"ANTI-VACUITY: only %d declared sheets were readable — the scan is measuring almost nothing" % checked)
	bad.sort()
	assert_eq(bad, [],
		("a declared sheet cannot be cut into even one frame. The loader is guarded, so this no "
		+ "longer aborts — it silently lays the sheet out as a single column instead, which is a "
		+ "wrong picture rather than a missing one: %s") % [bad])


## ⛔ BOTH DIVISION SITES, because one was guarded and one was not for the whole life of the file.
func test_neither_cols_per_row_site_divides_unguarded() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/battle/sprites/HybridSpriteLoader.gd")
	assert_gt(code.length(), 2000, "PRECONDITION: the loader must be readable and stripped")

	assert_eq(code.count("cols_per_row: int = maxi(1, texture.get_width() / frame_width)"), 2,
		("both cols_per_row sites must clamp to at least one column. They differed for the life of "
		+ "this file — monster_frame_texture guarded, load_monster_sprite_frames not — and a "
		+ "modulo by zero aborts the loader rather than drawing something wrong"))
	assert_false(code.contains("int = texture.get_width() / frame_width"),
		"the unguarded form is what this replaced")
