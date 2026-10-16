extends GutTest

## 69 of 214 overworld walk sheets (villagers and world costumes) held four whole rows of figures at an UNEVEN pitch,
## typically 34/30/30/30 instead of 32/32/32/32. The game cuts every sheet at y = 32, 64, 96, so walking left, right or
## up drew the previous row's feet floating over a figure whose own feet were cut off. Nothing failed: the file loads,
## the manifest matches, the frames are 32px. Found by eye 2026-10-12 while auditing white-keyed grids.
## tools/reseat_overworld_rows.py moved the rows of 27 sheets onto the grid. The other 42 cannot be shuffled into
## shape (two or three rows of figures, rows that touch, a row cut short) and need a re-roll: they are named below
## with the reason, and the list may only shrink.
## 2026-10-12, second pass: six more seated, five of them with a last row the image edge had cut 5px short.
## Those walk up without feet until re-rolled and are named in UP_ROW_CUT_SHORT.
## 2026-10-16: every villager sheet was redrawn at 48px; the 14 villagers listed here and 3 in UP_ROW_CUT_SHORT are whole.
## The measure: a cell holding a DETACHED body of >= MIN_PIECE px on its top or bottom edge holds another row's figure.

const SECTIONS := ["overworld_npc_sheets", "overworld_player_sheets", "overworld_monster_sheets"]
const SPRITES := "res://assets/sprites/"
## The cell of a sheet that declares none (job costumes, the 32px placeholders). A sheet that declares frame_height is
## cut at its own cell: the 48px villagers redrawn 2026-10-16 were skipped by a 32-only filter, not checked.
const CELL := 32
const MIN_PIECE := 10
## Sheets still cut, keyed by path under assets/sprites without .png, each with why a re-seat cannot fix it.
const NEEDS_A_REROLL := {
	"jobs/bard/overworld_industrial": "3 rows of figures, not 4",
	"jobs/fighter/overworld_abstract": "a detached piece still sits on a cell edge after re-seating",
	"jobs/fighter/overworld_digital": "seated on the grid, but its own legs are in loose pieces on some frames (key damage)",
	"jobs/fighter/overworld_steampunk": "seated on the grid, but its own legs are in loose pieces on some frames (key damage)",
	"jobs/guardian/overworld_abstract": "3 rows of figures, not 4",
	"jobs/guardian/overworld_digital": "2 rows of figures, not 4",
	"jobs/guardian/overworld_industrial": "3 rows of figures, not 4",
	"jobs/guardian/overworld_steampunk": "3 rows of figures, not 4",
	"jobs/guardian/overworld_suburban": "3 rows of figures, not 4",
	"jobs/mage/overworld_abstract": "seated on the grid, but its own legs are in loose pieces on some frames (key damage)",
	"jobs/mage/overworld_steampunk": "a detached piece still sits on a cell edge after re-seating",
	"jobs/ninja/overworld_abstract": "3 rows of figures, not 4",
	"jobs/ninja/overworld_digital": "3 rows of figures, not 4",
	"jobs/ninja/overworld_industrial": "3 rows of figures, not 4",
	"jobs/ninja/overworld_steampunk": "3 rows of figures, not 4",
	"jobs/ninja/overworld_suburban": "3 rows of figures, not 4",
	"jobs/speculator/overworld_abstract": "2 rows of figures, not 4",
	"jobs/speculator/overworld_digital": "2 rows of figures, not 4",
	"jobs/speculator/overworld_industrial": "3 rows of figures, not 4",
	"jobs/speculator/overworld_steampunk": "2 rows of figures, not 4",
	"jobs/summoner/overworld_abstract": "rows of unequal height: one was cut short",
	"jobs/summoner/overworld_digital": "6 rows of figures, not 4",
	"jobs/summoner/overworld_industrial": "3 rows of figures, not 4",
	"jobs/summoner/overworld_steampunk": "2 rows of figures, not 4",
	"jobs/summoner/overworld_suburban": "2 rows of figures, not 4",
}

## Seated sheets whose up-facing row lost its feet to the image edge: that row stands shorter than the down row.
const UP_ROW_CUT_SHORT := [
	"jobs/fighter/overworld_digital", "jobs/fighter/overworld_steampunk",
]
## An up row at most this share of the down row's height has lost its feet.
const SHORT_SHARE := 0.82


func _alpha(img: Image) -> PackedByteArray:
	## 1 per opaque pixel, row-major.
	var d := img.get_data()
	var out := PackedByteArray()
	out.resize(img.get_width() * img.get_height())
	for i in out.size():
		out[i] = 1 if d[i * 4 + 3] >= 128 else 0
	return out


