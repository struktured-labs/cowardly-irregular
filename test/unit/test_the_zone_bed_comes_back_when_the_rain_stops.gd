extends GutTest

## In World 1 the overworld goes SILENT after every rain shower.
##
## WeatherSystem owns the ambient layer while weather is on, and hands it back by playing the
## world's fair-weather bed. WORLD_CLEAR_AMBIENTS names one for suburban, steampunk, industrial
## and digital. It names none for MEDIEVAL -- the only fully playable world -- so the clear branch
## falls to `_: stop_ambient()`. Measured on the shipped code:
##
##     zone bed playing        ambient_forest
##     rain starts             weather_rain        <- correct, weather takes the layer
##     rain stops              (nothing)           <- the forest never comes back
##
## 🔑 AND IT STAYS SILENT. WeatherSystem.process() only calls _apply_condition when the condition
## CHANGES, so nothing re-asserts; the bed returns only if the player happens to cross a zone
## boundary, which is the one other thing that writes this layer (OverworldScene:900).
##
## ⛔ THE HOSTS DO NOT SHARE A BASE CLASS -- OverworldScene, the four per-world overworlds and
## BaseVillage are each `extends Node2D` -- so the seam is duck-typed: WeatherSystem asks its host
## to restore the place bed and falls back to stop_ambient() when the host cannot. That fallback is
## pinned below, because it is what keeps a host that does not implement it behaving as before.

const WS := preload("res://src/exploration/WeatherSystem.gd")
const OVERWORLD := preload("res://src/exploration/OverworldScene.gd")
const VILLAGE := preload("res://src/maps/villages/BaseVillage.gd")

const PLACE_BED := "ambient_forest"


## A host that restores a known bed, standing in for OverworldScene/BaseVillage. The arm below
## proves the REAL hosts carry this method, so this double is not testing a fiction.
class StubHost extends Node2D:
	var restored: int = 0
	func restore_place_ambient() -> void:
		restored += 1
		SoundManager.play_ambient("ambient_forest")


class DeafHost extends Node2D:
	pass


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	GameState.set_weather("clear")


func after_each() -> void:
	SoundManager.stop_ambient()
	GameState.set_weather("clear")


func _weather_on(host: Node2D, world: String) -> Node:
	var player := Node2D.new()
	host.add_child(player)
	var w = WS.new()
	host.add_child(w)
	w.setup(host, player, world)
	return w


func test_the_place_bed_returns_when_the_rain_stops() -> void:
	var host := StubHost.new()
	add_child_autofree(host)
	var w := _weather_on(host, "medieval")

	GameState.set_weather("clear"); w.process(0.016)
	SoundManager.play_ambient(PLACE_BED)
	assert_true(SoundManager._ambient_player.playing, "CONTROL: the place bed is playing before the rain")

	GameState.set_weather("rain"); w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_rain",
		"CONTROL: weather must take the layer while it is on")

	GameState.set_weather("clear"); w.process(0.016)
	assert_true(SoundManager._ambient_player.playing,
		"the overworld went silent when the rain stopped -- medieval has no fair-weather bed, so the clear branch stopped the ambient and nothing re-asserts")
	assert_eq(SoundManager._current_ambient_key, PLACE_BED,
		"and the bed that came back must be the PLACE bed, not something else")


func test_the_real_hosts_carry_the_method_the_double_stands_in_for() -> void:
	## ⛔ WITHOUT THIS THE ARM ABOVE TESTS MY OWN STUB. Both real hosts run WeatherSystem
	## (OverworldScene:125, BaseVillage:664) and both own a place bed.
	var ow = OVERWORLD.new()
	var v = VILLAGE.new()
	assert_true(ow.has_method("restore_place_ambient"),
		"OverworldScene cannot restore its zone bed, so W1's overworld still goes silent")
	assert_true(v.has_method("restore_place_ambient"),
		"BaseVillage cannot restore its village bed, so a medieval village still goes silent")
	ow.free()
	v.free()


