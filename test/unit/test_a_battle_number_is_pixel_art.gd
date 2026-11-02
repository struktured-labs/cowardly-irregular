extends GutTest

## struktured 2026-11-02 (via cowir-main): floating battle numbers "more pixel 16 bit esque ... up to the point where it
## might hurt readability ... a retro feel but with capabilities a retro device couldn't". Every number goes through
## BattleResultsDisplay -> DamageNumber, so these arms drive the real spawn calls and read what was put on screen.

const ResultsScript = preload("res://src/battle/BattleResultsDisplay.gd")

var _scene: Node2D
var _display
var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)
	_scene = Node2D.new()
	add_child_autofree(_scene)
	_display = ResultsScript.new(_scene)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


## One of each kind a player can see, through the same calls the battle makes.
func _spawn_every_kind() -> Array:
	_display.spawn_damage_number(Vector2(100, 100), 12, false, false)
	_display.spawn_damage_number(Vector2(300, 100), 140, false, false)
	_display.spawn_damage_number(Vector2(500, 100), 77, false, true)
	_display.spawn_damage_number(Vector2(700, 100), 30, true, false)
	_display.spawn_damage_number(Vector2(100, 300), 15, true, false, "mp")
	_display.spawn_damage_number(Vector2(300, 300), 1, true, false, "ap")
	_display.spawn_miss_number(Vector2(500, 300))
	_display.spawn_banner(Vector2(700, 300), "IMMUNE")
	_display.spawn_banner(Vector2(900, 300), "RESIST")
	var out: Array = []
	for c in _scene.get_children():
		if c is DamageNumber:
			out.append(c)
	return out


func _labels_under(n: Node) -> int:
	var count := 0
	for c in n.get_children():
		if c is Label or c is RichTextLabel:
			count += 1
		count += _labels_under(c)
	return count


func test_every_number_kind_is_drawn_in_pixel_glyphs() -> void:
	var nums := _spawn_every_kind()
	assert_eq(nums.size(), 9, "nine spawns made nine popups")
	for n in nums:
		assert_true(n._label is PixelText, "%s draws with PixelText" % n._label)
		assert_gt(n._label.glyph_sprites.size(), 0, "'%s' put glyphs on screen" % n._label.text)
		assert_eq(_labels_under(n), 0, "'%s' has no smooth-font Label anywhere under it" % n._label.text)


func test_the_words_on_screen_are_the_ones_the_battle_meant() -> void:
	var texts: Array = []
	for n in _spawn_every_kind():
		texts.append(n._label.text)
	for want in ["12", "140", "77", "30", "15 MP", "+1 AP", "MISS", "IMMUNE", "RESIST"]:
		assert_true(texts.has(want), "'%s' is on screen — got %s" % [want, str(texts)])


func _all_integral(nums: Array) -> String:
	for n in nums:
		if not is_instance_valid(n):
			continue
		if n.scale != Vector2.ONE or n._label.scale != Vector2.ONE:
			return "%s node scale %s / %s" % [n._label.text, n.scale, n._label.scale]
		if n.position != n.position.round():
			return "%s sits between pixels at %s" % [n._label.text, n.position]
		for spr in n._label.glyph_sprites:
			if spr.scale != spr.scale.round() or spr.scale.x < 1.0 or spr.scale.y < 1.0:
				return "%s glyph scale %s" % [n._label.text, spr.scale]
	return ""


## The pop, squash, shake and hop all happen inside this window; every frame of it must stay on whole pixels.
func test_every_frame_of_the_motion_stays_on_whole_pixels() -> void:
	var nums := _spawn_every_kind()
	var frames := 0
	var bad := ""
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 450 and bad == "":
		await get_tree().process_frame
		frames += 1
		bad = _all_integral(nums)
	assert_gt(frames, 5, "the motion was actually sampled (%d frames)" % frames)
	assert_eq(bad, "", "integer scale and position on every frame")


