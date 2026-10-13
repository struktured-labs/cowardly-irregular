extends GutTest

## 🐛 THREE W1 CHESTS SIT NOWHERE NEAR THE PLACES THEY ARE NAMED FOR. `w1_village_potion` and
## `w1_village_gold` render in open sand and forest ~50 cells from Harmonia; `w1_cave_hipotion`
## renders in forest ~40 cells from the Whispering Cave. A player exploring beside the village finds
## nothing, and the "village potion" is lying in a desert with no landmark within six cells.
##
## 🔑 THE CAUSE IS THE 2026-08-22 RESIZE. `OverworldScene` renders every content literal at
## `pos * MAP_SCALE * TILE_SIZE`, so a literal is in the OLD 100x70 frame and doubles into the
## 200x140 map. These three were authored in PNG-CELL coordinates and never rescaled, so they render
## at twice their intended position. Measured against the authored map:
##
##     w1_village_potion  intended PNG (6,50)  grass, Harmonia's gate 2 cells east
##                        RENDERED   (12,100)  unbroken sand, NO landmark within 6
##     w1_village_gold    intended     (8,48)  a path tile beside the village
##                        RENDERED    (16,96)  forest, nothing within 6
##     w1_cave_hipotion   intended     (7,41)  grass on the cave approach
##                        RENDERED    (14,82)  forest, nothing within 6
##
## ⛔ THE INVARIANT IS A RELATIONSHIP, NOT A DISTANCE, because a threshold here would be the
## coincidental-value ratchet this repo warns about: the correct chests sit 6-22 cells from their
## landmark, so any cutoff I picked would be a number I had read off today's map. Instead: **a chest
## whose id names a landmark must be NEARER TO THAT LANDMARK THAN TO ANY OTHER.** Verified to hold
## for all six correct chests before being used to condemn the three (6 ok / 3 mismatched), so it
## separates them without a magnitude and cannot red a legitimate relocation.
##
## ⚠️ NEARNESS IS NOT THE ONLY CONSTRAINT, and the other one is not this file's. A door sits 96 px
## north of its own mark and a chest grabs presses at 128 px, so "near the landmark" and "not robbing
## the landmark's door" are two measurements: my first fix put cave_hipotion 115 px from CaveEntrance
## and `test_a_chest_in_the_doorway_answers_instead_of_the_door` caught it. Run that file too.
##
## ⚠️ SCOPE: only chests whose id contains a landmark word. `w1_central_*` names no landmark and
## `w1_secret_*` belongs to a hidden passage rather than a landmark — both out, deliberately, and
## an arm below pins that the covered set is not empty so the scope cannot silently shrink to zero.

const SCENE := "res://src/exploration/OverworldScene.gd"
const MAP_PNG := "res://data/maps/overworld_w1.png"
const PALETTE := "res://data/maps/map_palette.json"

## id word -> the map character of the landmark it names.
const NAMES := {
	"village": "V", "cave": "C", "forest": "E", "swamp": "G",
	"iron": "I", "desert": "D", "magma": "4", "frozen": "W",
}


func _grid() -> Array:
	var img := Image.load_from_file(ProjectSettings.globalize_path(MAP_PNG))
	assert_not_null(img, "CONTROL: the authored map must load")
	if img == null:
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PALETTE))
	assert_true(parsed is Dictionary, "CONTROL: the palette must parse")
	var world: Dictionary = ((parsed as Dictionary).get("worlds", {}) as Dictionary).get("medieval", {})
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
			var k := Vector3i(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0))
			if by_rgb.has(k):
				line += str(by_rgb[k])
			else:
				line += "?"
				unknown += 1
		rows.append(line)
	## A wrong palette yields a PLAUSIBLE MAP MADE OF THE WRONG TILES, not an error — the palette
	## file says so itself, which is why this control is not optional.
	assert_eq(unknown, 0, "CONTROL: %d pixels matched no palette colour; the decode is wrong" % unknown)
	return rows


