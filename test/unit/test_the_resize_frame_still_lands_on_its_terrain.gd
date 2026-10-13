extends GutTest

## The 2026-08-22 resize doubled W1's map and left every content literal in the old 100x70 frame,
## scaled by `MAP_SCALE` at the tile->pixel conversion. `OverworldScene.gd` asserted that in prose
## and cited the wrong evidence for it.
##
## ⛔ THE OLD EVIDENCE WAS FALSE. It read "proven by the H markers sitting at exactly 2x the passage
## literals." Measured by decoding `overworld_w1.png` against `map_palette.json`:
##
##     H cells in the PNG       (12,4) and (162,100)
##     2x the passage literals  (34,134) and (10,12)       -> neither matches, at 1x or 2x
##
## ✅ THE FRAME IS STILL RIGHT, and this file is what evidences it: each passage literal, scaled by
## `MAP_SCALE`, lands on terrain that matches what that passage CLAIMS TO BE. A wrong frame cannot
## produce that agreement twice — an ice alcove on ice, and a "sunken ring" in the one gap through a
## mountain ridge. **Prose cannot go stale here anymore: a resize that breaks the frame reds.**
##
## 🔑 WHY THIS READS THE PNG RATHER THAN THE RUNNING SCENE. The map is the AUTHORED source (1px per
## tile), so it answers "is this literal still pointing at the terrain it was written for". It is
## deliberately NOT a reachability claim: the Mode 7 collider clone is displaced +140.6px = 4.4
## tiles, so where a BODY fits is a different question with a different instrument
## (`test_overworld_secrets_are_reachable` uses physics for that one).

const SCENE := "res://src/exploration/OverworldScene.gd"
const MAP_PNG := "res://data/maps/overworld_w1.png"
const PALETTE := "res://data/maps/map_palette.json"
const WORLD := "medieval"

## ⛔ ONLY THE INTENT IS PINNED HERE. THE LITERAL IS READ FROM THE SOURCE, and that split is the
## whole correctness of this file. The first version hardcoded the literal too — so it compared ITS
## OWN COPY against the map and was BLIND to the source literal moving, which is the exact frame
## break it exists to catch. Measured: moving `w1_frozen_alcove` from (5,6) to (5,9) left all three
## arms GREEN. A guard holding a second copy of its subject tests the copy.
##
## 🔑 Derive what can MOVE (the literal), pin what expresses INTENT (the terrain it claims to be).
## Deriving both would be circular — whatever the literal points at would become the expectation.
const EXPECT_CHAR := {
	"w1_frozen_alcove": {"char": "i", "why": "an ice alcove, on ice"},
	"w1_sunken_ring": {"char": "s", "why": "sand, in the ridge gap"},
}


## Pull each passage's authored cell out of OverworldScene's own `passages` array. Anchored on the
## id STATEMENT rather than a delimiter — a statement cannot appear inside a type annotation or a
## nested value, which is the anchor class that cost four lanes an evening.
func _literals_from_source(code: String) -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string('\\{"id": "(w1_[a-z_]+)", "pos": Vector2\\((\\d+), (\\d+)\\)')
	for m in re.search_all(code):
		out[m.get_string(1)] = Vector2i(int(m.get_string(2)), int(m.get_string(3)))
	return out


func _grid() -> Array:
	var img := Image.load_from_file(ProjectSettings.globalize_path(MAP_PNG))
	assert_not_null(img, "CONTROL: the authored map PNG must load")
	if img == null:
		return []
	var raw := FileAccess.get_file_as_string(PALETTE)
	assert_ne(raw, "", "CONTROL: the palette must be readable")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the palette must parse")
	var world: Dictionary = ((parsed as Dictionary).get("worlds", {}) as Dictionary).get(WORLD, {})
	assert_false(world.is_empty(), "CONTROL: the %s palette must exist" % WORLD)

	var by_rgb: Dictionary = {}
	for section in ["terrain", "landmarks"]:
		for ch in (world.get(section, {}) as Dictionary).keys():
			var rgb: Array = ((world[section] as Dictionary)[ch] as Dictionary)["rgb"]
			by_rgb[Vector3i(int(rgb[0]), int(rgb[1]), int(rgb[2]))] = str(ch)

	var rows: Array = []
	var unknown := 0
	for y in range(img.get_height()):
		var line := ""
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var key := Vector3i(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0))
			if by_rgb.has(key):
				line += str(by_rgb[key])
			else:
				line += "?"
				unknown += 1
		rows.append(line)
	## ⛔ THE DECODE'S OWN CONTROL, and it is the one that makes every assert below mean something:
	## an unknown colour means the palette or the stride is wrong, and a wrong decode yields a
	## PLAUSIBLE MAP MADE OF THE WRONG TILES rather than an error — the palette file says so itself.
	assert_eq(unknown, 0, "CONTROL: %d pixels decoded to no palette char; the decode is wrong" % unknown)
	return rows


