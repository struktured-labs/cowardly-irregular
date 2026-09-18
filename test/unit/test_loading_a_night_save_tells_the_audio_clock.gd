extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## ⛔ `day_phase` HAS THREE WRITERS IN src/ AND ONE EMIT. Only `_advance_day_phase` tells anybody;
## the LOAD path and `reset_game_state` both assign the field silently. @cowir-adhoc's rule, on the
## other door into the audio autoload: the setup emits, the restore does not — except here both ends
## are production code.
##
## 🔑 WHY IT MOSTLY DOES NOT BITE, AND WHERE IT DOES. `GameLoop._start_exploration` re-derives BOTH
## night audio surfaces from a live `is_night()`, and a title-screen load or New Game each build a
## scene — so the compensation is REMOTE and late rather than absent (@cowir-sfx's local-vs-remote
## table). The route that escapes it is `_quick_load_with_toast`, which rebuilds only when already in
## EXPLORATION: quick-load across the band from the autogrind console and the MusicNight low-pass
## stays on the bed that is still playing, until the next exploration entry.
##
## The repair is LOCAL, matching what this same function already does for corruption two lines from
## the silent write: emit on a band change at the write site. Then a fourth route inherits it.

const DAY_PHASE := 0.30
const NIGHT_PHASE := 0.80


var _saved_phase: float = 0.0


func before_each() -> void:
	_saved_phase = GameState.day_phase
	SoundState.restore()
	watch_signals(GameState)


## ⛔ THIS FILE MOVES THE CLOCK, SO IT OWES THE SAME RESTORE IT IS ABOUT. Caught by the detector on my
## own first run: leaving day_phase at 0.85 made the NEXT clock file save a night phase as its
## baseline, and its after_each faithfully announced "night" — so my guard turned a fixed file back
## into a polluter without touching it. Restore the value AND the listener, in that order.
func after_each() -> void:
	GameState.day_phase = _saved_phase
	GameState.time_of_day_changed.emit(GameState.get_time_of_day_name())
	SoundState.restore()


func test_floor_the_clock_surface_still_exists() -> void:
	for name in ["get_time_of_day_name", "is_night", "_apply_save_data", "reset_game_state", "_advance_day_phase"]:
		assert_true(GameState.has_method(name), "GameState must still expose %s()" % name)
	assert_true(GameState.has_signal("time_of_day_changed"), "GameState must still declare time_of_day_changed")


func test_control_the_clock_tick_does_tell_the_listeners() -> void:
	## The one writer that has always emitted. Without this the arm below could pass on a signal
	## nothing ever fires, and the file would be about a listener that does not exist.
	## Delta DERIVED from the live cycle constant, not a literal: _advance_day_phase moves
	## delta / (cycle_minutes * 60), so a hardcoded 1.2 s crosses the 0.60 boundary only at the cycle
	## length that happened to be configured when it was written. My first version used 1.2 and landed
	## on "dusk" — a coincidental-fixture control, which is the one kind that fails on correct code.
	var cycle: float = float(GameState.game_constants.get("day_cycle_minutes", 24.0))
	GameState.day_phase = 0.59
	GameState._advance_day_phase(0.02 * cycle * 60.0)
	assert_eq(GameState.get_time_of_day_name(), "night", "CONTROL: the tick must cross into night")
	assert_signal_emitted_with_parameters(GameState, "time_of_day_changed", ["night"])


func test_loading_a_night_save_tells_the_audio_clock() -> void:
	GameState.day_phase = DAY_PHASE
	assert_eq(GameState.get_time_of_day_name(), "day", "CONTROL: start in daylight")
	GameState._apply_save_data({"day_phase": NIGHT_PHASE})
	assert_eq(GameState.get_time_of_day_name(), "night",
		"CONTROL: the load must actually have moved the clock into night")
	assert_signal_emitted_with_parameters(GameState, "time_of_day_changed", ["night"],
		"loading a night save moved the clock and told nobody — SoundManager's night surfaces are signal-driven, and the only thing that re-derives them is a scene build the quick-load path skips")


func test_a_load_that_stays_in_the_same_band_says_nothing() -> void:
	## The other direction, so the repair cannot be "emit on every load". A band that did not change
	## is not an event, and thrashing the listeners would re-trigger the night taper on every save.
	GameState.day_phase = 0.70
	assert_eq(GameState.get_time_of_day_name(), "night", "CONTROL: already night")
	GameState._apply_save_data({"day_phase": 0.85})
	assert_signal_not_emitted(GameState, "time_of_day_changed",
		"the band did not change, so nothing should have been announced")
