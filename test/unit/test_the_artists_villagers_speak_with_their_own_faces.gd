extends GutTest

## Rotha and Roy, the artist's own villagers, spoke with the generic generated "villager" face: a different person.
## Each now speaks with a bust cut from the artist's own walk frame (tools/derive_walker_portrait.py): whole-number
## nearest scaling only, so every colour in the portrait is a colour of his sheet.

const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")
const WALKERS := ["rotha", "roy"]


func _img(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _colours(img: Image) -> Dictionary:
	var out := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 1.0:
				out[c.to_rgba32()] = true
	return out


func test_each_speaks_with_a_portrait_of_their_own() -> void:
	var village: Node = load("res://src/maps/villages/HarmoniaVillage.gd").new()
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	vp.add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame
	var seen := {}
	for n in village.find_children("*", "Area2D", true, false):
		var arch := str(n.get("sprite_archetype"))
		if arch in WALKERS:
			seen[arch] = str(n.get("dialogue_portrait"))
	assert_eq(seen.size(), WALKERS.size(), "CONTROL: both of the artist's villagers are in Harmonia (%s)" % str(seen))
	for id in WALKERS:
		assert_eq(str(seen.get(id, "")), id, "%s speaks with their own portrait, not a generic one" % id)
		assert_eq(str(Dialogue.PORTRAIT_SPRITES.get(id, "")), "res://assets/sprites/portraits/npcs/%s.png" % id)


func test_each_portrait_is_the_artists_pixels_and_nothing_else() -> void:
	for id in WALKERS:
		var portrait := _img("res://assets/sprites/portraits/npcs/%s.png" % id)
		var sheet := _img("res://assets/sprites/npcs/%s/overworld.png" % id)
		assert_not_null(portrait, "CONTROL: %s has a portrait on disk" % id)
		assert_not_null(sheet, "CONTROL: %s has a walk sheet on disk" % id)
		if portrait == null or sheet == null:
			continue
		assert_eq(portrait.get_size(), Vector2i(256, 256), "the size every dialogue portrait is")
		var soft := 0
		for y in portrait.get_height():
			for x in portrait.get_width():
				var a := portrait.get_pixel(x, y).a
				soft += 1 if a > 0.0 and a < 1.0 else 0
		assert_eq(soft, 0, "%s: hard alpha, nearest-neighbour only" % id)
		var allowed := _colours(sheet)
		var mine := _colours(portrait)
		assert_gt(mine.size(), 5, "CONTROL: %s's portrait has art in it" % id)
		var foreign: Array = []
		for c in mine:
			if not allowed.has(c):
				foreign.append(c)
		assert_eq(foreign, [], "%s: every colour comes from the artist's sheet" % id)
		assert_eq(portrait.get_used_rect().end.y, 256, "%s: the bust stands on the frame's lower edge" % id)
