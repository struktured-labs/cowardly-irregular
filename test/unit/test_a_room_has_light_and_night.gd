extends GutTest

## struktured 2026-11-12: "the inside of the inn is still pretty basic or crude". The first piece of the interior kit:
## one light rig per room. A darkness for the lamps to read against, a look that follows the day clock, a night, and
## the hook the inn's rest scene drives (cutscenes 24212: host.rest_light("night" | "dawn")).

const Inn := preload("res://src/maps/interiors/InnInterior.gd")
const NOON := 0.5
## The sky is darkest between 0.70 and 0.90 of the day (DayNightOverlay.TINT_ANCHORS); 0.0 is already turning to dawn.
const MIDNIGHT := 0.8

var _flicker := true


func before_each() -> void:
	_flicker = InteriorLighting.flicker_enabled
	InteriorLighting.flicker_enabled = false


func after_each() -> void:
	InteriorLighting.flicker_enabled = _flicker


func _rig(phase: float) -> InteriorLighting:
	var rig := InteriorLighting.new()
	rig.phase_override = phase
	add_child_autofree(rig)
	return rig


func _lamp(rig: InteriorLighting, energy: float, flicker: float = 0.0) -> PointLight2D:
	var l := PointLight2D.new()
	l.energy = energy
	rig.add_child(l)
	rig.adopt(l, flicker)
	return l


func _count(node: Node, kind: String) -> int:
	var n := 1 if node.is_class(kind) else 0
	for c in node.get_children():
		n += _count(c, kind)
	return n


func test_a_room_is_dimmer_and_cooler_at_night_and_never_black() -> void:
	assert_almost_eq(InteriorLighting.darkness_for(NOON), 0.0, 0.01, "CONTROL: at noon the room is not dark")
	assert_gt(InteriorLighting.darkness_for(MIDNIGHT), 0.8, "at midnight it is")
	var day := _rig(NOON).tint_now()
	var night := _rig(MIDNIGHT).tint_now()
	assert_lt(day.get_luminance(), 1.0, "a lit room by day sits under white, or a lamp's pool cannot show")
	assert_gt(day.get_luminance(), night.get_luminance() + 0.25, "night is plainly darker than day")
	assert_gt(night.get_luminance(), 0.25, "and never black: the player still sees the room")
	assert_gt(night.b, night.r, "night leans cool")
	assert_gt(day.r, day.b, "day leans warm")


func test_a_lamp_is_lit_by_day_and_carries_the_room_at_night() -> void:
	var by_day := _rig(NOON)
	var by_night := _rig(MIDNIGHT)
	var a := _lamp(by_day, 0.4)
	var b := _lamp(by_night, 0.4)
	by_day._process(0.1)
	by_night._process(0.1)
	assert_gt(a.energy, 0.0, "a lamp is lit at noon")
	assert_lt(a.energy, b.energy, "and brighter at night")
	assert_almost_eq(b.energy, 0.4 * lerpf(InteriorLighting.LAMP_DAY_SHARE, 1.0, InteriorLighting.darkness_for(MIDNIGHT)), 0.001, "by the rig's own rule")
	assert_almost_eq(a.energy, 0.4 * InteriorLighting.LAMP_DAY_SHARE, 0.001, "noon is the day share of its full energy")


func test_a_flicker_wavers_and_the_switch_holds_it_still() -> void:
	var rig := _rig(MIDNIGHT)
	var hearth := _lamp(rig, 0.9, 0.25)
	var steady := _lamp(rig, 0.4)
	rig._process(0.1)
	var h1 := hearth.energy
	var s1 := steady.energy
	rig._process(0.137)
	assert_eq(hearth.energy, h1, "with the switch off a flickering light holds still (the screenshot tool's switch)")
	InteriorLighting.flicker_enabled = true
	rig._process(0.137)
	assert_ne(hearth.energy, h1, "CONTROL: with it on the hearth wavers")
	assert_eq(steady.energy, s1, "and a light adopted with no flicker never does")


func test_the_inn_is_lit_by_one_rig() -> void:
	var inn: Node = Inn.new()
	add_child_autofree(inn)
	await get_tree().process_frame
	assert_not_null(inn.lighting, "the inn builds its rig")
	if inn.lighting == null:
		return
	assert_eq(_count(inn, "CanvasModulate"), 1, "ONE CanvasModulate in the room: two multiply each other")
	var lights := _count(inn, "PointLight2D")
	assert_gt(lights, 4, "CONTROL: the inn has lanterns, corner fills and a hearth (%d lights)" % lights)
	assert_eq(inn.lighting.lamp_count(), lights, "every light in the room answers to the rig, or it would glow at noon as at night")


func test_the_rest_scene_draws_the_room_down_and_hands_it_back() -> void:
	var inn: Node = Inn.new()
	add_child_autofree(inn)
	await get_tree().process_frame
	assert_true(inn.has_method("rest_light"), "the inn answers the rest scene's hook by name")
	if inn.lighting == null or not inn.has_method("rest_light"):
		return
	var rig: InteriorLighting = inn.lighting
	rig.phase_override = NOON
	assert_almost_eq(rig.darkness_now(), 0.0, 0.01, "CONTROL: it is day in the room before anyone rests")
	inn.rest_light("night")
	var waited := 0
	while rig.darkness_now() < 0.99 and waited < 240:
		await get_tree().process_frame
		waited += 1
	assert_gt(rig.darkness_now(), 0.99, "night falls in the room (after %d frames)" % waited)
	inn.rest_light("dawn")
	waited = 0
	while rig._rest_dark >= 0.0 and waited < 240:
		await get_tree().process_frame
		waited += 1
	assert_lt(rig._rest_dark, 0.0, "after dawn the room is the clock's again (after %d frames)" % waited)
	assert_almost_eq(rig.darkness_now(), 0.0, 0.01, "and it is day in it")
