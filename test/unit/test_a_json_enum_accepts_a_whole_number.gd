extends GutTest

## The JSON guard's enum check was `val in spec`, and JSON parses every number as a float: `2.0 in [1, 2, 3]` is false
## in Godot 4, so a schema enum of whole numbers would refuse the model's correct `2` and hand back the fallback. Latent
## (every enum shipped today is strings); found in the float-membership sweep (controller 22016, ai 22032). The guard
## now matches a number by value and returns the AUTHORED member, so a consumer's `match` sees the int it wrote.

const LS := preload("res://src/llm/LLMService.gd")

var _svc = null


func before_each() -> void:
	_svc = LS.new()
	add_child_autofree(_svc)


func test_a_whole_number_enum_accepts_the_models_number() -> void:
	var parsed: Variant = JSON.parse_string('{"tier": 2}')
	assert_true(parsed is Dictionary and (parsed as Dictionary)["tier"] is float,
		"CONTROL: JSON hands the guard a float, which is the case this guards")
	assert_false((parsed as Dictionary)["tier"] in [1, 2, 3], "CONTROL: and plain membership refuses it")
	var got: Variant = _svc._guard_json('{"tier": 2}', {"tier": [1, 2, 3]}, "FALLBACK")
	assert_true(got is Dictionary, "THE DEFECT: a correct whole number fell back")
	if not (got is Dictionary):
		return
	assert_eq(typeof((got as Dictionary)["tier"]), TYPE_INT, "the caller receives the authored int, so a typed match holds")
	assert_eq(int((got as Dictionary)["tier"]), 2)


func test_a_number_outside_the_enum_still_falls_back() -> void:
	assert_eq(_svc._guard_json('{"tier": 4}', {"tier": [1, 2, 3]}, "FALLBACK"), "FALLBACK", "4 is not a member")
	assert_eq(_svc._guard_json('{"tier": 2.5}', {"tier": [1, 2, 3]}, "FALLBACK"), "FALLBACK", "nor is 2.5")
	assert_eq(_svc._guard_json('{"tier": "2"}', {"tier": [1, 2, 3]}, "FALLBACK"), "FALLBACK",
		"a string is not a number: only a numeric value is matched by value")


func test_a_string_enum_is_unchanged() -> void:
	var got: Variant = _svc._guard_json('{"verdict": "no_change"}', {"verdict": ["nudge_easier", "no_change"]}, "FALLBACK")
	assert_true(got is Dictionary, "a string member still passes")
	if got is Dictionary:
		assert_eq((got as Dictionary)["verdict"], "no_change")
	assert_eq(_svc._guard_json('{"verdict": "explode"}', {"verdict": ["no_change"]}, "FALLBACK"), "FALLBACK",
		"and a non-member string still falls back")
