extends GutTest

## `HybridSpriteLoader` divides by a manifest-declared `frame_width` at four sites and multiplies by
## `frame_height`. The two are NOT the same hazard, which is why this file drives both:
##
## 🔑 MEASURED 2026-09-17, not assumed — a GDScript divide-by-zero ABORTS the enclosing function and
## the caller resumes with the return type's DEFAULT. So a zero WIDTH already ended at `null`, and a
## guard returning `null` is indistinguishable from the abort: an arm asserting `== null` on width
## cannot fail, and would have been a passing test of nothing.
##
## ⛔ A zero HEIGHT never divides, so it never aborts. Pre-guard the loader built `Rect2(x, 0, w, 0)`
## regions, printed "Loaded monster sheet", and returned a non-null SpriteFrames of INVISIBLE frames
## — so the procedural fallback never ran and the character was simply absent. That is the arm below.
const MANIFEST := "res://data/sprite_manifest.json"
const SECTIONS: Array[String] = ["monster_sheets", "sheets", "battle_effects"]
const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const PROBE := "_a_declared_sheet_probe"
const JOB_DIR := "res://assets/sprites/jobs/bard"


func after_each() -> void:
	# Loader._monster_manifest is a STATIC var: an injected key would reach every later test.
	Loader._monster_manifest.erase(PROBE)


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
			var fh: int = int((e as Dictionary).get("frame_height", 0))
			if fw <= 0 or fh <= 0:
				bad.append("%s/%s: declares frame %dx%d — the loader divides by the width and sizes its regions by the height" % [section, id, fw, fh])
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


## The monster path. Borrows a REAL declared sheet so the only difference from the control is height.
func test_a_zero_height_monster_declaration_refuses_instead_of_shipping_invisible_frames() -> void:
	Loader._load_manifest()
	var donor := _a_real_monster_id()
	assert_ne(donor, "", "PRECONDITION: need one real declared monster sheet to borrow")

	var control := Loader.load_monster_sprite_frames(donor)
	assert_not_null(control,
		"CONTROL: the unmodified donor must load. If it does not, the null below means nothing")

	var broken: Dictionary = (Loader._monster_manifest[donor] as Dictionary).duplicate(true)
	broken["frame_height"] = 0
	Loader._monster_manifest[PROBE] = broken
	assert_null(Loader.load_monster_sprite_frames(PROBE),
		("a sheet declaring zero-height frames must be REFUSED so the procedural fallback runs. "
		+ "Unguarded this returns a SpriteFrames of Rect2(x, 0, w, 0) regions and logs it as loaded, "
		+ "so the monster is invisible rather than absent — and nothing in the log says so"))


## The job path, driven directly: _load_external_sheet takes its declaration as an argument.
func test_a_zero_height_job_sheet_refuses_instead_of_shipping_invisible_frames() -> void:
	assert_true(DirAccess.dir_exists_absolute(JOB_DIR), "PRECONDITION: the donor job dir must exist")

	var control = Loader._load_external_sheet(_job_decl(256), "bard")
	assert_not_null(control,
		"CONTROL: the same declaration with a real height must load, or the null below is free")

	assert_null(Loader._load_external_sheet(_job_decl(0), "bard"),
		("a job sheet declaring zero-height frames must be REFUSED. Unguarded, `loaded_any` is set "
		+ "for an animation whose every frame is zero pixels tall, so the loader reports success"))


## Pins the maxi(1, …) floor by BEHAVIOUR rather than by its spelling: a sheet narrower than one
## declared frame must still come back, because cols_per_row 0 would abort on `frame_idx % 0`.
func test_a_sheet_narrower_than_one_frame_lays_out_rather_than_aborting() -> void:
	Loader._load_manifest()
	var donor := _a_real_monster_id()
	assert_ne(donor, "", "PRECONDITION: need one real declared monster sheet to borrow")

	var narrow: Dictionary = (Loader._monster_manifest[donor] as Dictionary).duplicate(true)
	var tex := load(str(narrow["path"])) as Texture2D
	assert_not_null(tex, "PRECONDITION: the donor sheet must load as a texture")
	narrow["frame_width"] = tex.get_width() * 2
	Loader._monster_manifest[PROBE] = narrow
	assert_not_null(Loader.load_monster_sprite_frames(PROBE),
		("a sheet narrower than one declared frame must lay out as a single column. Without the "
		+ "floor, cols_per_row is 0 and `frame_idx % cols_per_row` aborts the loader mid-build"))


func _a_real_monster_id() -> String:
	for id in Loader._monster_manifest:
		var e = Loader._monster_manifest[id]
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if int(d.get("frame_width", 0)) > 0 and int(d.get("frame_height", 0)) > 0 \
			and str(d.get("path", "")).ends_with(".png") and ResourceLoader.exists(str(d["path"])):
			return str(id)
	return ""


func _job_decl(frame_height: int) -> Dictionary:
	return {
		"path": JOB_DIR,
		"frame_width": 256,
		"frame_height": frame_height,
		"animations": ["idle"],
	}