func test_a_world_with_a_fair_weather_bed_still_plays_it() -> void:
	## ⛔ THE DANGEROUS DIRECTION. steampunk names weather_steam for clear; restoring the PLACE bed
	## there would delete a deliberate per-world atmosphere.
	var host := StubHost.new()
	add_child_autofree(host)
	var w := _weather_on(host, "steampunk")

	GameState.set_weather("rain"); w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_rain", "CONTROL: rain is on")
	GameState.set_weather("clear"); w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_steam",
		"steampunk's fair-weather bed was replaced by the place bed -- the per-world atmosphere is gone")
	assert_eq(host.restored, 0, "and the host must not have been asked to restore at all")


func test_weather_still_wins_the_layer_while_it_is_on() -> void:
	var host := StubHost.new()
	add_child_autofree(host)
	var w := _weather_on(host, "medieval")

	SoundManager.play_ambient(PLACE_BED)
	GameState.set_weather("storm"); w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_storm_bed",
		"the place bed outranked active weather -- the precedence has inverted")


func test_a_host_that_cannot_restore_still_falls_back_to_silence() -> void:
	## The duck-typed seam must not break a host that does not implement it.
	var host := DeafHost.new()
	add_child_autofree(host)
	var w := _weather_on(host, "medieval")

	SoundManager.play_ambient(PLACE_BED)
	GameState.set_weather("clear"); w.process(0.016)
	assert_false(SoundManager._ambient_player.playing,
		"a host with no restore hook must still end at silence, exactly as before")


## ⛔ THE MIRROR, and the reason precedence needs BOTH directions. The fix above defines what
## happens when weather ENDS; this defines what happens when the PLACE changes while weather is on.
## Measured on the shipped code: rain playing, cross a zone boundary, and the rain is replaced by
## the new zone's bed while rain is still falling on screen -- and nothing re-asserts until the
## weather next changes, which is a 60-120 s timer.
##
## `_update_zone_ambient` lives only in OverworldScene (medieval); the four per-world overworlds
## are separate classes with no zone router. Medieval is also the one world whose CLEAR state owns
## no bed, so in clear weather the router behaves exactly as it always did -- the arm below pins
## that, because a deferral one notch too broad would freeze the zone beds entirely.
func _overworld() -> Node:
	var ow = OVERWORLD.new()
	add_child_autofree(ow)
	await get_tree().process_frame
	return ow


func test_a_zone_change_during_rain_keeps_the_rain() -> void:
	var ow: Node = await _overworld()
	assert_not_null(ow.get("_weather"), "CONTROL: the overworld built a weather system")

	GameState.set_weather("rain"); ow._weather.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_rain", "CONTROL: rain owns the layer")

	ow._update_zone_ambient("forest")
	assert_eq(SoundManager._current_ambient_key, "weather_rain",
		"crossing a zone boundary replaced the rain with the zone bed, while rain was still falling")


func test_when_the_rain_stops_the_bed_is_the_zone_you_are_in_now() -> void:
	var ow: Node = await _overworld()
	GameState.set_weather("rain"); ow._weather.process(0.016)
	ow._current_zone = "forest"
	ow._update_zone_ambient("forest")
	assert_eq(SoundManager._current_ambient_key, "weather_rain", "CONTROL: weather still holds it")

	GameState.set_weather("clear"); ow._weather.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "ambient_forest",
		"the bed that came back must be the zone the player is in NOW, not the one they left")


func test_a_zone_change_in_clear_weather_still_updates_the_bed() -> void:
	## ⛔ THE DANGEROUS DIRECTION: a deferral that fires in clear weather would freeze the zone beds.
	var ow: Node = await _overworld()
	GameState.set_weather("clear"); ow._weather.process(0.016)
	assert_false(ow._weather.owns_ambient(), "CONTROL: medieval clear owns no bed, so the router must run")

	ow._update_zone_ambient("coast")
	assert_eq(SoundManager._current_ambient_key, "ambient_coast",
		"the zone router stopped working in clear weather -- the deferral is too broad")
