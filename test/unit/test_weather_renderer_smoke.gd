extends GutTest

## Weather v2 renderer: WeatherSystem is now a pure view of GameState.weather_condition.
## Renders every condition without error, and the state actually drives the visuals.

var _saved_condition: String = ""
var _saved_timer: float = 0.0
var _saved_world_pin: int = 0


func before_each() -> void:
	_saved_condition = GameState.weather_condition
	_saved_timer = GameState.weather_timer
	_saved_world_pin = GameState._weather_world


func after_each() -> void:
	GameState.weather_condition = _saved_condition
	GameState.weather_timer = _saved_timer
	GameState._weather_world = _saved_world_pin


func _make_weather() -> Array:
	var host := Node2D.new()
	add_child_autofree(host)
	var player := Node2D.new()
	host.add_child(player)
	var w := WeatherSystem.new()
	host.add_child(w)
	w.setup(host, player, "medieval")
	return [host, player, w]


func test_every_condition_renders_without_error() -> void:
	var parts := _make_weather()
	var w: WeatherSystem = parts[2]
	for condition in GameState.all_weather_conditions():
		GameState.set_weather(condition, 999.0)
		for i in range(3):
			w.process(0.05)
		assert_eq(w._rendered_condition, condition, "renderer must track state to '%s'" % condition)


func test_rain_family_drives_the_emitter() -> void:
	var parts := _make_weather()
	var w: WeatherSystem = parts[2]
	GameState.set_weather("storm", 999.0)
	w.process(0.05)
	assert_true(w._rain_emitter.emitting, "storm must rain")
	assert_gt(w._rain_emitter.amount, 100, "and harder than plain rain")
	GameState.set_weather("clear", 999.0)
	w.process(0.05)
	assert_false(w._rain_emitter.emitting, "clear must stop the rain")


func test_fog_breathes_and_clear_restores_the_world_tint() -> void:
	var parts := _make_weather()
	var w: WeatherSystem = parts[2]
	GameState.set_weather("fog", 999.0)
	w.process(0.05)
	assert_true(w._fog_breathe, "fog must enable overlay breathing")
	GameState.set_weather("clear", 999.0)
	w.process(0.05)
	assert_false(w._fog_breathe, "clear must disable it")
	assert_almost_eq(w._overlay_target_alpha, float(WeatherSystem.WORLD_TINTS["medieval"].a), 0.001,
		"clear must fall back to the world's ambient tint")


func test_abstract_world_gets_no_weather_layer() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var w := WeatherSystem.new()
	host.add_child(w)
	w.setup(host, host, "abstract")
	assert_null(w._canvas, "W6 abstract is weatherless BY DESIGN — no layer, no cost")
	w.process(0.05)
	pass_test("processing without a canvas must be a no-op, not a crash")


func test_villages_wire_the_same_renderer() -> void:
	# Source-level: BaseVillage instantiates WeatherSystem in _ready and pumps it.
	var src := FileAccess.get_file_as_string("res://src/maps/villages/BaseVillage.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true(src.contains("_setup_weather()"), "village _ready must set up weather")
	assert_true(src.contains("WeatherSystem.new()"), "villages use the SAME renderer as overworlds")
	assert_true(src.contains("_weather.process(delta)"), "and must pump it, or the layer freezes")


func test_world_id_mapping_covers_all_worlds() -> void:
	for n in range(1, 7):
		assert_ne(WeatherSystem.world_id_for(n), "", "world %d must map to a renderer id" % n)
	assert_eq(WeatherSystem.world_id_for(6), "abstract")
	assert_eq(WeatherSystem.world_id_for(99), "abstract", "unknown worlds fail safe to weatherless")
