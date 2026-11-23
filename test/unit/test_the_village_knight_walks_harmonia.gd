extends GutTest

## The artist's SIXTH overworld villager (the Village Knight, 2026-11-03 drop) sat on the Drive unused. He is drawn 40x55 in
## 64px cells at native size, every row the artist's frames. His East is drawn on its own, not a mirror of West.

const SHEET := "res://assets/sprites/npcs/village_knight/overworld.png"
const LOOP_CELLS := 6


func _entry() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return (m.get("overworld_npc_sheets", {}) as Dictionary).get("village_knight", {})


func _image() -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func test_the_knight_is_registered_as_the_artists_at_his_own_size() -> void:
	var e := _entry()
	assert_eq(str(e.get("tier", "")), "T2", "the Village Knight is artist art")
	var img := _image()
	assert_not_null(img, "CONTROL: his sheet is on disk")
	if img == null:
		return
	assert_eq(img.get_size(), Vector2i(int(e.get("frame_width", 0)) * 4, int(e.get("frame_height", 0)) * 4),
		"the sheet is a 4x4 grid of the cells it declares")
	assert_gt(int(e.get("frame_height", 0)), 32, "CONTROL: he is taller than a 32px placeholder cell")


func test_his_pixels_are_the_artists_untouched() -> void:
	var img := _image()
	assert_not_null(img, "CONTROL: his sheet is on disk")
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
	assert_not_null(img, "CONTROL: his sheet is on disk")
	if img == null:
		return
	var cell: int = img.get_width() / 4
	var bad: Array = []
	for row in 4:
		for col in 4:
			var used := img.get_region(Rect2i(col * cell, row * cell, cell, cell)).get_used_rect()
			# His walk bobs by the artist's hand, so a frame's feet may sit a few px above the cell floor.
			if used.size.y < 30 or used.end.y < cell - 6 or used.position.y == 0:
				bad.append("row %d col %d: %s" % [row, col, str(used)])
	assert_eq(bad, [], "a frame is empty, cut at the top, or floats off the floor")


func test_the_knight_walks_the_south_wall_on_open_ground() -> void:
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
		if str(n.get("sprite_archetype")) == "village_knight":
			found = n
		elif n.get("npc_name") != null:
			others.append(n)
	assert_not_null(found, "a villager in Harmonia wears the Village Knight's sheet")
	if found == null:
		return
	assert_eq(str(found.get("npc_name")), "Village Knight")
	# A patrol authored through a prop is clipped at runtime (a barrel stood on Kid Acrees' first cell): nothing here may need that.
	assert_eq(int(village.relocated_count), 0, "no patrol or spot in Harmonia had to be moved off a prop or wall")
	var a := Vector2i((found as Node2D).position / 32.0)
	var blocked: Array = []
	for x in range(a.x, a.x + LOOP_CELLS):
		if not village._is_cell_walkable(Vector2i(x, a.y)):
			blocked.append(Vector2i(x, a.y))
	assert_eq(blocked, [], "every cell of his loop is ground a villager could stand on")
	assert_gt(others.size(), 5, "CONTROL: the other villagers were found (%d)" % others.size())
	var crowded: Array = []
	for n in others:
		var c := Vector2i((n as Node2D).position / 32.0)
		if c.y == a.y and c.x >= a.x and c.x < a.x + LOOP_CELLS:
			crowded.append(str(n.get("npc_name")))
	assert_eq(crowded, [], "nobody else starts on his loop")


func test_his_right_row_is_drawn_not_mirrored() -> void:
	## Rows are down, left, right, up. The artist drew East on its own (the halberd and plume change sides), so a re-export
	## with --mirror-right-from-left would throw his East away; this reds if that happens.
	var img := _image()
	assert_not_null(img, "CONTROL: his sheet is on disk")
	if img == null:
		return
	var cell: int = img.get_width() / 4
	var mirrored := 0
	for col in 4:
		var left := img.get_region(Rect2i(col * cell, 1 * cell, cell, cell))
		var right := img.get_region(Rect2i(col * cell, 2 * cell, cell, cell))
		assert_gt(right.get_used_rect().size.y, 30, "CONTROL: walk_right col %d holds a figure" % col)
		left.flip_x()
		if left.get_data() == right.get_data():
			mirrored += 1
	assert_eq(mirrored, 0, "walk_right frames that are just walk_left mirrored: the artist's own East was replaced")


