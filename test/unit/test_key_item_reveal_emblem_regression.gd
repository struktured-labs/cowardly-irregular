extends GutTest

## All 21 authored grant_item reveals omit sprite_path (measured 2026-09-11), and items.json
## carries no icon data, so every Zelda-style "You obtained" panel showed a blank 96px band
## under its title — reads as a missing asset. With no sprite the popup now draws an emblem in
## the slot, keyed on the item's ItemSystem category and drawn only with glyphs the font
## fallback chain already proves. The Director passes the item id so the emblem can key on it.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const FontChainTest = preload("res://test/unit/test_font_fallback_chain.gd")

var _host: Node


func before_each() -> void:
	_host = Node.new()
	add_child_autofree(_host)


func test_a_reveal_without_a_sprite_shows_an_emblem_not_a_blank_band() -> void:
	var popup := KeyItemPopup.show_item(_host, {"item_id": "untested_shield", "name": "The Untested Shield", "description": "Bram's gift."})
	assert_not_null(popup._icon, "the slot is filled")
	assert_true(popup._icon is Label, "with an emblem label when there is no sprite")
	assert_eq((popup._icon as Label).text, "✦", "a META-category key item gets the star-of-four emblem")


func test_the_emblem_follows_the_item_category() -> void:
	assert_eq(KeyItemPopup.emblem_glyph("untested_shield"), "✦", "category 4 (META)")
	assert_eq(KeyItemPopup.emblem_glyph("potion"), "♦", "category 0 (CONSUMABLE)")
	assert_eq(KeyItemPopup.emblem_glyph("no_such_item_zzz"), "★", "an unknown item still gets an emblem")


func test_a_reveal_with_a_sprite_keeps_the_sprite() -> void:
	var dir := DirAccess.open("res://assets/sprites/jobs/fighter")
	assert_not_null(dir, "control: the fighter sheet directory exists")
	var png := ""
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".png"):
			png = "res://assets/sprites/jobs/fighter/" + f
			break
		f = dir.get_next()
	dir.list_dir_end()
	assert_ne(png, "", "control: found a real PNG to use as the sprite")
	var popup := KeyItemPopup.show_item(_host, {"item_id": "untested_shield", "name": "X", "description": "y", "sprite_path": png})
	assert_true(popup._icon is TextureRect, "a real sprite still wins the slot: %s" % popup._icon)


func test_every_emblem_is_a_glyph_the_font_chain_proves() -> void:
	# The chain test pins every authored glyph; an emblem outside that set would render as tofu on web.
	var proven: String = FontChainTest.AUTHORED_GLYPHS
	for g in KeyItemPopup.EMBLEM_BY_CATEGORY.values():
		assert_true(proven.contains(g), "emblem %s is not in the proven glyph set" % g)
	assert_true(proven.contains(KeyItemPopup.EMBLEM_DEFAULT))


func test_every_authored_reveal_either_has_its_sprite_or_an_emblem() -> void:
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir)
	dir.list_dir_begin()
	var fname := dir.get_next()
	var reveals := 0
	while fname != "":
		if fname.ends_with(".json"):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string("res://data/cutscenes/" + fname)) == OK and json.data is Dictionary:
				for step in (json.data as Dictionary).get("steps", []):
					if step is Dictionary and step.get("type") == "grant_item":
						reveals += 1
						var sp := str(step.get("sprite_path", ""))
						if sp != "":
							assert_true(ResourceLoader.exists(sp), "%s: sprite_path %s does not exist — the reveal would show a blank slot" % [fname, sp])
						else:
							assert_ne(KeyItemPopup.emblem_glyph(str(step.get("item", ""))), "", "%s: no emblem for %s" % [fname, step.get("item")])
		fname = dir.get_next()
	dir.list_dir_end()
	assert_gt(reveals, 15, "control: the corpus scan saw the authored reveals (21 on 2026-09-11)")


func test_the_director_hands_the_item_id_to_the_reveal() -> void:
	var d := DirectorScript.new()
	add_child_autofree(d)
	d._skipping = false
	var runner := func() -> void:
		await d._step_grant_item({"type": "grant_item", "item": "untested_shield", "name": "The Untested Shield"})
	runner.call()
	await get_tree().process_frame
	var popup: Node = d._key_item_popup
	assert_not_null(popup, "control: the reveal is up")
	if popup:
		assert_true(popup._icon is Label and (popup._icon as Label).text == "✦", "the emblem keyed on the granted item's category, so the id reached the popup")
	d._trigger_skip()
	for i in 20:
		await get_tree().process_frame
	d._active = false
