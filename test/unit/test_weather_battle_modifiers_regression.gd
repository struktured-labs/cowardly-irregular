extends GutTest

## Weather v2: battle obeys the weather. Functional value checks + a seam pin for each
## consumer, because a correct table nobody consults is decorative (goblin-music class).

var _saved_condition: String = ""
var _saved_timer: float = 0.0
var _saved_world_pin: int = 0


func before_each() -> void:
	_saved_condition = GameState.weather_condition
	_saved_timer = GameState.weather_timer
	_saved_world_pin = GameState._weather_world


func after_each() -> void:
	GameState.weather_condition = _saved_condition
	GameState.weather_timer = _saved_timer
	GameState._weather_world = _saved_world_pin


func test_storm_boosts_lightning_only() -> void:
	GameState.set_weather("storm", 999.0)
	assert_almost_eq(BattleManager.get_weather_damage_modifier("lightning"), 1.25, 0.001,
		"storm must boost lightning")
	assert_almost_eq(BattleManager.get_weather_damage_modifier("fire"), 1.0, 0.001,
		"storm must leave fire alone")


func test_rain_dampens_fire_and_feeds_water_ice() -> void:
	GameState.set_weather("rain", 999.0)
	assert_almost_eq(BattleManager.get_weather_damage_modifier("fire"), 0.75, 0.001, "rain dampens fire")
	assert_almost_eq(BattleManager.get_weather_damage_modifier("water"), 1.15, 0.001, "rain feeds water")
	assert_almost_eq(BattleManager.get_weather_damage_modifier("ice"), 1.15, 0.001, "rain feeds ice")
	GameState.set_weather("drizzle", 999.0)
	assert_almost_eq(BattleManager.get_weather_damage_modifier("fire"), 0.75, 0.001,
		"drizzle carries the same elemental profile")


func test_clear_is_identity_for_every_element() -> void:
	GameState.set_weather("clear", 999.0)
	for element in ["fire", "ice", "lightning", "water", "dark", "holy", ""]:
		assert_almost_eq(BattleManager.get_weather_damage_modifier(element), 1.0, 0.001,
			"clear weather must not touch %s" % ("(empty)" if element == "" else element))


func test_fog_and_smog_thicken_the_miss_rate() -> void:
	GameState.set_weather("fog", 999.0)
	assert_almost_eq(BattleManager.get_weather_miss_bonus(), 0.15, 0.001, "fog adds miss chance")
	GameState.set_weather("smog", 999.0)
	assert_almost_eq(BattleManager.get_weather_miss_bonus(), 0.15, 0.001, "smog behaves as fog")
	GameState.set_weather("storm", 999.0)
	assert_almost_eq(BattleManager.get_weather_miss_bonus(), 0.0, 0.001, "storm does not affect accuracy")


func test_fog_raises_encounter_pressure() -> void:
	GameState.set_weather("fog", 999.0)
	assert_almost_eq(EncounterSystem.get_weather_encounter_multiplier(), 1.5, 0.001,
		"fog must raise the per-step encounter chance")
	GameState.set_weather("clear", 999.0)
	assert_almost_eq(EncounterSystem.get_weather_encounter_multiplier(), 1.0, 0.001,
		"clear must be identity")


func test_the_damage_seam_actually_consults_weather() -> void:
	# The modifier lives beside terrain_mod in the elemental damage path. Match the CODE.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_gt(src.length(), 5000, "CONTROL: read a real file")
	var i: int = src.find("terrain_mod = get_terrain_damage_modifier(element)")
	assert_gt(i, -1, "CONTROL: the terrain seam must exist — it anchors the weather seam")
	var window: String = src.substr(i, 220)
	assert_true(window.contains("get_weather_damage_modifier(element)"),
		"the elemental damage path must multiply in the weather modifier, or the table is decorative")


func test_the_miss_seam_actually_consults_weather() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i: int = src.find("var base_miss_rate = 0.10")
	assert_gt(i, -1, "CONTROL: the miss check must exist")
	var window: String = src.substr(i, 400)
	assert_true(window.contains("get_weather_miss_bonus()"),
		"the miss check must add the weather bonus, or fog is decorative")


func test_the_encounter_seam_actually_consults_weather() -> void:
	var src := FileAccess.get_file_as_string("res://src/encounters/EncounterSystem.gd")
	var i: int = src.find("var chance = encounter_rate * encounter_rate_modifier")
	assert_gt(i, -1, "CONTROL: the encounter roll must exist")
	var window: String = src.substr(i, 300)
	assert_true(window.contains("get_weather_encounter_multiplier()"),
		"the encounter roll must multiply in the weather factor, or fog pressure is decorative")