func test_the_map_decodes_and_its_landmarks_are_where_the_code_expects() -> void:
	var rows := _grid()
	assert_eq(rows.size(), 140, "CONTROL: W1's map must still be 140 rows, found %d" % rows.size())
	if rows.is_empty():
		return
	assert_eq(rows[0].length(), 200, "CONTROL: W1's map must still be 200 columns")
	## A second independent anchor: the single-pixel landmarks must each appear exactly once, which
	## a stride or orientation error would scramble.
	for ch in ["V", "P", "W"]:
		var n := 0
		for row in rows:
			n += (row as String).count(ch)
		assert_eq(n, 1, "landmark '%s' must appear exactly once in the map, found %d" % [ch, n])


## ⛔ THE ARM THE COMMENT NOW POINTS AT: each passage literal x2 lands on the terrain it claims.
func test_each_passage_literal_lands_on_its_claimed_terrain() -> void:
	var rows := _grid()
	if rows.is_empty():
		return
	var src := FileAccess.get_file_as_string(SCENE)
	assert_ne(src, "", "CONTROL: OverworldScene.gd must be readable")
	var code: String = str(GdSource.split(src)["code"])
	assert_true(code.contains("MAP_SCALE: int = 2"),
		"CONTROL: this arm assumes MAP_SCALE is 2; if it changed, the expectations below are stale")

	var lits := _literals_from_source(code)
	assert_gt(lits.size(), 0,
		"CONTROL: no passage literal could be read from the source — the extraction is broken, and every assert below would be vacuous")
	for pid in EXPECT_CHAR.keys():
		var spec: Dictionary = EXPECT_CHAR[pid]
		assert_true(lits.has(pid), "'%s' must still be placed by OverworldScene with a Vector2 pos" % pid)
		if not lits.has(pid):
			continue
		var lit: Vector2i = lits[pid]
		var cell := lit * 2
		assert_lt(cell.y, rows.size(), "%s: scaled cell %s is off the map" % [pid, str(cell)])
		var got: String = (rows[cell.y] as String).substr(cell.x, 1)
		assert_eq(got, str(spec["char"]),
			"%s: literal %s x2 = %s should be '%s' (%s), found '%s' — the resize frame no longer holds, or the map moved under it" % [
				pid, str(lit), str(cell), str(spec["char"]), str(spec["why"]), got])
	gut.p("  %d passage literals (read from source) still land on their claimed terrain at x2" % EXPECT_CHAR.size())


## The H markers are NOT evidence for the frame. Pinned so the false claim cannot come back: if a
## future author re-derives "H sits at 2x the literals", this arm says it does not.
func test_the_h_markers_are_not_the_passages() -> void:
	var rows := _grid()
	if rows.is_empty():
		return
	var hs: Array = []
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row.substr(x, 1) == "H":
				hs.append(Vector2i(x, y))
	assert_gt(hs.size(), 0, "CONTROL: the map must still carry H cells, or this arm proves nothing")
	var lits2 := _literals_from_source(str(GdSource.split(FileAccess.get_file_as_string(SCENE))["code"]))
	assert_gt(lits2.size(), 0, "CONTROL: the extraction must find literals or this arm is vacuous")
	for pid in lits2.keys():
		var scaled: Vector2i = (lits2[pid] as Vector2i) * 2
		assert_false(scaled in hs,
			"'%s' x2 = %s now coincides with an H cell. That is FINE for the game, but the comment in OverworldScene.gd says H is not the evidence for the frame — update it rather than deleting this arm." % [
				pid, str(scaled)])
	gut.p("  %d H cell(s) at %s, none of which is a passage literal x2" % [hs.size(), str(hs)])

