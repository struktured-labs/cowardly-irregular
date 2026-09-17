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
	assert_eq((str(calls["why"]) + " " + str(props["why"])).strip_edges(), "",
		("the COMMENT STRIP failed, so the derived member list is prose or empty — that is the "
		+ "INSTRUMENT, not the subject: %s %s") % [calls["why"], props["why"]])
	assert_gt(int(calls["found"]) + int(props["found"]), 0,
		"VOID: no `.call(\"name\")` or `.get(\"_name\")` found in this file's own text — the extraction is broken, not the subject")
	assert_eq(calls["missing"], [],
		("this guard drives those methods BY NAME and the subject no longer has them, so its arms "
		+ "would ABORT INTO A SILENT PASS — EC=0, nothing failing, nothing risky: %s") % [calls["missing"]])
	assert_eq(props["missing"], [],
		"this guard reads those private properties by name and the subject no longer has them: %s" % [props["missing"]])


## ⛔ TURNING MUST NOT MOVE THE CREATURE, checked through a REAL node rather than in source.
##
## An off-centre sprite mirrored IN PLACE lands at the mirrored offset, so walk_left and
## walk_right sit at different x inside the cell. `centered = true` pins the CELL to the node, so
## that displacement is literal on-screen motion at a position that never changed. Measured
## 2026-09-16 on BBOX CENTRE, the body's visible position: 21 of the 53 declaring overworld sheets
## drift >= 0.5px — monsters 8 of 10 (worst snake 4.0px, wolf 3.0px), players 9 of 14 (worst
## 1.75px), npcs 4 of 29 (worst 0.75px). On alpha CENTROID the count is 44 of 53; centroid is more
## sensitive and less visible, and quoting one count beside the other metric's numbers is the
## mixed-basis error this note exists to not repeat.
##
## 🔑 THE INVARIANT IS POST-CORRECTION AGREEMENT, not "the offset is non-zero": every row's drawn
## centre plus its offset must land on the walk_down row's centre. That is one assertion that
## covers a sheet needing a big correction and a sheet needing none.
func test_turning_does_not_move_the_creature() -> void:
	var drifted := 0
	for id in ["wolf", "snake", "slime"]:
		var m = Roamer.new()
		m.monster_id = id
		add_child_autofree(m)
		var sprite: Node = m.get_node_or_null("Sprite")
		assert_not_null(sprite, "%s must build a Sprite node" % id)
		var offsets: PackedFloat32Array = m.get("_row_offsets")
		assert_gt(offsets.size(), 3, "%s: no per-row offsets were computed" % id)

		var centres := _row_centres(sprite, m, offsets.size())
		assert_eq(centres.size(), offsets.size(),
			("%s: measuring the sheet produced %d of %d row centres. The helper returns [] when it "
			+ "ABORTS, so this reports a failed MEASUREMENT rather than rows that disagree")
			% [id, centres.size(), offsets.size()])
		if centres.size() != offsets.size():
			continue

		# ⛔ DRIVE _apply_frame AND READ THE SPRITE. Reading `_row_offsets` tests the COMPUTATION;
		# deleting the line that applies it left this arm green — cowir-controller's shape, an arm
		# that runs, asserts, and is about the wrong subject. The rendered offset is the subject.
		var anchor: int = int((m.get("_rows") as Dictionary).get("walk_down", 0))
		var spread := 0.0
		for r in centres.size():
			m.call("_apply_frame", r, 0)
			var applied: float = (sprite.get("offset") as Vector2).x
			spread = maxf(spread, absf((centres[r] + applied) - centres[anchor]))
			if absf(centres[r] - centres[anchor]) > 0.5:
				drifted += 1
		assert_almost_eq(spread, 0.0, 0.01,
			("%s: after correction the rows still draw at different x inside the cell, so the "
			+ "creature slides sideways when it turns while its position is unchanged") % id)
	assert_gt(drifted, 0,
		("ANTI-VACUITY: none of the probed sheets is off-centre at all, so the correction above was "
		+ "proved on nothing — wolf and snake drifted 3.0px and 4.0px when this was written"))