func test_glyphs_are_nearest_filtered() -> void:
	for n in _spawn_every_kind():
		assert_eq(n._label.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "'%s' is nearest-filtered" % n._label.text)


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func test_text_size_grows_the_glyph_pixel_in_whole_steps() -> void:
	var presets := _presets()
	assert_gt(presets.size(), 2, "floor: the Text Size ladder was read")
	var last := 0
	for preset in presets:
		GameState.text_size_scale = float(preset)
		_display.spawn_damage_number(Vector2(100, 100), 12, false, false)
		var n: DamageNumber = _scene.get_child(_scene.get_child_count() - 1)
		var px: Vector2i = n._label.pixel_scale
		assert_eq(px.x, px.y, "square pixels at %s" % preset)
		assert_gt(px.x, last, "Text Size %s grows the glyph pixel past %d (got %d)" % [preset, last, px.x])
		last = px.x


func test_a_crit_glows_and_a_plain_hit_does_not() -> void:
	_display.spawn_damage_number(Vector2(100, 100), 40, false, true)
	_display.spawn_damage_number(Vector2(400, 100), 40, false, false)
	var crit: DamageNumber = _scene.get_child(0)
	var plain: DamageNumber = _scene.get_child(1)
	assert_eq(crit._glow.size(), 4, "a crit carries its additive halo")
	assert_eq((crit._glow[0].material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "the halo is additive")
	assert_eq(plain._glow.size(), 0, "CONTROL: a plain hit has none")
	assert_gt(crit._label.pixel_scale.x, plain._label.pixel_scale.x, "a crit stands a whole pixel bigger")


func test_every_ink_pixel_is_rimmed() -> void:
	for ch in "0123456789MPAISX+%!":
		var img: Image = PixelText.glyph_texture(ch).get_image()
		var bare := 0
		var ink := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y) != Color.WHITE:
					continue
				ink += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + (d as Vector2i)
					if img.get_pixelv(q).a == 0.0:
						bare += 1
		assert_gt(ink, 0, "'%s' has ink" % ch)
		assert_eq(bare, 0, "'%s': no ink pixel touches transparency — the outline is what reads on any floor" % ch)


func test_every_letter_and_digit_has_a_glyph_and_an_unknown_one_is_visible() -> void:
	for ch in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ+-%!":
		assert_true(PixelText.can_draw(ch), "'%s' has a glyph" % ch)
	assert_false(PixelText.can_draw("~"), "CONTROL: '~' has none")
	var t := PixelText.new("~", 2)
	autofree(t)
	assert_eq(t.glyph_sprites.size(), 1, "an unknown character still draws (as '?') instead of vanishing")


## The elemental indicators are the same family; every word they and the negation banners can float has its glyphs.
func test_every_floating_word_is_drawable() -> void:
	for word in ["WEAK!", "RESIST", "IMMUNE!", "IMMUNE", "BLOCK", "MISS", "MP", "AP"]:
		for ch in word:
			assert_true(PixelText.can_draw(ch), "'%s' in %s has a glyph" % [ch, word])
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _spawn_elemental_indicator")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true(body.contains("PixelText.new(text"), "WEAK!/RESIST/IMMUNE! are drawn in PixelText")
	assert_false(body.contains("Label.new()"), "and no smooth Label is built beside them")


## A popup at nameplate height drew UNDER the plate (cowir-adhoc 21469: "M" of MISS left of "GOBLIN B").
func test_a_popup_draws_over_every_nameplate_and_under_the_menu() -> void:
	var nums := _spawn_every_kind()
	var scene_consts: Dictionary = load("res://src/battle/BattleScene.gd").get_script_constant_map()
	var plate_z: int = int(scene_consts.get("NAME_LABEL_Z", -999))
	assert_ne(plate_z, -999, "floor: BattleScene.NAME_LABEL_Z was read")
	for n in nums:
		assert_gt(n.z_index, plate_z, "'%s' (z %d) draws over the nameplates (z %d)" % [n._label.text, n.z_index, plate_z])
		assert_lt(n.z_index, 100, "'%s' stays under the live command menu (z 100)" % n._label.text)
		assert_true(n.z_as_relative, "CONTROL: relative z, parented to the scene root at z 0")
