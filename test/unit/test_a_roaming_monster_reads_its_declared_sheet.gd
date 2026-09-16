extends GutTest

## `RoamingMonster` hardcoded THREE facts the manifest already declares, and read the section
## for none of them:
##
##   FRAME_W / FRAME_H = 32       overworld_monster_sheets[id].frame_width / frame_height
##   SHEET_COLS = 4               animations.walk_*.frames
##   rows 0=down 1=left 2=right   animations.walk_*.row
##   3=up, written into _update_row_from_move_dir
##
## Every shipped sheet agreed with all three conventions when this was written (2026-09-16), so
## each hardcoded value is correct and none is enforced. The agreement is DERIVED rather than
## restated here — test_the_roster_agreeing_with_the_convention_is_recorded_not_assumed reds the
## day it stops holding, which is the point: a count in this comment would go stale silently
## and none of them is enforced. A sheet at another frame size is mis-sliced; a sheet that orders
## its rows differently WALKS FACING THE WRONG WAY, with nothing failing. This is the same defect
## the player's own walk sheet carried an hour ago, on the second consumer of the same convention.
##
## 🔑 AND THE LESSON FROM THAT ONE IS APPLIED HERE RATHER THAN RE-LEARNED. Deriving the CUT while
## the render stayed native would trade a mis-sliced monster for an oversized one: `TOUCH_RADIUS_PX`
## is documented as "~1.4x the 32px sprite half-width" and the placeholder is drawn at FRAME_W, so
## both assume the rendered size. The sheet is cut at its DECLARED frame and the sprite is scaled
## back to the CONVENTION, which leaves every downstream assumption true by construction.
## cowir-cutscenes' rule: one half derived and one half guessing is worse than both guessing.
##
## ⚠️ AND THE LIMIT, MEASURED RATHER THAN ASSUMED: every shipped entry declares exactly what the
## constants encode, so an owner that IGNORED the manifest and returned the convention passes every
## arm here. Mutating it alone is GREEN, and that is expected rather than a hole. The proof is a
## PAIR — declare slime's walk_down on row 3 AND blind the owner, and the first arm reds naming the
## key. Neither half is evidence; the pair is. Same shape as the player's sheet one hour ago.
const GuardSubject := preload("res://test/unit/helpers/guard_subject.gd")
const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const Roamer := preload("res://src/exploration/RoamingMonster.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const SECTION := "overworld_monster_sheets"


func _section() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse")
	return (parsed as Dictionary).get(SECTION, {}) if parsed is Dictionary else {}


## The owner, driven directly, including every reason it must fall back to the convention.
func test_the_geometry_owner_reports_what_each_sheet_declares() -> void:
	var section := _section()
	assert_gt(section.size(), 5, "ANTI-VACUITY: only %d roaming monster sheets registered" % section.size())
	for id in section:
		var entry: Dictionary = section[id]
		var geo: Dictionary = Loader.overworld_monster_geometry(str(id))
		assert_eq(geo["frame"], Vector2i(int(entry.get("frame_width", 0)), int(entry.get("frame_height", 0))),
			"%s's frame must come from its manifest entry" % id)
		var anims: Dictionary = entry.get("animations", {})
		for anim in anims:
			assert_eq(int((geo["rows"] as Dictionary).get(str(anim), -1)), int((anims[anim] as Dictionary).get("row", -1)),
				"%s's %s row must come from the declaration, not from a hardcoded order" % [id, anim])

	# An UNREGISTERED monster takes the convention. The section is an audit ledger for art the
	# runtime also reaches by path convention, so absence must never refuse a sheet.
	var fallback: Dictionary = Loader.overworld_monster_geometry("__no_such_monster__")
	assert_eq(fallback["frame"], Vector2i(32, 32), "an unregistered monster keeps the 32px convention")
	assert_eq(int(fallback["cols"]), 4, "...and the 4-column convention")
	assert_eq(int((fallback["rows"] as Dictionary)["walk_left"]), 1, "...and the documented row order")


## ⛔ THE FACING HALF, driven through the real node. A row order read from the wrong place is
## invisible to any geometry check — the sheet slices perfectly and the creature faces backwards.
func test_the_facing_row_comes_from_the_declaration() -> void:
	var m = Roamer.new()
	add_child_autofree(m)
	var declared: Dictionary = (Loader.overworld_monster_geometry("slime") as Dictionary)["rows"]
	assert_gt(declared.size(), 3, "PRECONDITION: slime must declare all four walk rows")
	m.set("_rows", declared)

	var cases := {
		Vector2(1, 0): "walk_right", Vector2(-1, 0): "walk_left",
		Vector2(0, 1): "walk_down", Vector2(0, -1): "walk_up",
	}
	for dir in cases:
		m.call("_update_row_from_move_dir", dir)
		assert_eq(int(m.get("_row")), int(declared[cases[dir]]),
			"moving %s must select the row declared for %s" % [dir, cases[dir]])

	# ⛔ THE DISCRIMINATING CASE: a sheet whose rows are ordered differently must follow ITS order.
	# Under the old hardcoded mapping every assertion below returns the convention's answer.
	m.set("_rows", {"walk_down": 3, "walk_left": 2, "walk_right": 1, "walk_up": 0})
	m.call("_update_row_from_move_dir", Vector2(0, 1))
	assert_eq(int(m.get("_row")), 3, "a sheet declaring walk_down on row 3 must use row 3, not the convention's 0")
	m.call("_update_row_from_move_dir", Vector2(-1, 0))
	assert_eq(int(m.get("_row")), 2, "...and walk_left on row 2, not the convention's 1")


## Every shipped sheet must be an exact grid at its DECLARED geometry — the property the loader
## now refuses on. A sheet that merely exists is what produced a mis-sliced creature.
func test_every_shipped_sheet_is_an_exact_grid_at_its_declaration() -> void:
	var section := _section()
	var bad: Array = []
	var checked := 0
	for id in section:
		var entry: Dictionary = section[id]
		var path := str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		checked += 1
		var geo: Dictionary = Loader.overworld_monster_geometry(str(id))
		var f: Vector2i = geo["frame"]
		var cols: int = int(geo["cols"])
		var rows: int = (geo["rows"] as Dictionary).size()
		var w := tex.get_width()
		var h := tex.get_height()
		if w % f.x != 0 or h % f.y != 0:
			bad.append("%s: %dx%d is not a whole number of %dx%d frames" % [id, w, h, f.x, f.y])
		elif w / f.x < cols or h / f.y < rows:
			bad.append("%s: %dx%d gives %dx%d frames, short of %d cols x %d rows" % [id, w, h, w / f.x, h / f.y, cols, rows])
	assert_gt(checked, 5, "ANTI-VACUITY: only %d sheets were loadable — the scan is measuring nothing" % checked)
	assert_eq(bad, [], "a roaming monster sheet is not an exact grid at the geometry it declares: %s" % [bad])


## ⛔ THE HALF HOUR 11 GOT WRONG FIRST TIME. The cut is derived; the RENDER must not be, or a 48px
## sheet draws 1.5x with a TOUCH_RADIUS_PX tuned to 32. Both halves are checked in source, and the
## scale line is behaviourally load-bearing rather than cosmetic.
func test_the_cut_is_derived_and_the_render_is_normalised() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/exploration/RoamingMonster.gd")
	assert_gt(code.length(), 1000, "PRECONDITION: RoamingMonster must be readable and stripped")

	assert_true(code.contains("HybridSpriteLoader.overworld_monster_geometry("),
		"the loader must take its geometry from the manifest owner")
	assert_false(code.contains("Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)"),
		"cutting at the CONSTANT is the rule this file replaced")
	assert_true(code.contains("_sprite.region_rect = Rect2(col * _frame.x"),
		"...the region must be cut at the resolved frame")
	assert_true(code.contains("_sprite.scale = Vector2(float(FRAME_W) / float(_frame.x)"),
		"...and the sprite scaled back to the convention, or TOUCH_RADIUS_PX no longer matches what is drawn")
	assert_false(code.contains("% SHEET_COLS"),
		"the animation must cycle at the DECLARED column count, not the constant")


## ⛔ ANTI-VACUITY FOR THE WHOLE FILE. Every arm above passes on a roster where the declaration and
## the convention agree — which is today's roster, and is precisely why this went unnoticed. If the
## two ever diverge on a shipped sheet, this arm says so rather than letting the agreement read as
## enforcement.
func test_the_roster_agreeing_with_the_convention_is_recorded_not_assumed() -> void:
	var section := _section()
	var divergent: Array = []
	for id in section:
		var geo: Dictionary = Loader.overworld_monster_geometry(str(id))
		if geo["frame"] != Vector2i(32, 32):
			divergent.append("%s frame %s" % [id, geo["frame"]])
		var rows: Dictionary = geo["rows"]
		if int(rows.get("walk_down", -1)) != 0 or int(rows.get("walk_left", -1)) != 1 \
				or int(rows.get("walk_right", -1)) != 2 or int(rows.get("walk_up", -1)) != 3:
			divergent.append("%s rows %s" % [id, rows])
	assert_eq(divergent, [],
		("a shipped sheet now diverges from the convention the constants encode. That is FINE and is "
		+ "what the declaration is for — but the file header says every sheet agrees today, so update "
		+ "it rather than leaving a stale claim: %s") % [divergent])


## ⛔ THE SILENT-PASS FLOOR. This guard drives its subject BY NAME; rename the member and every
## cardinal stays clean — see test/unit/helpers/guard_subject.gd for the four measurements and why
## run_tests.sh's exit 4 cannot see this rung. Names are DERIVED from this file's own text, so a
## new `.call("...")` is floored the day it is written rather than the day someone remembers.
func test_every_member_this_guard_drives_by_name_exists() -> void:
	var subject: Object = Roamer.new()
	add_child_autofree(subject)
	var calls: Dictionary = GuardSubject.audit_calls("res://test/unit/test_a_roaming_monster_reads_its_declared_sheet.gd", subject)
	var props: Dictionary = GuardSubject.audit_properties("res://test/unit/test_a_roaming_monster_reads_its_declared_sheet.gd", subject)
	assert_gt(int(calls["found"]) + int(props["found"]), 0,
		"VOID: no `.call(\"name\")` or `.get(\"_name\")` found in this file's own text — the extraction is broken, not the subject")
	assert_eq(calls["missing"], [],
		("this guard drives those methods BY NAME and the subject no longer has them, so its arms "
		+ "would ABORT INTO A SILENT PASS — EC=0, nothing failing, nothing risky: %s") % [calls["missing"]])
	assert_eq(props["missing"], [],
		"this guard reads those private properties by name and the subject no longer has them: %s" % [props["missing"]])
