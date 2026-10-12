extends GutTest

## struktured's slime/bat/goblin frame (via cowir-main, 2026-10-12): "the bat's sprite covers the SLIME
## name label". Measured on that exact trio: it is NOT occlusion — NAME_LABEL_Z (5) already beats every
## monster sprite (0), and the text draws on top. The bat's 256px sheet takes ENEMY_SCALE_BUMP and draws
## 608px tall, so SLIME's name lands ON the bat's wing and reads as the BAT's name. The outline and
## shadow were sized against the floor's grid lines; a neighbour's body is a different problem.
## A plate sized to the TEXT is what makes a name read as a tag rather than as text lying on a monster.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const FRAME := 64

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _scene() -> Node:
	var s = load(SCENE).instantiate()
	add_child_autofree(s)
	return s


func _sprite() -> AnimatedSprite2D:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", ImageTexture.create_from_image(img))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = &"idle"
	add_child_autofree(s)
	return s


func _labelled(scene: Node, text: String) -> Array:
	var spr := _sprite()
	scene._add_sprite_label(spr, text, 40.0)
	return [spr, spr.get_node_or_null("NameLabel") as Label, spr.get_node_or_null("NamePlate") as Control]


func test_a_name_carries_a_plate() -> void:
	var r := _labelled(_scene(), "SLIME")
	assert_not_null(r[1], "CONTROL: the sprite must carry a name label")
	assert_not_null(r[2], "a name needs a backing plate to read off a neighbour's body")


func test_the_plate_covers_the_text_and_no_more() -> void:
	var scene := _scene()
	var r := _labelled(scene, "SLIME")
	var label: Label = r[1]
	var plate: Control = r[2]
	if label == null or plate == null:
		fail_test("CONTROL: label and plate must exist")
		return
	var font := label.get_theme_font(&"font")
	var text_w: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1,
		label.get_theme_font_size(&"font_size")).x
	assert_gte(plate.size.x, text_w, "the plate must be at least as wide as the text it backs")
	## Sized to the TEXT, never to NAME_LABEL_WIDTH: the label is a fixed-width centred box, so a
	## plate matching it would be a slab ~%d px wide under a short name.
	assert_lt(plate.size.x, label.size.x,
		"the plate is sized to the text (%0.0f), not to the label's fixed box (%0.0f)" % [plate.size.x, label.size.x])


func test_the_plate_is_centred_on_the_name() -> void:
	var scene := _scene()
	for name_text in ["BAT", "SLIME", "SKELETON KNIGHT"]:
		var r := _labelled(scene, name_text)
		var label: Label = r[1]
		var plate: Control = r[2]
		if label == null or plate == null:
			fail_test("CONTROL: %s has no label/plate" % name_text)
			return
		var label_centre: float = label.position.x + label.size.x * label.scale.x * 0.5
		var plate_centre: float = plate.position.x + plate.size.x * plate.scale.x * 0.5
		assert_almost_eq(plate_centre, label_centre, 0.51,
			"'%s': the plate must sit under its own name, not drift with the name's length" % name_text)


func test_the_plate_sits_under_the_name_and_over_the_battlefield() -> void:
	var scene := _scene()
	var r := _labelled(scene, "SLIME")
	var label: Label = r[1]
	var plate: Control = r[2]
	if label == null or plate == null:
		fail_test("CONTROL: label and plate must exist")
		return
	assert_eq(plate.z_index, label.z_index, "plate and name share a rung, so nothing can land between them")
	assert_lt(plate.get_index(), label.get_index(), "and the plate is drawn FIRST, so the name reads on top of it")
	assert_gt(plate.z_index, 0, "both sit above every monster sprite (z 0), which is what the .590 fix bought")


func test_the_plate_is_opaque_enough_to_hide_a_wing() -> void:
	var scene := _scene()
	var r := _labelled(scene, "SLIME")
	var plate: Control = r[2]
	if plate == null:
		fail_test("CONTROL: no plate")
		return
	var style := plate.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style, "the plate draws a filled box")
	if style == null:
		return
	assert_gt(style.bg_color.a, 0.5,
		"a plate the bat's wing shows through is not a plate (alpha %0.2f)" % style.bg_color.a)
