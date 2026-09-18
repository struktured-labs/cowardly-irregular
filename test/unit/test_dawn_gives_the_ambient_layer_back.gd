extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## ⛔ NIGHT TAKES THE AMBIENT LAYER AND NEVER GIVES IT BACK. `set_night_ambience(true)` reaches
## `play_ambient`, which stops whatever was there first; `set_night_ambience(false)` calls
## `stop_ambient()` and stops. Measured 2026-09-18:
##
##   village bed playing · night falls · dawn breaks  ->  _current_ambient_key ""  player NOT playing
##   rain playing        · night falls · day returns  ->  ""  the rain does not come back
##
## 🔑 THE LAYER STAYS SILENT UNTIL SOMETHING ELSE HAPPENS TO WRITE IT — a zone crossing, a weather
## change, or a scene rebuild. At the default 24-minute cycle a player crosses dawn regularly while
## standing still, and after it the place they are standing in has no room tone at all.
##
## ⛔ THIS IS NOT THE OWNERSHIP QUESTION AND DELIBERATELY DOES NOT ANSWER IT. Whether NIGHT should
## outrank rain while it IS night is struktured's call and stays registered. "Night ends and nothing
## hands the layer back" is wrong under every answer to that question, so it is repaired here.
##
## The repair is a CONDUIT, not a barrier: night restores the snapshot it displaced rather than
## re-deriving a default, because only the snapshot knows whether weather or the place owned the
## layer — and asking a host to re-derive can be wrong about that, while a snapshot cannot.

const NIGHT := "night_crickets_wind"
const PLACE := "ambient_village"
const RAIN := "weather_rain"


func before_each() -> void:
	SoundState.restore()


func after_all() -> void:
	SoundState.restore()


func test_floor_the_night_layer_surface_still_exists() -> void:
	for name in ["set_night_ambience", "play_ambient", "stop_ambient"]:
		assert_true(SoundManager.has_method(name), "SoundManager must still expose %s()" % name)
	assert_true("_current_ambient_key" in SoundManager, "SoundManager must still carry _current_ambient_key")
	SoundManager._load_music_manifest()
	for key in [NIGHT, PLACE, RAIN]:
		assert_true(SoundManager._sfx_manifest.has(key) or SoundManager._music_manifest.has(key),
			"FLOOR: '%s' must resolve in one of the two stores, or the arms below drive nothing" % key)


func test_control_night_still_takes_the_layer() -> void:
	SoundManager.play_ambient(PLACE)
	assert_eq(str(SoundManager._current_ambient_key), PLACE, "CONTROL: the place bed must be playing first")
	SoundManager.set_night_ambience(true)
	assert_eq(str(SoundManager._current_ambient_key), NIGHT,
		"CONTROL: night must still displace the place bed, or these arms are about nothing")


func test_dawn_gives_the_ambient_layer_back() -> void:
	SoundManager.play_ambient(PLACE)
	SoundManager.set_night_ambience(true)
	SoundManager.set_night_ambience(false)
	assert_eq(str(SoundManager._current_ambient_key), PLACE,
		"night ended and the layer is '%s' — the place bed it displaced never came back, so the room has no tone until a zone crossing or a scene rebuild writes it" % str(SoundManager._current_ambient_key))
	assert_true(SoundManager._ambient_player.playing,
		"and the ambient player is stopped, which is what silence on this layer actually is")


func test_dawn_gives_the_rain_back_too() -> void:
	## The weather case, because the place hook and the weather bed are different owners and only the
	## snapshot knows which one night displaced.
	SoundManager.play_ambient(RAIN)
	SoundManager.set_night_ambience(true)
	SoundManager.set_night_ambience(false)
	assert_eq(str(SoundManager._current_ambient_key), RAIN,
		"it was raining when night fell and the layer came back as '%s' — a player who stood through one night loses the storm" % str(SoundManager._current_ambient_key))


func test_a_layer_taken_over_during_the_night_is_not_clawed_back() -> void:
	## ⛔ THE OTHER DIRECTION, and it is the one a naive snapshot gets wrong. If the weather starts
	## DURING the night it stomps the crickets itself — night no longer owns the layer, so dawn must
	## leave the rain alone rather than restore a stale snapshot over it.
	SoundManager.play_ambient(PLACE)
	SoundManager.set_night_ambience(true)
	SoundManager.play_ambient(RAIN)
	assert_eq(str(SoundManager._current_ambient_key), RAIN, "CONTROL: the weather took the layer mid-night")
	SoundManager.set_night_ambience(false)
	assert_eq(str(SoundManager._current_ambient_key), RAIN,
		"dawn restored '%s' over the rain that had already taken the layer — night may only give back what it still holds" % str(SoundManager._current_ambient_key))


func test_night_over_silence_still_returns_to_silence() -> void:
	## Nothing was playing, so there is nothing to hand back and the old behaviour is correct.
	SoundManager.stop_ambient()
	SoundManager.set_night_ambience(true)
	SoundManager.set_night_ambience(false)
	assert_eq(str(SoundManager._current_ambient_key), "",
		"night over silence must return to silence, not to a stale snapshot (%s)" % str(SoundManager._current_ambient_key))


func test_a_snapshot_does_not_survive_the_night_it_belongs_to() -> void:
	## ⛔ TWO CYCLES, because a single one cannot see the clear. Night 1 displaces the place bed and
	## dawn hands it back; if the snapshot is not dropped at that point, night 2 over SILENCE hands
	## back a bed from the previous night — a room tone arriving out of nowhere in a place that has
	## none. My own mutation set missed this until I wrote the arm: every mutation I had moved the
	## restore, none moved the CLEAR.
	SoundManager.play_ambient(PLACE)
	SoundManager.set_night_ambience(true)
	SoundManager.set_night_ambience(false)
	assert_eq(str(SoundManager._current_ambient_key), PLACE, "CONTROL: night 1 handed the place bed back")

	SoundManager.stop_ambient()
	SoundManager.set_night_ambience(true)
	SoundManager.set_night_ambience(false)
	assert_eq(str(SoundManager._current_ambient_key), "",
		"night 2 fell over silence and dawn produced '%s' — last night's snapshot outlived the night it belonged to" % str(SoundManager._current_ambient_key))
