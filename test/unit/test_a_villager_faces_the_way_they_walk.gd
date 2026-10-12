extends GutTest

## 73 villager sheets walked LEFT FACING RIGHT and right facing left. Every overworld sheet is read as rows 0 down,
## 1 left, 2 right, 3 up, and on those the generator drew the right-facing walk on row 1. The two rows are exact
## mirrors of each other, so test_a_walk_sheet_declares_the_facing_its_pixels_show (which finds WHICH PAIR is the side
## pair) was satisfied either way round, and says so in its own header. Found by eye 2026-10-12 on the innkeeper.
## The signal that guard lacked is the FACE: in a side view the head's skin sits toward the way the figure looks, so
## its centroid against the figure's own centre leans left on a left-facing row. Checked by eye on 16 sheets: right on
## every clear lean, wrong on flat placeholder sprites whose lean is under the floor, which is why there is a floor.
## tools/fix_overworld_side_facing.py swapped the side rows of 71 sheets.

const CELL := 32
const LEFT_ROW := 1
const RIGHT_ROW := 2
## Both rows must lean this far (share of the figure's width) before the sheet has a verdict.
const CLEAR_LEAN := 0.10
const HEAD_SHARE := 0.6
## Weak-lean sheets checked by eye and found swapped: after the fix their left row leans left at all.
const REVIEWED := ["fairy", "blacksmith_abstract", "old_woman_steampunk"]
## Still facing the wrong way, each with why it was not swapped.
const LEFT_AS_IS := {
	"innkeeper_abstract": "its rows are cut in the wrong place (see test_an_overworld_walker_is_cut_at_its_own_rows)",
	"priestess": "its rows are cut in the wrong place and are not the four facings",
}
const NO_LEAN := 99.0


func _is_skin(d: PackedByteArray, o: int) -> bool:
	if d[o + 3] < 128:
		return false
	var r := d[o] / 255.0
	var g := d[o + 1] / 255.0
	var b := d[o + 2] / 255.0
	var hi := maxf(r, maxf(g, b))
	var lo := minf(r, minf(g, b))
	var sat := (hi - lo) / hi if hi > 0.0 else 0.0
	return r > g and g > b and hi > 0.6 and sat > 0.15 and sat < 0.65 and r - b > 0.12


func row_lean(img: Image, row: int) -> float:
	## Mean over the row's frames of (head skin centroid - figure centre) / figure width; + faces right. NO_LEAN if no face.
	var w := img.get_width()
	var d := img.get_data()
	var total := 0.0
	var frames := 0
	for col in w / CELL:
		var x0 := CELL
		var x1 := -1
		var y0 := CELL
		var y1 := -1
		var opaque := 0
		for y in CELL:
			for x in CELL:
				if d[((row * CELL + y) * w + col * CELL + x) * 4 + 3] >= 128:
					opaque += 1
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		if opaque < 40:
			continue
		var sum_x := 0.0
		var skin := 0
		for y in range(y0, y0 + int((y1 - y0) * HEAD_SHARE)):
			for x in CELL:
				if _is_skin(d, ((row * CELL + y) * w + col * CELL + x) * 4):
					sum_x += x
					skin += 1
		if skin < 4:
			continue
		total += (sum_x / skin - (x0 + x1) / 2.0) / maxf(1.0, float(x1 - x0))
		frames += 1
	return total / frames if frames > 0 else NO_LEAN


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _villagers() -> Dictionary:
	## id -> path for every 32px villager sheet.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out := {}
	for key in manifest["overworld_npc_sheets"]:
		var entry: Dictionary = manifest["overworld_npc_sheets"][key]
		if int(entry.get("frame_width", CELL)) == CELL and int(entry.get("frame_height", CELL)) == CELL and ResourceLoader.exists(str(entry["path"])):
			out[key] = str(entry["path"])
	return out


func test_no_villager_walks_left_facing_right() -> void:
	var sheets := _villagers()
	assert_gt(sheets.size(), 130, "CONTROL: the villager sheets were found (%d)" % sheets.size())
	var backwards: Array = []
	var facing_left := 0
	for key in sheets:
		var img := _rgba(sheets[key])
		var left := row_lean(img, LEFT_ROW)
		var right := row_lean(img, RIGHT_ROW)
		if left == NO_LEAN or right == NO_LEAN:
			continue
		if left <= -CLEAR_LEAN and right >= CLEAR_LEAN:
			facing_left += 1
		var wrong: bool = left >= CLEAR_LEAN and right <= -CLEAR_LEAN
		if LEFT_AS_IS.has(key):
			assert_true(wrong, "%s faces the right way now: drop it from LEFT_AS_IS" % key)
		elif wrong:
			backwards.append("%s (left row leans %+.2f)" % [key, left])
	assert_gt(facing_left, 90, "CONTROL: sheets with a clear verdict face the way they walk (%d)" % facing_left)
	assert_eq(backwards, [], "%d villager sheet(s) walk left facing right (tools/fix_overworld_side_facing.py): %s" % [backwards.size(), str(backwards.slice(0, 8))])


func test_the_sheets_checked_by_eye_were_turned_round() -> void:
	var sheets := _villagers()
	for key in REVIEWED:
		assert_true(sheets.has(key), "CONTROL: %s is a villager sheet" % key)
		assert_lt(row_lean(_rgba(sheets[key]), LEFT_ROW), 0.0, "%s walks left facing left" % key)


func _synthetic(face_dx: int) -> Image:
	## A body per frame on both side rows, with a face face_dx px off centre on the left row and mirrored on the right.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for pair in [[LEFT_ROW, face_dx], [RIGHT_ROW, -face_dx]]:
		for col in 4:
			img.fill_rect(Rect2i(col * CELL + 8, pair[0] * CELL + 4, 16, 26), Color8(60, 50, 90))
			img.fill_rect(Rect2i(col * CELL + 14 + pair[1], pair[0] * CELL + 8, 5, 6), Color8(236, 190, 150))
	return img


func test_the_measure_tells_left_from_right() -> void:
	assert_lt(row_lean(_synthetic(-5), LEFT_ROW), -CLEAR_LEAN, "a face toward the left faces left")
	assert_gt(row_lean(_synthetic(5), LEFT_ROW), CLEAR_LEAN, "a face toward the right faces right")
	assert_lt(absf(row_lean(_synthetic(0), LEFT_ROW)), CLEAR_LEAN, "a face in the middle gives no verdict")
	var blank := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	blank.fill(Color8(60, 50, 90))
	assert_eq(row_lean(blank, LEFT_ROW), NO_LEAN, "no face, no verdict")
