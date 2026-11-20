extends GutTest

## A reply's content went through str(): a reasoning model out of tokens sends content null and the player read "<null>";
## a server that sends content as an array of parts had the array printed. content_text reads both as speech.


## Unparented: _ready() fires a live network probe, which a test must not do.
func _backend(fmt: String) -> HTTPBackend:
	var be := HTTPBackend.new()
	autofree(be)
	be.base_url = "http://127.0.0.1:9"
	be.model = "m"
	be.api_format = fmt
	return be


func _read(fmt: String, reply: Dictionary) -> Array:
	return _backend(fmt)._extract_text(200, JSON.stringify(reply).to_utf8_buffer())


func test_a_null_content_fails_instead_of_saying_null() -> void:
	var res: Array = _read("openai", {"choices": [{"message": {"role": "assistant", "content": null}, "finish_reason": "stop"}]})
	assert_eq(str(res[1]), "", "the player never reads <null>")
	assert_false(bool(res[0]), "a reply with no speech is a failure, so the caller's fallback speaks")


func test_content_parts_are_read_as_their_text() -> void:
	var res: Array = _read("openai", {"choices": [{"message": {"content": [{"type": "text", "text": "Kneel, "}, {"type": "text", "text": "heroes."}]}}]})
	assert_true(bool(res[0]), "a parts array is speech: %s" % str(res[2]))
	assert_eq(str(res[1]), "Kneel, heroes.", "joined text, not the array printed")


func test_a_model_that_ran_out_while_reasoning_says_so() -> void:
	var res: Array = _read("openai", {"choices": [{"message": {"content": null, "reasoning_content": "Let me think about"}, "finish_reason": "length"}]})
	assert_false(bool(res[0]))
	assert_string_contains(str(res[2]), "ran out of tokens while still reasoning", "Test Connection names the cause the player can fix")


func test_a_refusal_is_named() -> void:
	var res: Array = _read("openai", {"choices": [{"message": {"content": null, "refusal": "I can't help with that."}}]})
	assert_false(bool(res[0]))
	assert_string_contains(str(res[2]), "the model refused: I can't help with that.")


func test_an_ollama_null_response_is_not_said() -> void:
	var res: Array = _read("ollama", {"response": null, "done": true})
	assert_eq(str(res[1]), "", "the Ollama arm reads its reply the same way")


func test_control_a_plain_reply_is_unchanged() -> void:
	var res: Array = _read("openai", {"choices": [{"message": {"content": "The crown stays mine."}, "finish_reason": "stop"}]})
	assert_eq(res, [true, "The crown stays mine.", ""], "CONTROL: ordinary content passes through untouched")
	assert_eq(_read("ollama", {"response": "Down you go."}), [true, "Down you go.", ""], "CONTROL: Ollama too")
	var bare: Array = _read("openai", {"choices": [{"message": {"content": ""}}]})
	assert_eq(bare, [false, "", "OpenAI response missing choices[0].message.content"], "CONTROL: an empty reply with no cause keeps its old error exactly")
