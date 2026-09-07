extends GutTest

## Pins the night_crickets_wind consumer wired in cycle #6 (msg 2672 + 2683):
## SoundManager listens to GameState.time_of_day_changed and toggles the
## ambience via set_night_ambience(bool). Regression against silent breakage
## if the signal/method/manifest key drift apart.

const NIGHT_KEY := "night_crickets_wind"


func test_night_ambience_key_present_in_manifest() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm != null, "SoundManager autoload present")
	assert_true(sm._sfx_manifest.has(NIGHT_KEY), "manifest has night_crickets_wind entry")


func test_night_ambience_constant_matches_manifest() -> void:
	assert_eq(load("res://src/audio/SoundManager.gd").NIGHT_AMBIENCE_KEY, NIGHT_KEY, "NIGHT_AMBIENCE_KEY constant matches manifest slug")


func test_set_night_ambience_method_exists() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm.has_method("set_night_ambience"), "public set_night_ambience method exposed")


func test_set_night_ambience_true_starts_correct_key() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	sm.stop_ambient()
	sm.set_night_ambience(true)
	assert_eq(sm._current_ambient_key, NIGHT_KEY, "true selects night_crickets_wind")
	sm.stop_ambient()


func test_set_night_ambience_false_respects_other_ambient() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	sm._current_ambient_key = "some_other_weather_loop"
	sm.set_night_ambience(false)
	assert_eq(sm._current_ambient_key, "some_other_weather_loop", "false does NOT stop non-night ambience")
	sm.stop_ambient()


func test_set_night_ambience_false_stops_night_only() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	sm.set_night_ambience(true)
	sm.set_night_ambience(false)
	assert_eq(sm._current_ambient_key, "", "false stops night ambience when it was active")


func test_signal_connected_on_ready() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(gs.has_signal("time_of_day_changed"), "GameState exposes time_of_day_changed")
	assert_true(gs.time_of_day_changed.is_connected(sm._on_time_of_day_changed_for_ambience), "SoundManager wired to GameState.time_of_day_changed")


func test_band_change_to_night_toggles_ambience() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	sm.stop_ambient()
	sm._on_time_of_day_changed_for_ambience("night")
	assert_eq(sm._current_ambient_key, NIGHT_KEY, "'night' band starts ambience")
	sm._on_time_of_day_changed_for_ambience("day")
	assert_eq(sm._current_ambient_key, "", "'day' band stops ambience")