## Feet = centre of the bottom 6 rows' alpha extent: what the eye reads as "where he stands".
func _feet_centre(img: Image) -> float:
	var lo := img.get_width()
	var hi := -1
	var bottom := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				bottom = y
	for y in range(maxi(0, bottom - 5), bottom + 1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				lo = mini(lo, x)
				hi = maxi(hi, x)
	return (lo + hi) * 0.5


## His feet sat 5.75px apart facing left vs right (mean of 4 frames: 28.50 / 34.25), so pacing the wall he hopped at every turn; per frame the corrected gap is 0.5/4.5/0.5/1.5.
func test_the_knight_does_not_hop_when_he_turns() -> void:
	var w = WanderingNPC.new()
	w.sprite_archetype = "village_knight"
	add_child_autofree(w)
	await get_tree().process_frame
	var spr := w.find_child("Sprite", true, false) as Sprite2D
	assert_not_null(spr, "CONTROL: the wanderer has a sprite")
	var raw := {}
	var placed := {}
	for d in [1, 2]:
		raw[d] = 0.0
		placed[d] = 0.0
		for frame in 4:
			w._current_dir = d
			w._anim_frame = frame
			w._update_archetype_frame()
			var f := _feet_centre(spr.texture.get_image())
			raw[d] += f / 4.0
			placed[d] += (f + spr.offset.x) / 4.0
	assert_gt(absf(raw[1] - raw[2]), 4.0, "PRECONDITION: uncorrected, his feet move %.2fpx when he turns" % absf(raw[1] - raw[2]))
	assert_lte(absf(placed[1] - placed[2]), 2.0,
		("his feet move %.2fpx at a turn. <= 2 is the bound OverworldPlayer's bbox rule can reach on this sheet (1.75 measured): "
		+ "his halberd widens the bbox on the side he faces, so feet cannot land exactly with the shared rule") % absf(placed[1] - placed[2]))


func test_a_standing_knight_does_not_hop_when_he_turns_to_talk() -> void:
	var n = OverworldNPC.new()
	n.sprite_archetype = "village_knight"
	add_child_autofree(n)
	await get_tree().process_frame
	var spr := n.find_child("Sprite", true, false) as Sprite2D
	assert_not_null(spr, "CONTROL: the NPC has a sprite")
	var placed := {}
	for d in [2, 3]:
		placed[d] = 0.0
		for col in 4:
			n.facing_direction = d
			n._walk_col = col
			n._apply_facing()
			placed[d] += (_feet_centre(spr.texture.get_image()) + spr.offset.x) / 4.0
	assert_lte(absf(placed[2] - placed[3]), 2.0, "a standing NPC uses the same rule; his feet move %.2fpx when he turns to talk" % absf(placed[2] - placed[3]))


func test_the_shared_rule_leaves_an_unmoving_sheet_alone_and_cancels_a_shift() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for row in 4:
		for col in 4:
			img.fill_rect(Rect2i(col * 16 + 6, row * 16 + 4, 4, 10), Color.WHITE)
	var rows := {"walk_down": 0, "walk_left": 1, "walk_right": 2, "walk_up": 3}
	var still: Dictionary = WanderingNPC.sheet_registration(img, Vector2i(16, 16), rows)
	for d in still:
		assert_eq(float(still[d]), 0.0, "CONTROL: rows that sit at one x get no offset")
	assert_eq(still.size(), 4, "CONTROL: every direction is measured")
	var shifted := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for row in 4:
		for col in 4:
			shifted.fill_rect(Rect2i(col * 16 + 6 + (3 if row == 1 else 0), row * 16 + 4, 4, 10), Color.WHITE)
	var moved: Dictionary = WanderingNPC.sheet_registration(shifted, Vector2i(16, 16), rows)
	assert_eq(float(moved[OverworldPlayer.Direction.LEFT]), -3.0, "a left row drawn 3px right is drawn 3px back")
	assert_eq(float(moved[OverworldPlayer.Direction.RIGHT]), 0.0, "and the unmoved rows are left alone")
