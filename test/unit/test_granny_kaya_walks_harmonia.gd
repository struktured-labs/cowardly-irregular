extends GutTest

## The artist's FOURTH overworld villager (Granny Kaya, 2026-10-15 drop) sat on the Drive unused. She is drawn 22x39 in
## 48px cells at native size, every row the artist's frames: her East tag is the artist's own mirror of West.

const SHEET := "res://assets/sprites/npcs/granny_kaya/overworld.png"
const LOOP_CELLS := 6


func _entry() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return (m.get("overworld_npc_sheets", {}) as Dictionary).get("granny_kaya", {})


func _image() -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func test_kaya_is_registered_as_the_artists_at_her_own_size() -> void:
	var e := _entry()
	assert_eq(str(e.get("tier", "")), "T2", "Granny Kaya is artist art")
	var img := _image()
	assert_not_null(img, "CONTROL: her sheet is on disk")
	if img == null:
		return
	assert_eq(img.get_size(), Vector2i(int(e.get("frame_width", 0)) * 4, int(e.get("frame_height", 0)) * 4),
		"the sheet is a 4x4 grid of the cells it declares")
	assert_gt(int(e.get("frame_height", 0)), 32, "CONTROL: she is taller than a 32px placeholder cell")


func test_her_pixels_are_the_artists_untouched() -> void:
	var img := _image()
	assert_not_null(img, "CONTROL: her sheet is on disk")
	if img == null:
		return
	var colours := {}
	var soft := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.a < 1.0:
				soft += 1
			elif c.a == 1.0:
				colours[c.to_rgba32()] = true
	assert_eq(soft, 0, "no soft-edged pixels")
	assert_lt(colours.size(), 40, "a pixel-art palette (%d colours)" % colours.size())
	assert_gt(colours.size(), 8, "CONTROL: the sheet has art in it")


func test_every_cell_holds_a_whole_figure_standing_on_its_floor() -> void:
	var img := _image()
	assert_not_null(img, "CONTROL: her sheet is on disk")
	if img == null:
		return
	var cell: int = img.get_width() / 4
	var bad: Array = []
	for row in 4:
		for col in 4:
			var used := img.get_region(Rect2i(col * cell, row * cell, cell, cell)).get_used_rect()
			# Her walk bobs by the artist's hand, so a frame's feet may sit a few px above the cell floor.
			if used.size.y < 30 or used.end.y < cell - 6 or used.position.y == 0:
				bad.append("row %d col %d: %s" % [row, col, str(used)])
	assert_eq(bad, [], "a frame is empty, cut at the top, or floats off the floor")


func test_kaya_walks_harmonia_on_open_ground() -> void:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var village: Node = load("res://src/maps/villages/HarmoniaVillage.gd").new()
	vp.add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame
	var found: Node = null
	var others: Array = []
	for n in village.find_children("*", "Area2D", true, false):
		if str(n.get("sprite_archetype")) == "granny_kaya":
			found = n
		elif n.get("npc_name") != null:
			others.append(n)
	assert_not_null(found, "a villager in Harmonia wears Granny Kaya' sheet")
	if found == null:
		return
	assert_eq(str(found.get("npc_name")), "Granny Kaya")
	# A patrol authored through a prop is clipped at runtime (a barrel stood on Kid Acrees' first cell): nothing here may need that.
	assert_eq(int(village.relocated_count), 0, "no patrol or spot in Harmonia had to be moved off a prop or wall")
	var a := Vector2i((found as Node2D).position / 32.0)
	var blocked: Array = []
	for x in range(a.x, a.x + LOOP_CELLS):
		if not village._is_cell_walkable(Vector2i(x, a.y)):
			blocked.append(Vector2i(x, a.y))
	assert_eq(blocked, [], "every cell of her loop is ground a villager could stand on")
	assert_gt(others.size(), 5, "CONTROL: the other villagers were found (%d)" % others.size())
	var crowded: Array = []
	for n in others:
		var c := Vector2i((n as Node2D).position / 32.0)
		if c.y == a.y and c.x >= a.x and c.x < a.x + LOOP_CELLS:
			crowded.append(str(n.get("npc_name")))
	assert_eq(crowded, [], "nobody else starts on her loop")


func test_her_right_row_is_her_left_row_mirrored() -> void:
	## Rows are down, left, right, up. The artist drew East as the exact mirror of West, so she faces the way she walks.
	var img := _image()
	assert_not_null(img, "CONTROL: her sheet is on disk")
	if img == null:
		return
	var cell: int = img.get_width() / 4
	var bad: Array = []
	for col in 4:
		var left := img.get_region(Rect2i(col * cell, 1 * cell, cell, cell))
		var right := img.get_region(Rect2i(col * cell, 2 * cell, cell, cell))
		left.flip_x()
		if left.get_data() != right.get_data():
			bad.append(col)
	assert_eq(bad, [], "walk_right frames that are not walk_left mirrored")
	var plain_left := img.get_region(Rect2i(0, 1 * cell, cell, cell))
	var plain_right := img.get_region(Rect2i(0, 2 * cell, cell, cell))
	assert_ne(plain_left.get_data(), plain_right.get_data(), "CONTROL: the two side rows are not the same picture")
