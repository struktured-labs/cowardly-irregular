extends GutTest

## The cleric walked the overworld with a slot in her hood that showed the grass through it. The August overworld
## sheets were keyed on near-white (R,G,B >= 240), so the brightest highlight of a pale robe went clear with the
## backdrop: 76 px on her sheet, 24 more across four speculator and summoner world costumes (a fifth was re-rolled whole 2026-10-31). Nothing failed, because
## a clear pixel inside a figure is a legal pixel. Found 2026-10-12 auditing the white-keyed grids.
## A hole is that damage, and not a real gap (staff to body, between the legs), when its rim is mostly pale.
## tools/fill_pale_holes.py fills each with the commonest pale colour on its own rim.

const SECTIONS := ["overworld_npc_sheets", "overworld_player_sheets", "overworld_monster_sheets"]
const SPRITES := "res://assets/sprites/"
## The cell of a sheet that declares none; a sheet that declares frame_height is read at its own cell (the 48px
## villagers of 2026-10-16 were skipped by a 32-only filter, not checked).
const CELL := 32
## A rim pixel is pale when its darkest channel is at least this; a hole is damage when this share of its rim is.
const PALE_MIN := 200
const PALE_SHARE := 0.6
## Sheets left holed, each with why. Empty since 2026-10-31: the speculator's industrial costume was re-rolled whole at 48px.
const LEFT_HOLED := {}


func pale_hole_pixels(img: Image, cell: int = CELL) -> int:
	## Clear pixels in enclosed regions of a cell whose opaque rim is mostly pale.
	var w := img.get_width()
	var d := img.get_data()
	var total := 0
	for r in img.get_height() / cell:
		for c in w / cell:
			var seen := PackedByteArray()
			seen.resize(cell * cell)
			for start in cell * cell:
				if seen[start] or d[((r * cell + start / cell) * w + c * cell + start % cell) * 4 + 3] >= 128:
					continue
				seen[start] = 1
				var stack: Array[int] = [start]
				var size := 0
				var enclosed := true
				var rim := {}
				while not stack.is_empty():
					var p: int = stack.pop_back()
					size += 1
					for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
						var nx: int = p % cell + step.x
						var ny: int = p / cell + step.y
						if nx < 0 or ny < 0 or nx >= cell or ny >= cell:
							enclosed = false
							continue
						var o := ((r * cell + ny) * w + c * cell + nx) * 4
						if d[o + 3] >= 128:
							rim[ny * cell + nx] = mini(d[o], mini(d[o + 1], d[o + 2])) >= PALE_MIN
						elif not seen[ny * cell + nx]:
							seen[ny * cell + nx] = 1
							stack.append(ny * cell + nx)
				if enclosed and not rim.is_empty() and float(rim.values().count(true)) >= PALE_SHARE * rim.size():
					total += size
	return total


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


func test_no_overworld_walker_has_a_slot_in_its_pale_cloth() -> void:
	var sheets := _sheets()
	assert_gt(sheets.size(), 200, "CONTROL: the overworld sheets were found (%d)" % sheets.size())
	var bad: Array = []
	var judged := 0
	for path in sheets:
		if not ResourceLoader.exists(path):
			continue
		judged += 1
		var n := pale_hole_pixels(_rgba(path), sheets[path])
		var key: String = path.trim_prefix(SPRITES)
		if LEFT_HOLED.has(key):
			assert_gt(n, 0, "%s is whole now: drop it from LEFT_HOLED" % key)
		elif n > 0:
			bad.append("%s: %d see-through px in pale cloth" % [path.trim_prefix(SPRITES), n])
	assert_gt(judged, 200, "CONTROL: the sheets were judged (%d)" % judged)
	assert_eq(bad, [], "overworld sheets with key holes in pale cloth (tools/fill_pale_holes.py): %s" % str(bad))


func test_the_measure_tells_a_slot_in_cloth_from_a_real_gap() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(8, 4, 16, 24), Color8(232, 230, 224))
	assert_eq(pale_hole_pixels(img), 0, "whole cloth has no slot")
	img.fill_rect(Rect2i(12, 8, 4, 1), Color(0, 0, 0, 0))
	assert_eq(pale_hole_pixels(img), 4, "a slot inside pale cloth is the key's damage")
	var dark := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	dark.fill_rect(Rect2i(8, 4, 16, 24), Color8(70, 40, 30))
	dark.fill_rect(Rect2i(14, 10, 1, 4), Color(0, 0, 0, 0))
	assert_eq(pale_hole_pixels(dark), 0, "a dark-rimmed opening is a real gap")
	var notch := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	notch.fill_rect(Rect2i(8, 0, 16, 20), Color8(240, 240, 240))
	notch.fill_rect(Rect2i(12, 0, 1, 1), Color(0, 0, 0, 0))
	assert_eq(pale_hole_pixels(notch), 0, "a notch open to the cell edge is not enclosed")
