extends GutTest

## One fact — the frame geometry of an overworld sheet — has FOUR consumers and THREE sources of
## truth. Measured on `0c9c6041`:
##
##   CutsceneActor      frame_size_of(tex)        MEASURES THE IMAGE   (cowir-cutscenes, 62dc0776)
##   WanderingNPC       ARCHETYPE_FRAME_W = 32    a constant, 4 sites
##   OverworldNPC       _ARCHETYPE_FRAME_W = 32   a constant, 2 sites
##   the manifest       frame_width x145          THE DECLARATION
##
## So a sheet authored at another size would slice correctly in a cutscene and be quartered on the
## map, by the same art, in the same run.
##
## 🔑 CLAUDE.md ALREADY RULES ON THIS SHAPE and it is neither "measure" nor "declare". Under
## *Two data sources feeding one surface*, case (a) REDUNDANT: "assert AGREEMENT — never model
## precedence, if both agree the question is moot." The measurement is what makes it case (a):
## declared 145, on disk 145, all 128x128, missing either way 0. NOBODY HAS TO WIN.
##
## ⚠️ AND THE AGREEMENT ARM CATCHES BOTH LANES' FEARS, WHICH NEITHER CONSUMER FIX WOULD:
##   a re-export that changes geometry and does not touch the manifest   -> reds (my worry)
##   a manifest edit that no image backs                                  -> reds (theirs)
## One test, no consumer changes, no precedence for the next reader to remember. cowir-cutscenes
## proposed it against my own divergence report; it is better than the answer I was going to ship.
##
## 📌 The CONSUMERS are deliberately NOT unified. `AdvanceAura.figure_rect_of(tex)` and
## `HybridSpriteLoader.figure_rect(path)` are already two owners split by INPUT, with different
## fallbacks on purpose. CutsceneActor holds a Texture and no manifest id; WanderingNPC holds an
## id. Measuring where you hold pixels and declaring where you hold ids is fine ONCE THE TWO ARE
## PINNED EQUAL — which is this file's whole job.
const MANIFEST := "res://data/sprite_manifest.json"
const SECTIONS: Array[String] = [
	"overworld_npc_sheets", "overworld_player_sheets", "overworld_monster_sheets",
]


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


## The comparison, as a pure function, so the control arm can drive it with geometry no shipped
## sheet has. An agreement check that only ever sees agreeing inputs cannot be shown to work.
static func _disagreement(id: String, img_w: int, img_h: int, fw: int, fh: int, rows: int, cols: int) -> String:
	if fw <= 0 or fh <= 0:
		return "%s: declares no frame size" % id
	if img_w % fw != 0 or img_h % fh != 0:
		return "%s: image %dx%d is not a whole number of %dx%d frames" % [id, img_w, img_h, fw, fh]
	# ⛔ EXACT, not ">= enough". Divisibility alone is satisfied by the very case this exists for:
	# a 4x4 sheet re-exported at 48px becomes 192x192, which divides by the stale 32 into 6x6 and
	# reads as agreement. My own control arm caught that — the first version used >=.
	if rows > 0 and img_h / fh != rows:
		return "%s: declares %d rows, the image has %d at %dpx" % [id, rows, img_h / fh, fh]
	if cols > 0 and img_w / fw != cols:
		return "%s: declares %d frames per row, the image has %d columns at %dpx" % [id, cols, img_w / fw, fw]
	return ""


func _declared_rows_and_cols(entry: Dictionary) -> Vector2i:
	var anims = entry.get("animations", {})
	if not (anims is Dictionary):
		return Vector2i(0, 0)
	var rows := 0
	var cols := 0
	for name in anims:
		var a = anims[name]
		if not (a is Dictionary):
			continue
		if a.has("row"):
			rows = maxi(rows, int(a["row"]) + 1)
		cols = maxi(cols, int(a.get("frames", 0)))
	return Vector2i(rows, cols)


