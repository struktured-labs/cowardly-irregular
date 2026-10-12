extends GutTest

## 69 of 214 overworld walk sheets (villagers and world costumes) held four whole rows of figures at an UNEVEN pitch,
## typically 34/30/30/30 instead of 32/32/32/32. The game cuts every sheet at y = 32, 64, 96, so walking left, right or
## up drew the previous row's feet floating over a figure whose own feet were cut off. Nothing failed: the file loads,
## the manifest matches, the frames are 32px. Found by eye 2026-10-12 while auditing white-keyed grids.
## tools/reseat_overworld_rows.py moved the rows of 27 sheets onto the grid. The other 42 cannot be shuffled into
## shape (two or three rows of figures, rows that touch, a row cut short) and need a re-roll: they are named below
## with the reason, and the list may only shrink.
## The measure: a cell holding a DETACHED body of >= MIN_PIECE px on its top or bottom edge holds another row's figure.

const SECTIONS := ["overworld_npc_sheets", "overworld_player_sheets", "overworld_monster_sheets"]
const SPRITES := "res://assets/sprites/"
const CELL := 32
const MIN_PIECE := 10
## Sheets still cut, keyed by path under assets/sprites without .png, each with why a re-seat cannot fix it.
const NEEDS_A_REROLL := {
	"jobs/bard/overworld_industrial": "3 rows of figures, not 4",
	"jobs/fighter/overworld_abstract": "a detached piece still sits on a cell edge after re-seating",
	"jobs/fighter/overworld_digital": "rows of unequal height: one was cut short",
	"jobs/fighter/overworld_steampunk": "rows of unequal height: one was cut short",
	"jobs/guardian/overworld_abstract": "3 rows of figures, not 4",
	"jobs/guardian/overworld_digital": "2 rows of figures, not 4",
	"jobs/guardian/overworld_industrial": "3 rows of figures, not 4",
	"jobs/guardian/overworld_steampunk": "3 rows of figures, not 4",
	"jobs/guardian/overworld_suburban": "3 rows of figures, not 4",
	"jobs/mage/overworld_abstract": "still cut after re-seating, (1, 3)]): the columns are off too",
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
	"npcs/chancellor_mordaine/overworld": "5 rows of figures, not 4",
	"npcs/child_digital/overworld": "rows of unequal height: one was cut short",
	"npcs/ghost_suburban/overworld": "still cut after re-seating, (1, 3)]): the columns are off too",
	"npcs/guard_suburban/overworld": "rows of unequal height: one was cut short",
	"npcs/innkeeper_abstract/overworld": "still cut after re-seating, (1, 2)]): the columns are off too",
	"npcs/merchant_industrial/overworld": "a detached speck sits between its rows",
	"npcs/monk/overworld": "rows of unequal height: one was cut short",
	"npcs/noblewoman/overworld": "rows of unequal height: one was cut short",
	"npcs/noblewoman_abstract/overworld": "its rows touch: no gap to cut at",
	"npcs/old_man_suburban/overworld": "rows of unequal height: one was cut short",
	"npcs/old_woman_suburban/overworld": "its rows touch: no gap to cut at",
	"npcs/priestess/overworld": "its rows are not the four facings (three side views, no back): re-seated, the facing guard can see that",
	"npcs/phil/overworld": "2 rows of figures, not 4",
	"npcs/soldier_digital/overworld": "its rows touch: no gap to cut at",
	"npcs/soldier_steampunk/overworld": "rows of unequal height: one was cut short",
	"npcs/traveler_steampunk/overworld": "rows of unequal height: one was cut short",
	"npcs/young_woman/overworld": "rows of unequal height: one was cut short",
}


func _alpha(img: Image) -> PackedByteArray:
	## 1 per opaque pixel, row-major.
	var d := img.get_data()
	var out := PackedByteArray()
	out.resize(img.get_width() * img.get_height())
	for i in out.size():
		out[i] = 1 if d[i * 4 + 3] >= 128 else 0
	return out


func cut_cells(img: Image) -> int:
	## Cells holding a detached piece of another row's figure on their top or bottom edge.
	var w := img.get_width()
	var a := _alpha(img)
	var cut := 0
	for r in img.get_height() / CELL:
		for c in w / CELL:
			var seen := PackedByteArray()
			seen.resize(CELL * CELL)
			var sizes: Array[int] = []
			var on_edge: Array[bool] = []
			for start in CELL * CELL:
				if seen[start] or not a[(r * CELL + start / CELL) * w + c * CELL + start % CELL]:
					continue
				var stack: Array[int] = [start]
				seen[start] = 1
				var n := 0
				var edge := false
				while not stack.is_empty():
					var p: int = stack.pop_back()
					n += 1
					var x := p % CELL
					var y := p / CELL
					edge = edge or y == 0 or y == CELL - 1
					for ny in range(maxi(0, y - 1), mini(CELL, y + 2)):
						for nx in range(maxi(0, x - 1), mini(CELL, x + 2)):
							var q := ny * CELL + nx
							if not seen[q] and a[(r * CELL + ny) * w + c * CELL + nx]:
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


func _sheets() -> Array:
	## Every 32px overworld sheet the game can load: the manifest's, plus each job's world costumes.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out: Array = []
	for section in SECTIONS:
		for key in manifest[section]:
			var entry: Dictionary = manifest[section][key]
			if int(entry.get("frame_width", CELL)) == CELL and int(entry.get("frame_height", CELL)) == CELL:
				out.append(str(entry["path"]))
	for job in DirAccess.get_directories_at(SPRITES + "jobs"):
		for f in DirAccess.get_files_at(SPRITES + "jobs/" + job):
			if f.begins_with("overworld_") and f.ends_with(".png"):
				out.append(SPRITES + "jobs/" + job + "/" + f)
	out.sort()
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
		var n := cut_cells(_rgba(path))
		if n > 0 and not NEEDS_A_REROLL.has(key):
			cut.append("%s: %d cells hold a piece of another row" % [key, n])
		elif n == 0 and NEEDS_A_REROLL.has(key):
			mended.append(key)
	assert_gt(judged, 200, "CONTROL: the sheets were judged (%d)" % judged)
	assert_eq(cut, [], "%d overworld sheet(s) whose rows are off the 32px grid (tools/reseat_overworld_rows.py): %s" % [cut.size(), str(cut.slice(0, 8))])
	assert_eq(mended, [], "these are whole now: drop them from NEEDS_A_REROLL")


func test_the_list_names_real_sheets() -> void:
	for key in NEEDS_A_REROLL:
		assert_true(ResourceLoader.exists(SPRITES + key + ".png"), "%s is listed but is not a sheet" % key)


func _synthetic(tops: Array) -> Image:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for top in tops:
		for c in 4:
			img.fill_rect(Rect2i(c * CELL + 10, top, 12, 28), Color.WHITE)
	return img


func test_the_measure_tells_a_row_on_the_grid_from_one_off_it() -> void:
	assert_eq(cut_cells(_synthetic([4, 36, 68, 100])), 0, "four rows inside their cells are whole")
	assert_eq(cut_cells(_synthetic([4, 38, 72, 100])), 4, "a row hanging 2px past its cell cuts the four cells below it")
