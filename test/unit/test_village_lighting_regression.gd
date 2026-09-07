extends GutTest

## Outdoor lighting moves from a fullscreen multiply rect to a per-scene CanvasModulate so
## PointLight2D lamps can pierce the dusk. Pins: the modulate colour is the SAME curve the
## overlay used (no look change at any phase), lamps are dark at noon and lit at night, and
## GameLoop stops tinting a scene that lights itself (no double darkening).

const VL := preload("res://src/exploration/VillageLighting.gd")


func test_modulate_tracks_the_overlay_curve() -> void:
	for p in [0.0, 0.07, 0.3, 0.57, 0.75, 0.95]:
		assert_eq(VL.tint_for(p), DayNightOverlay.tint_for_phase(p), "phase %.2f matches the overlay" % p)


func test_lamp_energy_is_zero_at_noon_and_full_at_night() -> void:
	assert_almost_eq(VL.lamp_energy_for(Color(1, 1, 1), 0.9), 0.0, 0.001, "noon: lamps off")
	assert_almost_eq(VL.lamp_energy_for(Color(0.45, 0.50, 0.78), 0.9), 0.9, 0.001, "deep night: full")
	var dusk := VL.lamp_energy_for(Color(1.0, 0.78, 0.62), 0.9)
	assert_gt(dusk, 0.0)
	assert_lt(dusk, 0.9)


func test_add_lamp_builds_a_point_light_with_a_texture() -> void:
	var l := VL.new()
	add_child_autofree(l)
	var lamp := l.add_lamp(Vector2(100, 50))
	assert_true(lamp is PointLight2D)
	assert_not_null(lamp.texture, "radial texture generated")
	assert_eq(lamp.position, Vector2(100, 50))
	assert_eq(lamp.get_parent(), l, "lamps live under the lighting node")
	l.phase_override = 0.75
	assert_eq(l.tint_now(), DayNightOverlay.tint_for_phase(0.75), "override pins the phase for tooling")


func test_base_village_lights_itself_by_default() -> void:
	var v := BaseVillage.new()
	add_child_autofree(v)
	assert_true(v.has_scene_lighting())
	assert_true(v.lighting is CanvasModulate)


func test_game_loop_hands_the_tint_to_scene_lit_villages() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i := src.find("var outdoor_scene: bool =")
	assert_gt(i, -1)
	var window := src.substr(i, 600)
	assert_true("has_scene_lighting" in window, "GameLoop asks the scene whether it lights itself")
	assert_true("_day_night_overlay.set_outdoor(outdoor_scene and not scene_lit)" in window, "overlay off for scene-lit maps")
	assert_true("_day_clock.set_outdoor(outdoor_scene)" in window, "the day clock still knows it is outdoors")
