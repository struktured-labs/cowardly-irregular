extends GutTest

## The overworld horizon kept a private 5-minute phase that started at noon every time the
## map was built. A night save, a battle, or a rest at the inn all come back to a daytime
## sky while the dial, the village lamps, and the battle backdrop still read the real clock.

var _saved_phase: float = 0.0


func before_each() -> void:
	_saved_phase = GameState.day_phase


func after_each() -> void:
	GameState.day_phase = _saved_phase
	GameState.time_of_day_changed.emit(GameState.get_time_of_day_name())
	var gl := get_tree().root.get_node_or_null("GameLoop")
	if gl is _LoopStub:
		var ov = gl._day_night_overlay
		gl.free()
		if ov != null and is_instance_valid(ov):
			ov.free()


func test_a_rebuilt_field_at_night_is_not_a_noon_sky() -> void:
	GameState.day_phase = 0.80
	assert_eq(GameState.get_time_of_day_name(), "night",
		"CONTROL: 0.80 is the night band the dial and the battle backdrop both read")
	var field := _fresh_field()
	field.process_frame()
	var sky: Color = field._shader_mat.get_shader_parameter("time_tint")
	var clock: Color = DayNightOverlay.tint_for_phase(0.80)
	assert_false(clock.is_equal_approx(Color.WHITE),
		"CONTROL: night on the shared curve is not white, or this arm cannot see a noon sky")
	assert_true(sky.is_equal_approx(clock),
		"rebuilt field tint %s — the horizon restarted at noon while the clock was night (%s)" % [sky, clock])


func test_dusk_on_the_clock_is_dusk_on_a_rebuilt_field() -> void:
	GameState.day_phase = 0.55
	assert_eq(GameState.get_time_of_day_name(), "dusk")
	var field := _fresh_field()
	field.process_frame()
	var sky: Color = field._shader_mat.get_shader_parameter("time_tint")
	var clock: Color = DayNightOverlay.tint_for_phase(0.55)
	assert_false(clock.is_equal_approx(Color.WHITE), "CONTROL: dusk tint is not white")
	assert_true(sky.is_equal_approx(clock),
		"rebuilt field tint %s at dusk — expected the clock colour %s" % [sky, clock])


func test_a_world_that_paints_its_own_night_does_not_stack_a_second_one() -> void:
	## W1 already multiplies the whole view by this curve. The horizon shader must stay
	## identity there, or night gets darkened twice.
	GameState.day_phase = 0.80
	var overlay := DayNightOverlay.new()
	overlay.set_outdoor(true)
	var loop := _LoopStub.new()
	loop.name = "GameLoop"
	loop._day_night_overlay = overlay
	get_tree().root.add_child(loop)
	var field := _fresh_field()
	field.process_frame()
	var sky: Color = field._shader_mat.get_shader_parameter("time_tint")
	assert_true(sky.is_equal_approx(Color.WHITE),
		"W1 field tint %s — the fullscreen clock tint is already on, and a second night multiply stacks" % sky)


func test_a_fixed_horizon_does_not_follow_the_clock() -> void:
	## Steampunk stays amber and the digital world stays terminal-blue. Those are presets.
	GameState.day_phase = 0.80
	var field := _fresh_field()
	field.day_night_enabled = false
	field._fixed_tint = Color(1.0, 0.85, 0.65)
	field.process_frame()
	var sky: Color = field._shader_mat.get_shader_parameter("time_tint")
	assert_true(sky.is_equal_approx(Color(1.0, 0.85, 0.65)),
		"fixed-tint world moved with the clock (%s)" % sky)


func _fresh_field() -> Mode7Overlay:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var player := Node2D.new()
	player.name = "Player"
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	player.add_child(sprite)
	var field := Mode7Overlay.new()
	field.day_night_enabled = true
	field._player_ref = player
	field._player_overlay_sprite = Sprite2D.new()
	field._player_overlay_sprite.name = "PlayerSprite"
	field._shader_mat = ShaderMaterial.new()
	field._shader_mat.shader = load("res://src/shaders/mode7.gdshader")
	add_child_autofree(player)
	add_child_autofree(field)
	field.add_child(field._player_overlay_sprite)
	return field


class _LoopStub extends Node:
	var _day_night_overlay = null
