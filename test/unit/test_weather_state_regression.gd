extends GutTest

## Weather v2 (2026-09-04, Philly demo-night suggestion): weather is GameState-owned so
## villages, battle, saves, and autobattle scripts agree. These pin the state machine.

var _saved: Dictionary = {}


func before_each() -> void:
	_saved = {
		"condition": GameState.weather_condition,
		"timer": GameState.weather_timer,
		"world": GameState._weather_world,
		"current_world": GameState.current_world,
	}


func after_each() -> void:
	GameState.weather_condition = _saved["condition"]
	GameState.weather_timer = _saved["timer"]
	GameState._weather_world = _saved["world"]
	GameState.current_world = _saved["current_world"]


func test_vocabulary_covers_all_six_worlds() -> void:
	for world in range(1, 7):
		assert_true(GameState.WEATHER_VOCAB.has(world), "world %d needs a vocabulary" % world)
		var vocab: Array = GameState.WEATHER_VOCAB[world]
		assert_gt(vocab.size(), 0, "world %d vocabulary must not be empty" % world)
		for entry in vocab:
			assert_ne(str(entry.get("id", "")), "", "every entry needs an id")
			assert_gt(int(entry.get("weight", 0)), 0, "every entry needs a positive weight")
			assert_gt(float(entry.get("min_s", 0.0)), 0.0, "every entry needs a duration floor")
			assert_gte(float(entry.get("max_s", 0.0)), float(entry.get("min_s", 0.0)),
				"max_s must be >= min_s")


func test_w6_is_weatherless_by_design() -> void:
	var vocab: Array = GameState.WEATHER_VOCAB[6]
	assert_eq(vocab.size(), 1, "W6 abstract has exactly one condition")
	assert_eq(str(vocab[0].get("id", "")), "clear", "and it is clear — pinned ruling, like Vertex")


func test_flat_vocabulary_names_the_known_members() -> void:
	var all: Array[String] = GameState.all_weather_conditions()
	for known in ["clear", "rain", "storm", "drizzle", "fog", "smog", "glitchstorm"]:
		assert_true(all.has(known), "flat vocabulary must contain %s" % known)


func test_roll_stays_inside_the_current_worlds_vocabulary() -> void:
	GameState.current_world = 1
	GameState._weather_world = 1
	var legal: Array = []
	for entry in GameState.WEATHER_VOCAB[1]:
		legal.append(str(entry["id"]))
	for i in range(40):
		GameState._roll_weather()
		assert_true(legal.has(GameState.weather_condition),
			"W1 roll produced '%s', outside %s" % [GameState.weather_condition, str(legal)])
		assert_gt(GameState.weather_timer, 0.0, "every roll must arm the timer")


func test_world_change_rerolls_immediately() -> void:
	GameState.current_world = 2
	GameState.set_weather("glitchstorm", 9999.0)
	assert_eq(GameState.get_weather(), "glitchstorm", "CONTROL: the pin must hold")
	GameState.current_world = 1
	GameState._advance_weather(0.016)
	var legal: Array = []
	for entry in GameState.WEATHER_VOCAB[1]:
		legal.append(str(entry["id"]))
	assert_true(legal.has(GameState.get_weather()),
		"entering W1 must re-roll from W1's vocabulary, got '%s'" % GameState.get_weather())


func test_timer_expiry_rerolls_and_signal_fires_on_change() -> void:
	GameState.current_world = 1
	GameState.set_weather("storm", 0.5)
	watch_signals(GameState)
	# Drain past expiry; the roll may land on storm again, so force a distinct pin after.
	GameState._advance_weather(1.0)
	assert_gt(GameState.weather_timer, 0.0, "expiry must arm a fresh timer")
	GameState.set_weather("clear", 60.0)
	if GameState.get_weather() != "storm":
		assert_signal_emitted(GameState, "weather_changed")


func test_save_roundtrip_preserves_weather() -> void:
	GameState.current_world = 1
	GameState.set_weather("storm", 77.0)
	var data: Dictionary = GameState._create_save_data()
	assert_eq(str(data.get("weather_condition", "")), "storm", "condition must serialize")
	assert_almost_eq(float(data.get("weather_timer", 0.0)), 77.0, 0.1, "timer must serialize")
	GameState.weather_condition = "clear"
	GameState.weather_timer = 0.0
	GameState._apply_save_data(data)
	assert_eq(GameState.get_weather(), "storm", "condition must survive the roundtrip")
	# The world-pin must be synced so the next frame does NOT re-roll the loaded weather.
	assert_eq(GameState._weather_world, GameState.current_world,
		"loaded weather must be pinned to the loaded world (pre-fix: pre-load world re-rolled it)")
	GameState._advance_weather(0.016)
	assert_eq(GameState.get_weather(), "storm", "first frame after load must keep the saved weather")


func test_old_save_without_weather_rerolls_fresh() -> void:
	var data: Dictionary = GameState._create_save_data()
	data.erase("weather_condition")
	data.erase("weather_timer")
	GameState._apply_save_data(data)
	assert_eq(GameState._weather_world, 0, "no weather key = unpinned, so the next frame rolls fresh")


func test_new_game_resets_weather() -> void:
	# Source-level: calling reset_game_state() here would wipe the shared singleton
	# mid-suite (the cross-test bleed class). Pin that the reset block covers weather.
	var src := FileAccess.get_file_as_string("res://src/meta/GameState.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i: int = src.find("func reset_game_state(")
	assert_gt(i, -1, "reset_game_state must exist")
	var j: int = src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, (j - i) if j > -1 else src.length() - i)
	assert_true(body.contains("weather_condition = \"clear\""), "New Game must reset the condition")
	assert_true(body.contains("weather_timer = 0.0"), "New Game must unarm the timer")
	assert_true(body.contains("_weather_world = 0"), "New Game must unpin the world so frame one re-rolls")


func test_set_weather_emits_only_on_change() -> void:
	GameState.set_weather("clear", 60.0)
	watch_signals(GameState)
	GameState.set_weather("clear", 60.0)
	assert_signal_not_emitted(GameState, "weather_changed")
	GameState.set_weather("rain", 60.0)
	assert_signal_emitted_with_parameters(GameState, "weather_changed", ["rain"])
