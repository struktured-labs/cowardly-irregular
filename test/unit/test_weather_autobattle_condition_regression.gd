extends GutTest

## Weather v2's point: scripts can SEE the weather (automation pillar). Pins the condition
## end-to-end: catalog, evaluation truth, decode-time validation, editor vocabulary sync.

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


func _combatant() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "WeatherTester"
	return c


func test_weather_is_in_the_condition_catalog() -> void:
	assert_true(AutobattleSystem.CONDITION_TYPES.has("weather"),
		"the grid editor's type picker renders from CONDITION_TYPES — absent means unpickable")
	assert_eq(str(AutobattleSystem.CONDITION_TYPES["weather"]), "Weather Is")


func test_condition_matches_the_live_weather() -> void:
	GameState.set_weather("storm", 999.0)
	var c := _combatant()
	assert_true(AutobattleSystem._evaluate_grid_condition(c, {"type": "weather", "weather": "storm"}),
		"storm rule must fire in a storm")
	assert_false(AutobattleSystem._evaluate_grid_condition(c, {"type": "weather", "weather": "rain"}),
		"rain rule must NOT fire in a storm")
	assert_false(AutobattleSystem._evaluate_grid_condition(c, {"type": "weather"}),
		"a value-less weather condition must never fire")
	c.free()


func test_validate_rule_rejects_a_made_up_condition() -> void:
	# The Rule Composer LLM can emit "midnight"-class values; decode must catch them
	# (same discipline as the is_night grammar ruling).
	var bad := {"conditions": [{"type": "weather", "weather": "midnight"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}
	var errors: Array[String] = AutobattleSystem.validate_rule(bad)
	assert_gt(errors.size(), 0, "an unknown weather value must fail validation")
	assert_true(str(errors[0]).contains("weather"), "and the error must name the field: %s" % str(errors))


func test_validate_rule_accepts_every_vocabulary_member() -> void:
	for condition in GameState.all_weather_conditions():
		var rule := {"conditions": [{"type": "weather", "weather": condition}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}
		assert_eq(AutobattleSystem.validate_rule(rule).size(), 0,
			"'%s' is in the vocabulary and must validate" % condition)


func test_editor_seed_and_cycling_stay_inside_the_vocabulary() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	assert_gt(src.length(), 5000, "CONTROL: read a real file")
	assert_true(src.contains('cond["weather"] = "rain"'),
		"type-change must seed a default so the condition is immediately evaluable")
	assert_true(GameState.all_weather_conditions().has("rain"),
		"and the seed must be a legal vocabulary member")
	assert_true(src.contains("GameState.all_weather_conditions()"),
		"value cycling must derive from the SAME vocabulary the validator uses — two lists drift")


func test_rules_with_weather_survive_the_share_roundtrip() -> void:
	# COWIR1: codes are grammar-validated at decode; a weather rule must come back intact —
	# a validator that never learned the new type would reject the whole code as {}.
	var char_id := "weather_share_probe"
	# Persistence OFF for the probe: set_character_script would otherwise write user:// — and
	# deploy suites run UNSANDBOXED against real player data (2026-09-06 leak).
	var saved_persist: bool = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	AutobattleSystem.set_character_script(char_id, {"rules": [{"enabled": true,
		"conditions": [{"type": "weather", "weather": "storm"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}]})
	var code: String = ScriptShareManager.encode_share_code(char_id)
	var decoded: Dictionary = ScriptShareManager.decode_share_code(code)
	AutobattleSystem.character_profiles.erase(char_id)
	AutobattleSystem.autobattle_enabled.erase(char_id)
	AutobattleSystem._test_disable_persistence = saved_persist
	assert_true(code.begins_with("COWIR1:"), "CONTROL: encode must produce a share code")
	assert_false(decoded.is_empty(), "decode must ACCEPT the weather rule — {} means the grammar rejected it")
	var rules: Array = (decoded.get("script", {}) as Dictionary).get("rules", [])
	assert_eq(rules.size(), 1, "the rule must survive decode: %s" % str(decoded))
	var cond: Dictionary = rules[0]["conditions"][0]
	assert_eq(str(cond.get("type", "")), "weather")
	assert_eq(str(cond.get("weather", "")), "storm")
