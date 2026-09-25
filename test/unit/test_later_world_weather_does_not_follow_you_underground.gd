extends GutTest

## World 1 stops its outdoor loop in OverworldScene._exit_tree, because a dungeon never
## touches the ambient layer and the rain otherwise plays for the whole cave. Worlds 2-5
## render the same weather and each has a dungeon (Suburban Underground, the Mechanism,
## Assembly Core, Root Process), but their _exit_tree only tears down Mode 7. The weather
## bed keeps playing after the map is gone.


const SoundState := preload("res://test/unit/helpers/sound_state.gd")

const WORLDS := [
	{"script": preload("res://src/exploration/SuburbanOverworld.gd"), "weather": "drizzle", "bed": "weather_rain", "where": "Suburban Underground", "flag": "w2_entered"},
	{"script": preload("res://src/exploration/SteampunkOverworld.gd"), "weather": "fog", "bed": "weather_steam", "where": "the Mechanism", "flag": "w3_entered"},
	{"script": preload("res://src/exploration/IndustrialOverworld.gd"), "weather": "smog", "bed": "weather_smog", "where": "Assembly Core", "flag": "w4_entered"},
	{"script": preload("res://src/exploration/FuturisticOverworld.gd"), "weather": "glitchstorm", "bed": "weather_glitch", "where": "Root Process", "flag": "w5_entered"},
]

var _saved_weather: String = "clear"
var _saved_timer: float = 0.0
var _saved_pin: int = 0
var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_weather = GameState.weather_condition
	_saved_timer = GameState.weather_timer
	_saved_pin = GameState._weather_world
	for row in WORLDS:
		_saved_flags[row["flag"]] = GameState.get_story_flag(row["flag"])
	SoundManager.stop_ambient()


func after_each() -> void:
	GameState.weather_condition = _saved_weather
	GameState.weather_timer = _saved_timer
	GameState._weather_world = _saved_pin
	for flag in _saved_flags:
		GameState.set_story_flag(flag, bool(_saved_flags[flag]))
	SoundState.restore()


func test_leaving_w2_through_w5_stops_the_weather_bed() -> void:
	for row in WORLDS:
		GameState.set_weather(str(row["weather"]), 999.0)
		var ow: Node = (row["script"] as GDScript).new()
		add_child(ow)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(SoundManager._current_ambient_key, str(row["bed"]),
			"CONTROL: %s must be playing before %s is left, or a silent exit proves nothing" % [row["bed"], row["where"]])
		assert_true(SoundManager._ambient_player.playing,
			"CONTROL: the weather bed must actually be sounding")
		ow.free()
		await get_tree().process_frame
		assert_eq(SoundManager._current_ambient_key, "",
			"leaving for %s kept '%s' playing — that dungeon sets no bed of its own, so the outdoor weather lasts the whole cave" % [row["where"], SoundManager._current_ambient_key])
		assert_false(SoundManager._ambient_player.playing,
			"and the player must be stopped, not merely renamed, on the way into %s" % row["where"])