## ⛔ THE SCOPE DECISION, RATCHETED. Only RoamingMonster corrects registration; OverworldPlayer and
## OverworldNPC/WanderingNPC carry the same defect and are unfixed. That is defensible ONLY while
## the severe end lives in the sheets this file renders — which is a fact about today's art, not a
## property of the code, and it is the fact the decision rests on.
##
## 🔑 DERIVED HERE RATHER THAN WRITTEN IN A HEADER, per CLAUDE.md:21 — "three true music numbers
## and three true SFX numbers exist; say which you mean; bare counts here drifted for months". The
## SFX half of that line was repaired by deleting the count and pointing at the arm that derives
## it, because correcting a number buys until the next one. Same shape: one PNG, three honest
## drift measurements. This arm PRINTS the distribution every run and asserts only the part the
## decision depends on.
func test_the_severe_registration_drift_is_in_the_sheets_this_file_renders() -> void:
	var m := _manifest_root()
	var worst := {}
	var counted := 0
	for section in ["overworld_monster_sheets", "overworld_player_sheets", "overworld_npc_sheets"]:
		var node = m.get(section, {})
		if not (node is Dictionary):
			continue
		var top := 0.0
		for id in node:
			var e = node[id]
			if not (e is Dictionary):
				continue
			var anims = e.get("animations", {})
			if not (anims is Dictionary) or not anims.has("walk_left") or not anims.has("walk_right"):
				continue
			var path := str(e.get("path", ""))
			if path == "" or not ResourceLoader.exists(path):
				continue
			var img: Image = (load(path) as Texture2D).get_image()
			var fw: int = int(e.get("frame_width", 32))
			var fh: int = int(e.get("frame_height", 32))
			var lc := _mean_bbox_centre(img, fw, fh, int((anims["walk_left"] as Dictionary).get("row", 0)))
			var rc := _mean_bbox_centre(img, fw, fh, int((anims["walk_right"] as Dictionary).get("row", 0)))
			top = maxf(top, absf(lc - rc))
			counted += 1
		worst[section] = snappedf(top, 0.01)
	assert_gt(counted, 45, "ANTI-VACUITY: only %d sheets were measured" % counted)
	gut.p("systematic registration drift, worst per section (px): %s" % [worst])

	var mine: float = worst.get("overworld_monster_sheets", 0.0)
	assert_gt(mine, 0.5,
		("ANTI-VACUITY: the sheets this file renders no longer drift at all (%.2fpx), so the "
		+ "comparison below is between three zeros") % mine)
	for other in ["overworld_player_sheets", "overworld_npc_sheets"]:
		assert_true(float(worst[other]) <= mine,
			("%s now drifts %.2fpx against %.2fpx here, so the SEVERE end has moved out of the one "
			+ "consumer that corrects registration. Fixing only RoamingMonster was justified by this "
			+ "distribution; it no longer is: %s") % [other, worst[other], mine, worst])


## Mean over frames of the alpha bounding box's horizontal centre, for one row.
##
## MEAN, not max-over-frames: the correction is one CONSTANT per row, so this is the quantity it
## can remove. Max-over-frames also counts variation WITHIN a row, which is the walk animation
## moving and must not be flattened. cowir-adhoc measured 29 sheets that way where this measures
## 21; both are right and the definitions had simply not travelled with the numbers.

## Per-row mean bbox centre of the sheet this creature actually rendered.
##
## ⛔ A HELPER SO THE ABORT IS VISIBLE. `get_image()` on a null texture aborts its ENCLOSING
## function only. Inlined in the arm it aborted after two passing asserts and the whole run stayed
## green — measured 2026-09-17 by injecting a typed-null abort: Tests 8, Passing 8, EC 0, nothing
## red. From here an abort returns [] and the caller's size assert reds by name.
func _row_centres(sprite: Node, m: Node, rows: int) -> Array:
	var img: Image = (sprite.get("texture") as Texture2D).get_image()
	var frame: Vector2i = m.get("_frame")
	var cols: int = int(m.get("_cols"))
	var centres := []
	for r in rows:
		var total := 0.0
		var counted := 0
		for c in cols:
			var lo: int = frame.x
			var hi: int = -1
			for y in frame.y:
				for x in frame.x:
					if img.get_pixel(c * frame.x + x, r * frame.y + y).a > 0.0:
						lo = mini(lo, x)
						hi = maxi(hi, x)
			if hi >= 0:
				total += float(lo + hi) * 0.5
				counted += 1
		centres.append(total / float(counted) if counted > 0 else 0.0)
	return centres

func _mean_bbox_centre(img: Image, fw: int, fh: int, row: int) -> float:
	var total := 0.0
	var counted := 0
	for c in int(img.get_width() / fw):
		var lo: int = fw
		var hi: int = -1
		for y in fh:
			for x in fw:
				if img.get_pixel(c * fw + x, row * fh + y).a > 0.0:
					lo = mini(lo, x)
					hi = maxi(hi, x)
		if hi >= 0:
			total += float(lo + hi) * 0.5
			counted += 1
	return total / float(counted) if counted > 0 else 0.0


func _manifest_root() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}
