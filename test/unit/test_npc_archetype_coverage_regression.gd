extends GutTest

## NPC archetype sheets are 4x4 grids of 32x32 frames; row 0=down, 1=left, 2=right, 3=up.
## If a row is fully transparent the WanderingNPC silently stays on its prior frame when
## it tries to face that direction — looks like the NPC disappears.

const NPCS_DIR := "res://assets/sprites/npcs"
const FRAME := 32
const ROWS := 4
const COLS := 4
const OPACITY_THRESHOLD := 0.05

const DIR_NAMES: Array[String] = ["down", "left", "right", "up"]


func _list_archetypes() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(NPCS_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			var sheet_path: String = "%s/%s/overworld.png" % [NPCS_DIR, name]
			if FileAccess.file_exists(sheet_path):
				out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _row_has_content(img: Image, row: int) -> bool:
	for col in COLS:
		var opaque: int = 0
		for y in FRAME:
			for x in FRAME:
				var pixel_color := img.get_pixel(col * FRAME + x, row * FRAME + y)
				if pixel_color.a > 0.0:
					opaque += 1
		var ratio := float(opaque) / float(FRAME * FRAME)
		if ratio >= OPACITY_THRESHOLD:
			return true
	return false


func test_every_archetype_sheet_has_content_in_all_4_direction_rows() -> void:
	var archetypes := _list_archetypes()
	assert_gt(archetypes.size(), 0, "Expected at least one NPC archetype directory under %s" % NPCS_DIR)
	for archetype in archetypes:
		var path: String = "%s/%s/overworld.png" % [NPCS_DIR, archetype]
		var tex := load(path) as Texture2D
		assert_not_null(tex, "Sheet must load: %s" % path)
		var img := tex.get_image()
		assert_not_null(img, "Sheet image must be readable: %s" % path)
		assert_true(img.get_width() >= FRAME * COLS,
			"%s width < %d" % [path, FRAME * COLS])
		assert_true(img.get_height() >= FRAME * ROWS,
			"%s height < %d" % [path, FRAME * ROWS])
		for row in ROWS:
			assert_true(_row_has_content(img, row),
				"%s direction row '%s' is fully transparent — NPC will disappear when facing that way" % [archetype, DIR_NAMES[row]])