func _marks(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			var ch: String = row.substr(x, 1)
			if ch in NAMES.values():
				if not out.has(ch):
					out[ch] = []
				(out[ch] as Array).append(Vector2i(x, y))
	return out


## Chest literals, read from the scene's own source so a move is visible to this guard.
func _chests() -> Array:
	var raw := FileAccess.get_file_as_string(SCENE)
	assert_ne(raw, "", "CONTROL: OverworldScene.gd must be readable")
	var code: String = str(GdSource.split(raw)["code"])
	assert_true(code.contains("func _place_treasure_chests"), "CONTROL: the strip kept the placer")
	assert_false(code.contains("##"), "CONTROL: no comment survived into the code half")
	## ⛔ READ THE CHEST PLACER'S OWN LINE, NOT THE FILE. A file-wide `contains("MAP_SCALE *
	## TILE_SIZE")` passes on this file no matter what the CHEST line does, because passages,
	## landmarks and signposts all use the same formula. Measured: dropping `MAP_SCALE *` from the
	## chest position left this guard GREEN, because it modelled the formula (`scale := 2`) instead
	## of reading it — a second copy of the thing being checked.
	var at := code.find("func _place_treasure_chests")
	assert_gt(at, -1, "CONTROL: the chest placer must exist")
	var nxt := code.find("\nfunc ", at + 10)
	var body: String = code.substr(at, (nxt if nxt > at else code.length()) - at)
	assert_eq(body.count("\nfunc "), 0, "CONTROL: the placer slice over-ran into another function")
	## ⛔ BOTH AXES, EXACTLY. A `contains("MAP_SCALE * TILE_SIZE")` is satisfied by the Y half alone —
	## measured: dropping `MAP_SCALE *` from the X only left this control GREEN, because the same
	## line's Y still carried the string. One mention is not one formula. This guard's `scale := 2`
	## is only true while BOTH axes double, so both are pinned.
	assert_eq(body.count("MAP_SCALE * TILE_SIZE"), 2,
		"the CHEST placer must double BOTH axes (found %d of the 2 expected uses); this guard's cell arithmetic assumes it, so update `scale` here if the formula changed deliberately" % body.count("MAP_SCALE * TILE_SIZE"))
	var out: Array = []
	var re := RegEx.create_from_string('"(w1_[a-z_0-9]+)", "pos": Vector2\\((\\d+), (\\d+)\\)')
	for m in re.search_all(code):
		out.append({"id": m.get_string(1), "cell": Vector2i(int(m.get_string(2)), int(m.get_string(3)))})
	return out


func test_the_corpora_are_real() -> void:
	var rows := _grid()
	if rows.is_empty():
		return
	assert_eq(rows.size(), 140, "CONTROL: W1's map must still be 140 rows")
	var marks := _marks(rows)
	assert_gt(marks.size(), 4, "CONTROL: the landmark chars must decode, found %d kinds" % marks.size())
	assert_gt(_chests().size(), 8, "CONTROL: the chest literals must be readable, found %d" % _chests().size())


## ⛔ THE ARM THAT MATTERS: every chest naming a landmark renders nearer to THAT landmark than to
## any other.
func test_every_named_chest_is_nearest_to_its_namesake() -> void:
	var rows := _grid()
	if rows.is_empty():
		return
	var marks := _marks(rows)
	var scale := 2  # MAP_SCALE; the control in _chests pins the rendering formula
	var covered := 0
	var wrong: Array = []
	for c in _chests():
		var id: String = c["id"]
		if id.begins_with("w1_secret_"):
			continue
		var word := ""
		for w in NAMES.keys():
			if id.contains(w):
				word = w
				break
		if word == "":
			continue
		var ch: String = NAMES[word]
		if not marks.has(ch):
			continue
		covered += 1
		var at: Vector2i = (c["cell"] as Vector2i) * scale
		var own := 1 << 30
		for m in (marks[ch] as Array):
			own = min(own, maxi(absi(at.x - (m as Vector2i).x), absi(at.y - (m as Vector2i).y)))
		var best := 1 << 30
		var best_ch := ""
		for k in marks.keys():
			for m in (marks[k] as Array):
				var d: int = maxi(absi(at.x - (m as Vector2i).x), absi(at.y - (m as Vector2i).y))
				if d < best:
					best = d
					best_ch = str(k)
		if best_ch != ch:
			wrong.append("%s renders at %s, %d cells from its own '%s' but only %d from '%s'" % [
				id, str(at), own, ch, best, best_ch])
	assert_gt(covered, 5,
		"CONTROL: only %d chests name a landmark; the scope has shrunk and a green would mean little" % covered)
	wrong.sort()
	assert_eq(wrong, [],
		"these chests are not near the places they are named for — a player looking where the name says finds nothing: %s" % "; ".join(wrong))
	gut.p("  %d named chests, each nearest to its own landmark" % covered)
