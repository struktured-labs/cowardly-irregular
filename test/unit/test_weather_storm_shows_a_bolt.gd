extends GutTest

## A battle in "storm" weather pulsed the overlay tint and drew NO bolt, so a storm was
## indistinguishable from heavy rain. Reuses the ability storm's _storm_bolt builder.

const SRC := "res://src/battle/BattleScene.gd"

func _src() -> String:
	var s := FileAccess.get_file_as_string(SRC)
	assert_gt(s.length(), 1000, "CONTROL: read BattleScene")
	return s

func _weather_block() -> String:
	var s := _src()
	var i := s.find("func _process_weather_layer(")
	assert_gt(i, -1, "CONTROL: located the weather layer")
	var j := s.find("\nfunc ", i + 10)
	assert_gt(j, i, "CONTROL: found the end of the function")
	return s.substr(i, j - i)

func test_the_weather_storm_actually_draws_a_bolt() -> void:
	assert_true(_weather_block().contains("_storm_bolt("),
		"storm weather must draw a real bolt — a tint pulse alone reads as rain")

func test_the_weather_bolt_is_gated_on_flashes_suppressed() -> void:
	var b := _weather_block()
	assert_true(b.contains("_flashes_suppressed()"),
		"CONTROL: the accessibility gate is present in this function")
	var gate := b.find("_flashes_suppressed()")
	var bolt := b.find("_storm_bolt(")
	assert_gt(bolt, gate,
		"the bolt must sit INSIDE the not-suppressed branch — reduce_flashes has to win")

func test_the_weather_bolt_is_tier_gated() -> void:
	var b := _weather_block()
	assert_true(b.contains("_tier() == BattleJuice.Tier.FULL"),
		"ambient bolts must be FULL-tier only, like every other battle flourish")

func test_ambient_weather_never_punches_the_screen() -> void:
	## The ability storm adds trauma and a punch_zoom per strike. Ambient weather fires on a
	## 4-12s timer with no player action behind it; shaking the screen there would read as a bug.
	var b := _weather_block()
	assert_false(b.contains("add_trauma("), "weather must not shake the screen")
	assert_false(b.contains("punch_zoom("), "weather must not zoom the camera")

func test_the_ability_storm_still_does_punch_the_screen() -> void:
	## Guards the pair: the contrast above is the point, so it must be checked from both ends.
	var s := _src()
	var i := s.find("func _full_render_storm(")
	assert_gt(i, -1, "CONTROL: located the ability storm")
	var body := s.substr(i, 1800)
	assert_true(body.contains("add_trauma("), "a cast storm SHOULD hit hard")
	assert_true(body.contains("punch_zoom("), "a cast storm SHOULD punch")

func test_the_shared_builder_is_not_duplicated() -> void:
	var s := _src()
	assert_eq(s.count("func _storm_bolt("), 1,
		"one bolt builder — a second copy is how the weather bolt and the cast bolt drift apart")
