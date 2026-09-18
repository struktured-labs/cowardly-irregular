extends GutTest

## ⛔ THE SECOND DOOR INTO THE AUDIO AUTOLOAD, AND THE ONE THE CORRUPTION DETECTOR CANNOT SEE.
## @cowir-sfx measured SoundManager as a pure SINK with exactly two inbound signals from GameState:
## `corruption_changed` and `time_of_day_changed`. The corruption side already has a fixture arm
## ("teardown left a rendered detune"); the night side had none, so a file that drives the clock and
## restores the NUMBER without the LISTENER leaves the next file a night filter and a cricket loop.
##
## 🔑 THE VICTIM SURFACE IS DIFFERENT, WHICH IS WHY THE EXISTING DETECTOR IS SILENT ABOUT IT:
## `_current_ambient_key` satisfies play_ambient's "already playing this ambient" early return, and
## the MusicNight bus effects are a low-pass plus reverb over EVERY music player — a later file
## measuring a bed hears it through a filter nobody turned on.
##
## @cowir-adhoc's rule is the one being enforced: restore through the same door you mutated through.

const NIGHT_KEY := "night_crickets_wind"


func test_the_night_surface_is_clean_for_the_next_file() -> void:
	assert_true(SoundManager.has_method("are_night_music_effects_enabled"),
		"FLOOR: the night toggle must still be readable, or this arm reports clean about nothing")
	assert_true("_current_ambient_key" in SoundManager,
		"FLOOR: SoundManager must still carry _current_ambient_key")
	assert_false(bool(SoundManager.are_night_music_effects_enabled()),
		"a fixture left the MusicNight low-pass and reverb ENABLED — every later file measures its bed through a filter nobody turned on")
	assert_ne(str(SoundManager._current_ambient_key), NIGHT_KEY,
		"a fixture left the night ambience loop running; play_ambient's already-playing return means the next file's own ambient never starts")
