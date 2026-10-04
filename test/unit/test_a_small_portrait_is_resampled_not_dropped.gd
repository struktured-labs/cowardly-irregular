extends GutTest

## The dialogue boxes stopped pixel-dropping their portraits (test_a_portrait_is_resampled_not_dropped); four other
## surfaces draw the same 256px painted art far smaller, under the same NEAREST filter, and kept dropping it:
##   save slot 32px (0.125x, by rect.scale) · victory card chip 40px (0.16x) · shop keeper 64px (0.25x) ·
##   CharacterPortrait 32-96px (an explicit INTERPOLATE_NEAREST resize).
## Each surface is built for real and judged on what it DRAWS. Source pixels are captured BEFORE the surface is built:
## CharacterPortrait resized the texture's own Image in place, which headless shrank the source for every later reader.

const Judge := preload("res://test/unit/helpers/portrait_judge.gd")
const SaveScreenScript := preload("res://src/ui/SaveScreen.gd")
const OverlayScript := preload("res://src/battle/VictoryOverlay.gd")
const ShopScript := preload("res://src/exploration/ShopScene.gd")
const PortraitScript := preload("res://src/ui/CharacterPortrait.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]


class FakeScene:
	extends Node2D
	var party_sprite_nodes: Array = []


func _source(path: String) -> Image:
	return Judge.pixels(load(path))


func _rects(n: Node) -> Array:
	var out: Array = []
	if n is TextureRect:
		out.append(n)
	for c in n.get_children():
		out.append_array(_rects(c))
	return out


func test_a_save_slot_portrait_is_resampled() -> void:
	var screen = SaveScreenScript.new()
	autofree(screen)
	var bad: Array = []
	for job in STARTERS:
		var src := _source(HybridSpriteLoader.portrait_path(job))
		var slot: Control = screen._make_slot_portrait(job)
		add_child_autofree(slot)
		await get_tree().process_frame
		assert_true(slot is TextureRect, "CONTROL: the %s's slot shows its portrait art" % job)
		var why := Judge.judge("save/" + job, slot as TextureRect, src)
		if why != "":
			bad.append(why)
	assert_eq(bad, [], "save-slot portraits drawn dropped: %s" % str(bad))


func test_a_victory_card_chip_is_resampled() -> void:
	var scene := FakeScene.new()
	add_child_autofree(scene)
	var crs: Array = []
	for i in STARTERS.size():
		var s := Node2D.new()
		s.position = Vector2(700 - 40 * i, 120 + 90 * i)
		scene.add_child(s)
		scene.party_sprite_nodes.append(s)
		crs.append({"name": "PC%d" % i, "job_name": STARTERS[i].capitalize(), "is_alive": true, "exp_gained": 10,
			"leveled_up": false, "job_level": 1, "job_exp": 5, "job_exp_before": 0, "exp_to_next": 100})
	var sources := {}
	for job in STARTERS:
		sources[job] = _source(HybridSpriteLoader.portrait_path(job))
	var overlay: Control = OverlayScript.new()
	add_child_autofree(overlay)
	overlay.build({"char_results": crs, "gold": 0, "items": []}, scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var chips: Array = _rects(overlay).filter(func(r: TextureRect) -> bool: return r.custom_minimum_size == Vector2(40, 40))
	assert_eq(chips.size(), STARTERS.size(), "CONTROL: one portrait chip per card")
	var bad: Array = []
	for i in chips.size():
		var why := Judge.judge("chip/" + STARTERS[i], chips[i], sources[STARTERS[i]])
		if why != "":
			bad.append(why)
	assert_eq(bad, [], "victory chips drawn dropped: %s" % str(bad))


func test_a_shopkeeper_portrait_is_resampled() -> void:
	var bad: Array = []
	var judged := 0
	for type in ShopScript.KEEPER_PORTRAIT_PATHS:
		var path := str(ShopScript.KEEPER_PORTRAIT_PATHS[type])
		if not ResourceLoader.exists(path):
			continue
		var src := _source(path)
		var shop = ShopScript.new()
		shop.shop_type = type
		add_child_autofree(shop)
		var panel: Control = shop._create_description_panel()
		add_child_autofree(panel)
		await get_tree().process_frame
		var rects := _rects(panel)
		assert_eq(rects.size(), 1, "CONTROL: the %s keeper panel shows one portrait" % path.get_file())
		if rects.is_empty():
			continue
		judged += 1
		var why := Judge.judge("keeper/" + path.get_file(), rects[0], src)
		if why != "":
			bad.append(why)
	assert_eq(judged, ShopScript.KEEPER_PORTRAIT_PATHS.size(), "CONTROL: every keeper with art was judged")
	assert_eq(bad, [], "shopkeeper portraits drawn dropped: %s" % str(bad))


func test_a_character_portrait_widget_is_resampled_at_every_size() -> void:
	var bad: Array = []
	for size in PortraitScript.PortraitSize.values():
		for job in STARTERS:
			var src := _source(HybridSpriteLoader.portrait_path(job))
			var w = PortraitScript.new(null, job, size)
			add_child_autofree(w)
			await get_tree().process_frame
			var rects := _rects(w)
			if rects.is_empty():
				bad.append("%s@%s: no portrait art shown" % [job, size])
				continue
			var why := Judge.judge("widget/%s@%d" % [job, size], rects[0], src)
			if why != "":
				bad.append(why)
	assert_eq(bad, [], "CharacterPortrait faces drawn dropped: %s" % str(bad.slice(0, 6)))


func test_no_surface_shrinks_the_source_art() -> void:
	## A CharacterPortrait built over a portrait the test still holds must leave that portrait's Image its own size.
	var bad: Array = []
	for job in STARTERS:
		var tex: Texture2D = load(HybridSpriteLoader.portrait_path(job))
		var w = PortraitScript.new(null, job, PortraitScript.PortraitSize.MEDIUM)
		add_child_autofree(w)
		await get_tree().process_frame
		if tex.get_image().get_size() != Vector2i(tex.get_size()):
			bad.append("%s: image %s, texture %s" % [job, tex.get_image().get_size(), tex.get_size()])
	assert_eq(bad, [], "a portrait surface resized the source art in place: %s" % str(bad))


func test_a_fitted_face_names_the_art_it_came_from() -> void:
	## A resampled face is an ImageTexture with no resource_path; guards that tell portrait ART from a procedural face
	## (test_shopkeeper_portrait_wiring) read resource_name instead, so it must carry the source.
	var path := HybridSpriteLoader.portrait_path("bard")
	var fitted: Texture2D = HybridSpriteLoader.fitted_portrait(load(path), Vector2(40, 40))
	assert_eq(fitted.resource_path, "", "CONTROL: a fitted face has no file of its own")
	assert_eq(fitted.resource_name, path, "a fitted face names its source art")
