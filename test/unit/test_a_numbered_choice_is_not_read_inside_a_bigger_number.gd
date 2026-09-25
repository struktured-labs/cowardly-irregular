extends GutTest

## choose()'s whole-token match counted only letters as word characters, so "17" matched options "1" and "7".


func _labels(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, n + 1):
		out.append(str(i))
	return out


func test_a_prose_reply_picks_the_whole_number() -> void:
	assert_eq(LLMService._guard_choice("I pick 17.", _labels(20), "1"), "17",
		"'17' must not also match '1' and '7' and fall back")


func test_a_number_past_the_list_is_not_read_as_its_first_digit() -> void:
	assert_eq(LLMService._guard_choice("20", _labels(15), "1"), "1",
		"with 15 options, '20' is invalid and must fall back, not become option 2")


func test_json_and_bare_replies_still_work() -> void:
	assert_eq(LLMService._guard_choice("12", _labels(20), "1"), "12")
	assert_eq(LLMService._guard_choice('{"choice": "10"}', _labels(20), "1"), "10")


func test_word_options_are_unaffected() -> void:
	var opts: Array[String] = ["attack", "defend"]
	assert_eq(LLMService._guard_choice("I will attack now", opts, "defend"), "attack")