## ⛔ THE INSTRUMENT FIRST, BOTH DIRECTIONS. Every arm below reports an empty list on a corpus it
## could not read, so the comparison is proven able to FIND a disagreement before it is trusted to
## report none — cowir-controller's rule: an empty result means "none" and "broken" identically.
func test_the_comparison_can_detect_a_disagreement_at_all() -> void:
	assert_eq(_disagreement("ok", 128, 128, 32, 32, 4, 4), "",
		"CONTROL: agreeing geometry must report nothing, or every arm below reds on everything")

	assert_ne(_disagreement("reexported", 192, 192, 32, 32, 4, 4), "",
		"a sheet re-exported to 48px frames while the manifest still says 32 must be caught")
	assert_ne(_disagreement("stale_decl", 128, 128, 48, 48, 4, 4), "",
		"a manifest edited to 48px that no image backs must be caught")
	assert_ne(_disagreement("too_many_rows", 128, 128, 32, 32, 8, 4), "",
		"a declaration promising 8 rows on a 4-row image must be caught")
	assert_ne(_disagreement("spare_rows", 128, 128, 32, 32, 2, 4), "",
		"...and so must the reverse: a 4-row image whose declaration only describes 2 is not agreement")
	assert_ne(_disagreement("too_many_frames", 128, 128, 32, 32, 4, 8), "",
		"a declaration promising 8 frames per row on a 4-column image must be caught")
	assert_ne(_disagreement("no_frame", 128, 128, 0, 0, 4, 4), "",
		"an entry declaring no frame size at all must be caught, not treated as agreement")


## The ratchet itself. 169 sheets across three sections agree today; this keeps that true rather
## than letting the agreement be rediscovered by whoever re-exports one.
func test_every_declared_overworld_sheet_matches_its_image() -> void:
	var m := _manifest()
	var disagreements: Array = []
	var checked := 0
	var per_section := {}
	for section in SECTIONS:
		var node = m.get(section, {})
		assert_true(node is Dictionary, "%s must be a section of entries" % section)
		var n := 0
		for id in node:
			var entry = node[id]
			if not (entry is Dictionary):
				continue
			var path := str(entry.get("path", ""))
			if path == "":
				disagreements.append("%s/%s: no path" % [section, id])
				continue
			if not ResourceLoader.exists(path):
				disagreements.append("%s/%s: declared path does not load: %s" % [section, id, path])
				continue
			var tex := load(path) as Texture2D
			if tex == null:
				disagreements.append("%s/%s: path loads as nothing" % [section, id])
				continue
			n += 1
			checked += 1
			var rc := _declared_rows_and_cols(entry)
			var why := _disagreement("%s/%s" % [section, id], tex.get_width(), tex.get_height(),
				int(entry.get("frame_width", 0)), int(entry.get("frame_height", 0)), rc.x, rc.y)
			if why != "":
				disagreements.append(why)
		per_section[section] = n
		assert_gt(n, 5, "ANTI-VACUITY: %s contributed only %d readable sheets" % [section, n])
	assert_gt(checked, 100,
		"ANTI-VACUITY: only %d sheets were read across %d sections (%s) — the scan is measuring almost nothing"
		% [checked, SECTIONS.size(), per_section])
	disagreements.sort()
	assert_eq(disagreements, [],
		("a sheet's IMAGE and its DECLARATION disagree. Both are authored, neither outranks the other, "
		+ "and four consumers read one or the other — so they must agree or the same art renders "
		+ "differently in a cutscene and on the map: %s") % [disagreements])


## ⛔ AND THE CLAIM THIS FILE RESTS ON: that the declaration COVERS the art, so no consumer needs
## to measure for reach. If a sheet ever ships undeclared, measuring becomes the only way to know
## its geometry and the agreement ratchet stops being sufficient on its own.
func test_the_declaration_covers_every_shipped_overworld_npc_sheet() -> void:
	var node: Dictionary = _manifest().get("overworld_npc_sheets", {})
	var declared := {}
	for id in node:
		var e = node[id]
		if e is Dictionary:
			declared[str(e.get("path", ""))] = true
	assert_gt(declared.size(), 100, "ANTI-VACUITY: only %d npc sheets declared" % declared.size())

	var undeclared: Array = []
	var found := 0
	var stack: Array[String] = ["res://assets/sprites/npcs"]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full: String = "%s/%s" % [cur, n]
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(full)
			elif n == "overworld.png":
				found += 1
				if not declared.has(full):
					undeclared.append(full)
			n = d.get_next()
		d.list_dir_end()
	assert_gt(found, 100, "ANTI-VACUITY: only %d overworld.png files walked" % found)
	undeclared.sort()
	assert_eq(undeclared, [],
		("an overworld NPC sheet ships with no manifest entry, so its geometry is knowable only by "
		+ "MEASURING it — which is the case that would make a declaration-only consumer wrong: %s") % [undeclared])
