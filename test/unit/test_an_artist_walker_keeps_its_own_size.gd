extends GutTest

## The artist's first overworld villager (Rotha, 2026-10-08 drop) is drawn 24x47, not the 32px chibi the AI placeholders
## are. Both overworld NPC renderers sliced every sheet as 32x32 cells, which would have cut her into pieces, and artist
## pixels are never resampled to fit. A sheet now DECLARES its cell size (manifest frame_width/frame_height), the
## renderers slice by it, and a taller figure is lifted so her feet stand where a 32px walker's do.

const WanderScript := preload("res://src/exploration/WanderingNPC.gd")
const NpcScript := preload("res://src/exploration/OverworldNPC.gd")
const SHEET := "res://assets/sprites/npcs/rotha/overworld.png"


func _manifest_entry(id: String) -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return (m.get("overworld_npc_sheets", {}) as Dictionary).get(id, {})


func test_rotha_is_registered_as_the_artists_at_her_own_size() -> void:
	var e := _manifest_entry("rotha")
	assert_eq(str(e.get("tier", "")), "T2", "Rotha is artist art")
	var tex := load(SHEET) as Texture2D
	assert_not_null(tex, "CONTROL: her sheet loads")
	assert_eq(Vector2i(tex.get_size()), Vector2i(int(e.get("frame_width", 0)) * 4, int(e.get("frame_height", 0)) * 4),
		"the sheet is a 4x4 grid of the cells it declares")
	assert_gt(int(e.get("frame_height", 0)), 32, "CONTROL: she is taller than a 32px placeholder cell")


func test_her_pixels_are_the_artists_untouched() -> void:
	## Hard alpha and a small palette: a resampled sheet has soft edges and hundreds of blended colours.
	var img: Image = (load(SHEET) as Texture2D).get_image().duplicate()
	img.convert(Image.FORMAT_RGBA8)
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


func test_a_wandering_villager_slices_her_cells_and_stands_on_the_ground_line() -> void:
	var e := _manifest_entry("rotha")
	var w = WanderScript.new()
	w.sprite_archetype = "rotha"
	add_child_autofree(w)
	await get_tree().process_frame
	var spr := w.find_child("Sprite", true, false) as Sprite2D
	assert_not_null(spr, "CONTROL: the wanderer has a sprite")
	assert_eq(Vector2i(spr.texture.get_size()), Vector2i(int(e["frame_width"]), int(e["frame_height"])), "one whole cell, not a 32px piece of it")
	assert_eq(spr.offset.y, -(float(e["frame_height"]) - 32.0) / 2.0, "lifted so her feet are where a 32px walker's are")
	var plain = WanderScript.new()
	plain.sprite_archetype = "young_woman"
	add_child_autofree(plain)
	await get_tree().process_frame
	var ps := plain.find_child("Sprite", true, false) as Sprite2D
	assert_eq(Vector2i(ps.texture.get_size()), Vector2i(32, 32), "CONTROL: a placeholder still slices 32px cells")


func test_a_standing_npc_slices_her_cells_too() -> void:
	var e := _manifest_entry("rotha")
	var n = NpcScript.new()
	n.sprite_archetype = "rotha"
	add_child_autofree(n)
	await get_tree().process_frame
	var spr := n.find_child("Sprite", true, false) as Sprite2D
	assert_not_null(spr, "CONTROL: the NPC has a sprite")
	assert_eq(Vector2i(spr.texture.get_size()), Vector2i(int(e["frame_width"]), int(e["frame_height"])), "one whole cell")
	assert_eq(spr.offset.y, -(float(e["frame_height"]) - 32.0) / 2.0, "feet on the ground line")


func test_rotha_walks_harmonia() -> void:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var village: Node = load("res://src/maps/villages/HarmoniaVillage.gd").new()
	vp.add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame
	var found: Node = null
	for n in village.find_children("*", "Area2D", true, false):
		if str(n.get("sprite_archetype")) == "rotha":
			found = n
	assert_not_null(found, "a villager in Harmonia wears Rotha's sheet")
	if found:
		assert_eq(str(found.get("npc_name")), "Rotha")
		# Wanderers do not collide: every cell of her loop must be ground a villager could stand on
		var a := Vector2i((found as Node2D).position / 32.0)
		var blocked: Array = []
		for x in range(a.x, a.x + 6):
			if not village._is_cell_walkable(Vector2i(x, a.y)):
				blocked.append(Vector2i(x, a.y))
		assert_eq(blocked, [], "her loop crosses unwalkable cells")
