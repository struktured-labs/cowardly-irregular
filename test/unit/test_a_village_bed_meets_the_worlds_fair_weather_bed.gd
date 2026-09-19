extends GutTest

## A W2-W5 village plays its own ambient bed for exactly ONE FRAME.
##
## BaseVillage._ready() starts the village bed (:100), then _process runs the weather (:672).
## The first weather frame always calls _apply_condition -- _rendered_condition starts "" and the
## live condition is "clear" -- and for any world WORLD_CLEAR_AMBIENTS names, that branch plays the
## world's fair-weather bed OVER the village's. Measured:
##
##     medieval village    ambient_village -> ambient_village    <- handback, correct
##     suburban village    ambient_village -> weather_sunny      <- the village bed is gone
##
## 🔑 AND IT CANNOT COME BACK. owns_ambient() is true for those four worlds whenever the weather is
## clear, so BaseVillage.restore_place_ambient() (:709) is UNREACHABLE there -- the `_:` arm that
## calls it never runs. A rain shower does not help: clearing restores weather_sunny, not the village.
##
## ⛔ THIS FILE CHANGES NOTHING. The rule it pins is deliberate and already guarded the other way by
## test_a_world_with_a_fair_weather_bed_still_plays_it, whose stated reason is per-world OVERWORLD
## atmosphere. That reason does not obviously transfer to a village, and villages did not have an
## ambient layer when it was written. Whether a village bed should outrank a world's fair-weather
## bed is struktured's call; this pins what ships today so the answer is chosen, not inherited.

const WS := preload("res://src/exploration/WeatherSystem.gd")
const VILLAGE := preload("res://src/maps/villages/BaseVillage.gd")

const VILLAGE_BED := "ambient_village"


## Stands in for BaseVillage: owns a bed, starts it up front, restores it on request.
class VillageHost extends Node2D:
	var restored: int = 0
	func restore_place_ambient() -> void:
		restored += 1
		SoundManager.play_ambient("ambient_village")


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	GameState.set_weather("clear")


func after_each() -> void:
	SoundManager.stop_ambient()
	GameState.set_weather("clear")


func _village_in(world: String) -> Array:
	var host := VillageHost.new()
	add_child_autofree(host)
	var player := Node2D.new()
	host.add_child(player)
	var w = WS.new()
	host.add_child(w)
	w.setup(host, player, world)
	SoundManager.play_ambient(VILLAGE_BED)
	return [host, w]


func test_a_medieval_village_keeps_the_bed_it_started() -> void:
	var pair := _village_in("medieval")
	var w = pair[1]
	assert_eq(SoundManager._current_ambient_key, VILLAGE_BED, "CONTROL: the village bed is playing before weather runs")
	w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, VILLAGE_BED,
		"medieval names no fair-weather bed, so the first weather frame must hand the layer back to the village")
	assert_gt(pair[0].restored, 0, "and the handback must have gone through the host, not merely left the bed alone")


func test_a_suburban_village_loses_the_bed_it_started() -> void:
	var pair := _village_in("suburban")
	var w = pair[1]
	assert_eq(SoundManager._current_ambient_key, VILLAGE_BED, "CONTROL: the village bed is playing before weather runs")
	w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_sunny",
		"the first weather frame replaced the village bed with the world's fair-weather bed")
	assert_eq(pair[0].restored, 0, "and the village was never asked to restore -- its bed is simply gone")


func test_the_suburban_village_bed_never_returns() -> void:
	## The stomp is permanent, which is what makes it worth a ruling rather than a shrug.
	var pair := _village_in("suburban")
	var w = pair[1]
	w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_sunny", "CONTROL: the village bed is already gone")

	for _i in range(5):
		w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_sunny", "further clear frames do not restore it")

	GameState.set_weather("rain"); w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_rain", "CONTROL: real weather takes the layer")
	GameState.set_weather("clear"); w.process(0.016)
	assert_eq(SoundManager._current_ambient_key, "weather_sunny",
		"clearing restores the WORLD bed, so a shower does not give the village its bed back either")
	assert_eq(pair[0].restored, 0, "BaseVillage.restore_place_ambient is unreachable in this world -- dead code for W2-W5. NOT the same-named OverworldScene.restore_place_ambient, which WeatherSystem reaches duck-typed via has_method")


func test_the_affected_worlds_are_exactly_the_ones_the_table_names() -> void:
	## DERIVED, not enumerated: the set that loses its village bed must equal WORLD_CLEAR_AMBIENTS'
	## keys. A world added to or removed from that table changes this behaviour, and this reds.
	var named: Array = WS.WORLD_CLEAR_AMBIENTS.keys()
	var overridden: Array = []
	for world in WS.WORLD_IDS.values():
		SoundManager.stop_ambient()
		var pair := _village_in(str(world))
		pair[1].process(0.016)
		if pair[0].restored == 0 and SoundManager._current_ambient_key != VILLAGE_BED:
			overridden.append(str(world))
	named.sort()
	overridden.sort()
	assert_gt(named.size(), 0, "CONTROL: the table names at least one fair-weather world")
	assert_eq(overridden, named,
		"the worlds whose villages lose their bed (%s) must be exactly the worlds WORLD_CLEAR_AMBIENTS names (%s)" % [overridden, named])


func test_the_real_village_has_the_shape_these_arms_assume() -> void:
	## ⛔ WITHOUT THIS EVERY ARM ABOVE IS ABOUT MY OWN STUB. Source-derived from BaseVillage.
	var src: String = FileAccess.get_file_as_string("res://src/maps/villages/BaseVillage.gd")
	var ready_idx: int = src.find("func _ready")
	var ready_body: String = src.substr(ready_idx, src.find("\nfunc ", ready_idx + 1) - ready_idx)
	assert_true(ready_body.contains("play_ambient"),
		"BaseVillage._ready must start a village bed, or there is nothing for weather to overwrite")
	var proc_idx: int = src.find("func _process")
	var proc_body: String = src.substr(proc_idx, src.find("\nfunc ", proc_idx + 1) - proc_idx)
	assert_true(proc_body.contains("_weather.process"),
		"BaseVillage._process must drive the weather, or the overwrite never happens")
	var v = VILLAGE.new()
	assert_true(v.has_method("restore_place_ambient"),
		"BaseVillage must carry the handback hook the medieval arm exercises")
	assert_true(v.has_method("_get_ambient_key"),
		"and the village bed must come from a real key source, not a literal in this file")
	v.free()