func cut_cells(img: Image, cell: int = CELL) -> int:
	## Cells holding a detached piece of another row's figure on their top or bottom edge.
	var w := img.get_width()
	var a := _alpha(img)
	var cut := 0
	for r in img.get_height() / cell:
		for c in w / cell:
			var seen := PackedByteArray()
			seen.resize(cell * cell)
			var sizes: Array[int] = []
			var on_edge: Array[bool] = []
			for start in cell * cell:
				if seen[start] or not a[(r * cell + start / cell) * w + c * cell + start % cell]:
					continue
				var stack: Array[int] = [start]
				seen[start] = 1
				var n := 0
				var edge := false
				while not stack.is_empty():
					var p: int = stack.pop_back()
					n += 1
					var x := p % cell
					var y := p / cell
					edge = edge or y == 0 or y == cell - 1
					for ny in range(maxi(0, y - 1), mini(cell, y + 2)):
						for nx in range(maxi(0, x - 1), mini(cell, x + 2)):
							var q := ny * cell + nx
							if not seen[q] and a[(r * cell + ny) * w + c * cell + nx]:
								seen[q] = 1
								stack.append(q)
				sizes.append(n)
				on_edge.append(edge)
			var main := sizes.find(sizes.max()) if not sizes.is_empty() else -1
			for k in sizes.size():
				if k != main and sizes[k] >= MIN_PIECE and on_edge[k]:
					cut += 1
					break
	return cut


func _sheets() -> Dictionary:
	## path -> cell for every square-celled overworld sheet the game can load: the manifest's, plus each job's world costumes.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out := {}
	for section in SECTIONS:
		for key in manifest[section]:
			var entry: Dictionary = manifest[section][key]
			var fw := int(entry.get("frame_width", CELL))
			if fw == int(entry.get("frame_height", CELL)):
				out[str(entry["path"])] = fw
	for job in DirAccess.get_directories_at(SPRITES + "jobs"):
		for f in DirAccess.get_files_at(SPRITES + "jobs/" + job):
			if f.begins_with("overworld_") and f.ends_with(".png"):
				out[SPRITES + "jobs/" + job + "/" + f] = CELL
	return out


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_every_overworld_walker_is_cut_at_its_own_rows() -> void:
	var sheets := _sheets()
	assert_gt(sheets.size(), 200, "CONTROL: the overworld sheets were found (%d)" % sheets.size())
	var cut: Array = []
	var mended: Array = []
	var judged := 0
	for path in sheets:
		if not ResourceLoader.exists(path):
			continue
		judged += 1
		var key: String = path.trim_prefix(SPRITES).trim_suffix(".png")
		var n := cut_cells(_rgba(path), sheets[path])
		if n > 0 and not NEEDS_A_REROLL.has(key):
			cut.append("%s: %d cells hold a piece of another row" % [key, n])
		elif n == 0 and NEEDS_A_REROLL.has(key):
			mended.append(key)
	assert_gt(judged, 200, "CONTROL: the sheets were judged (%d)" % judged)
	assert_eq(cut, [], "%d overworld sheet(s) whose rows are off their cell grid (tools/reseat_overworld_rows.py): %s" % [cut.size(), str(cut.slice(0, 8))])
	assert_eq(mended, [], "these are whole now: drop them from NEEDS_A_REROLL")


func test_the_list_names_real_sheets() -> void:
	for key in NEEDS_A_REROLL:
		assert_true(ResourceLoader.exists(SPRITES + key + ".png"), "%s is listed but is not a sheet" % key)


func _row_height(img: Image, row: int) -> int:
	## Rows of the cell band that hold any opaque pixel. Every sheet is four rows, so the cell is a quarter of its height.
	var cell := img.get_height() / 4
	var a := _alpha(img)
	var w := img.get_width()
	var n := 0
	for y in range(row * cell, (row + 1) * cell):
		for x in w:
			if a[y * w + x]:
				n += 1
				break
	return n


func test_a_footless_up_row_is_named_until_it_is_redrawn() -> void:
	for key in UP_ROW_CUT_SHORT:
		var path: String = SPRITES + key + ".png"
		assert_true(ResourceLoader.exists(path), "CONTROL: %s is a sheet" % key)
		var img := _rgba(path)
		assert_lte(float(_row_height(img, 3)), SHORT_SHARE * _row_height(img, 0),
			"%s walks up with its feet now: drop it from UP_ROW_CUT_SHORT" % key)


func _synthetic(tops: Array) -> Image:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for top in tops:
		for c in 4:
			img.fill_rect(Rect2i(c * CELL + 10, top, 12, 28), Color.WHITE)
	return img


func test_the_measure_tells_a_row_on_the_grid_from_one_off_it() -> void:
	assert_eq(cut_cells(_synthetic([4, 36, 68, 100])), 0, "four rows inside their cells are whole")
	assert_eq(cut_cells(_synthetic([4, 38, 72, 100])), 4, "a row hanging 2px past its cell cuts the four cells below it")
