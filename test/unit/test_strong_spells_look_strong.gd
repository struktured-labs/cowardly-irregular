extends GutTest

## struktured 2026-10-03: "the strong forms of some spell should have more crazy icon ... could also be 'bolded' or duplicated horiz, or flashing, or animating".
## Tier comes from each ability's own data: tier 2 draws a hot horizontal echo + glint (static), tier 3 also animates (gold rim, breathing halo, twinkling star).


func _ink(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				n += 1
	return n


func _tiered(tier: int) -> Array[String]:
	var out: Array[String] = []
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	for id in data:
		if int(data[id].get("tier", 0)) == tier:
			out.append(str(id))
	return out


func test_every_tier_two_spell_is_doubled_and_still() -> void:
	var ids := _tiered(2)
	assert_gt(ids.size(), 0, "SCOPE: the data carries tier-2 spells")
	for id in ids:
		var base_id: String = id
		var t2: Image = AbilityIcons.tinted(id).get_image()
		assert_eq(t2.get_size(), Vector2i(16, 16), "%s stays 16x16; emphasis must not grow the row" % id)
		assert_false(AbilityIcons._animated.has(base_id), "%s is tier 2: emphasised, not animated" % id)
	var plain: Image = AbilityIcons.tinted("fire").get_image()
	var maior: Image = AbilityIcons.tinted("fira").get_image()
	assert_gt(_ink(maior), _ink(plain) + 8, "Ignis Maior must carry the echo and glint the plain Ignis lacks")


func test_every_tier_three_spell_animates() -> void:
	var ids := _tiered(3)
	assert_gt(ids.size(), 0, "SCOPE: the data carries tier-3 spells")
	for id in ids:
		var tex: Texture2D = AbilityIcons.tinted(id)
		assert_true(AbilityIcons._animated.has(id), "%s is tier 3 and must animate" % id)
		assert_eq(tex.get_size(), Vector2(16, 16), "%s stays 16x16" % id)
		assert_gt(_ink(tex.get_image()), 0, "%s's live texture still reads back pixels" % id)
		var frames: Array = AbilityIcons._animated[id]["frames"]
		assert_gt(frames.size(), 3, "%s needs real frames" % id)
		var distinct := {}
		for f in frames:
			distinct[(f as Image).get_data()] = true
		assert_gt(distinct.size(), 3, "%s's frames must differ (a still image is not an animation)" % id)


func test_the_driver_swaps_the_shared_texture_in_place() -> void:
	var tex: ImageTexture = AbilityIcons.tinted("firaga")
	assert_same(AbilityIcons.tinted("firaga"), tex, "every row shares ONE texture, so one swap animates them all")
	var a: Dictionary = AbilityIcons._animated["firaga"]
	a["shown"] = -1
	AbilityIcons._tick_animated()
	var shown: int = int(a["shown"])
	assert_between(shown, 0, AbilityIcons.MAXIMUS_FRAMES - 1, "the driver picked a frame")
	var want := int(Time.get_ticks_msec() / AbilityIcons.MAXIMUS_FRAME_MSEC) % AbilityIcons.MAXIMUS_FRAMES
	assert_true(shown == want or shown == (want + AbilityIcons.MAXIMUS_FRAMES - 1) % AbilityIcons.MAXIMUS_FRAMES,
		"the driver shows the frame the clock names (headless can't read back an update(); a real-GL capture proves the pixels)")


func test_a_plain_spell_is_untouched() -> void:
	assert_eq(AbilityIcons.tier_of("fire"), 1, "SCOPE: Ignis is tier 1")
	assert_false(AbilityIcons._animated.has("fire"), "a tier-1 spell does not animate")
	assert_eq(AbilityIcons.tier_of("power_strike"), 0, "an untiered ability reads tier 0")
