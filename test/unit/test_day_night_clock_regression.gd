extends GutTest

## Day/night clock (struktured 2026-07-16: "there should be a day/night system...
## monsters should get harder at night, encounter rate goes up... nice visuals").
## GameState owns the canonical clock; every downstream seam (BattleEnemySpawner
## night multiplier, autogrind parity, music bus, interior tint) gates on this API.

var _saved_phase: float = 0.0
var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_phase = GameState.day_phase
	_saved_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.day_phase = _saved_phase
	GameState.game_constants = _saved_constants.duplicate(true)


func test_band_names_across_cycle() -> void:
	GameState.day_phase = 0.05
	assert_eq(GameState.get_time_of_day_name(), "dawn")
	GameState.day_phase = 0.30
	assert_eq(GameState.get_time_of_day_name(), "day")
	GameState.day_phase = 0.55
	assert_eq(GameState.get_time_of_day_name(), "dusk")
	GameState.day_phase = 0.80
	assert_eq(GameState.get_time_of_day_name(), "night")


func test_is_night_matches_band() -> void:
	GameState.day_phase = 0.80
	assert_true(GameState.is_night())
	GameState.day_phase = 0.30
	assert_false(GameState.is_night())


func test_advance_wraps_at_full_cycle() -> void:
	GameState.game_constants["day_cycle_minutes"] = 1.0
	GameState.day_phase = 0.95
	GameState._advance_day_phase(6.0)
	assert_almost_eq(GameState.day_phase, 0.05, 0.001,
		"phase must wrap through 1.0 (0.95 + 6s/60s = 1.05 → 0.05)")


func test_zero_cycle_minutes_freezes_clock() -> void:
	GameState.game_constants["day_cycle_minutes"] = 0.0
	GameState.day_phase = 0.30
	GameState._advance_day_phase(10.0)
	assert_eq(GameState.day_phase, 0.30, "cycle <= 0 must freeze, not div-by-zero")


func test_band_change_emits_signal() -> void:
	GameState.game_constants["day_cycle_minutes"] = 1.0
	GameState.day_phase = 0.59
	watch_signals(GameState)
	GameState._advance_day_phase(1.2)
	assert_signal_emitted_with_parameters(GameState, "time_of_day_changed", ["night"])


func test_persistence_roundtrip() -> void:
	GameState.day_phase = 0.73
	var data: Dictionary = GameState.to_dict()
	assert_almost_eq(float(data.get("day_phase", -1.0)), 0.73, 0.001)
	GameState.day_phase = 0.10
	GameState._apply_save_data({"day_phase": 0.73})
	assert_almost_eq(GameState.day_phase, 0.73, 0.001)


func test_new_game_resets_to_morning() -> void:
	# Only assert the field this test owns — full reset_game_state() would nuke live party state.
	assert_almost_eq(GameState.DAY_PHASE_NEW_GAME, 0.15, 0.001,
		"new game starts mid-morning so first-session players see full daylight")
	var src := FileAccess.get_file_as_string("res://src/meta/GameState.gd")
	var reset_at := src.find("func reset_game_state")
	var body := src.substr(reset_at, 900)
	assert_true("day_phase = DAY_PHASE_NEW_GAME" in body,
		"reset_game_state must reset the clock — a New Game inheriting prior-run night is the quests/crystals leak class")


func test_overlay_tint_day_is_white_night_is_cool_dark() -> void:
	var day: Color = DayNightOverlay.tint_for_phase(0.30)
	assert_true(day.is_equal_approx(Color(1, 1, 1)), "full day = no tint (draw skipped)")
	var night: Color = DayNightOverlay.tint_for_phase(0.80)
	assert_lt(night.r, 0.6, "night multiply must darken")
	assert_gt(night.b, night.r, "night leans blue, not gray")


func test_overlay_tint_continuous_at_band_edges() -> void:
	# No popping: adjacent phases across the dusk->night anchor stay close.
	var a: Color = DayNightOverlay.tint_for_phase(0.599)
	var b: Color = DayNightOverlay.tint_for_phase(0.601)
	assert_lt(abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b), 0.05,
		"tint must lerp smoothly across band edges")


func test_gameloop_wires_overlay_and_band_consumer() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("DayNightOverlay.new()" in src, "GameLoop must own the overlay")
	assert_true("time_of_day_changed.connect(_on_time_of_day_changed)" in src,
		"band-change fan-out must be connected")
	assert_true("exploration_scene is OverworldScene or exploration_scene is BaseVillage" in src,
		"outdoor gate: overworld + villages tint, interiors/caves do not")
