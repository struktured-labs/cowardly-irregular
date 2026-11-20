extends GutTest

## A refused request reached the player as a bare "HTTP 404" or "HTTP 429": Test Connection could not tell a mistyped model
## from a spent quota. The status now carries the server's own message, bounded, and never a credential.

const KEY := "sk-test-0123456789abcdefghij"
const OPENAI_404 := '{"error": {"message": "The model `gpt-5x` does not exist or you do not have access to it.", "type": "invalid_request_error", "code": "model_not_found"}}'
const OPENAI_429 := '{"error": {"message": "You exceeded your current quota, please check your plan and billing details.", "type": "insufficient_quota"}}'
const OLLAMA_404 := '{"error": "model \'llama9\' not found, try pulling it first"}'
const DETAIL_422 := '{"detail": "field required: messages"}'
const OPENAI_401 := '{"error": {"message": "Incorrect API key provided: sk-test-****ghij. You can find your API key at the dashboard."}}'

var _b: HTTPBackend = null


func before_each() -> void:
	_b = HTTPBackend.new()
	_b.base_url = "http://127.0.0.1:1"
	_b.api_format = "openai"
	_b.model = "m"
	_b.api_key = KEY
	autofree(_b)


func _err(code: int, body: String) -> String:
	var got: Array = _b._extract_text(code, body.to_utf8_buffer())
	return str(got[2]) if got.size() >= 3 else "<no error slot>"


func test_a_mistyped_model_and_a_spent_quota_read_differently() -> void:
	assert_eq(_err(404, OPENAI_404), "HTTP 404: The model `gpt-5x` does not exist or you do not have access to it.")
	assert_eq(_err(429, OPENAI_429), "HTTP 429: You exceeded your current quota, please check your plan and billing details.")


func test_every_error_shape_a_server_sends_is_read() -> void:
	assert_eq(_err(404, OLLAMA_404), "HTTP 404: model 'llama9' not found, try pulling it first", "Ollama sends the message as the error itself")
	assert_eq(_err(422, DETAIL_422), "HTTP 422: field required: messages", "a bare detail is read too")
	assert_eq(_err(500, '{"message": "upstream\\n  timed out\\tagain"}'), "HTTP 500: upstream timed out again", "and a message with line breaks is one line")


func test_a_key_rejection_carries_none_of_the_servers_words() -> void:
	assert_eq(_err(401, OPENAI_401), "HTTP 401", "a 401 body quotes part of the key, so none of it is shown")
	assert_eq(_err(403, OPENAI_401), "HTTP 403")
	assert_string_contains(_err(400, OPENAI_401), "Incorrect API key", "CONTROL: the same body on another status IS read, so the status is what silences it")


func test_a_server_that_echoes_the_key_does_not_put_it_on_screen() -> void:
	var echoed: String = _err(400, '{"error": {"message": "bad header Authorization: Bearer %s for model m"}}' % KEY)
	assert_eq(echoed, "HTTP 400: bad header Authorization: Bearer [key] for model m")
	assert_false(echoed.contains(KEY), "the key itself is never in the error")
	_b.api_key = ""
	assert_string_contains(_err(400, '{"error": {"message": "no key for model m"}}'), "no key for model m", "CONTROL: with no key set, nothing is struck from the message")


func test_a_long_message_is_cut_to_a_line() -> void:
	var long_err: String = _err(400, '{"error": {"message": "%s"}}' % "x".repeat(900))
	assert_eq(long_err.length(), "HTTP 400: ".length() + HTTPBackend.MAX_REASON_CHARS, "the status plus at most MAX_REASON_CHARS of the server's text")
	var late: String = _err(400, '{"error": {"message": "%s%s"}}' % ["y".repeat(HTTPBackend.MAX_REASON_CHARS - 10), KEY])
	assert_false(late.contains(KEY.left(8)), "a key that straddles the cut is struck before the cut, not half shown: %s" % late.right(16))


func test_control_a_body_that_is_not_a_json_error_adds_nothing() -> void:
	assert_eq(_err(502, "<html><body>Bad Gateway</body></html>"), "HTTP 502", "CONTROL: a proxy's page is not put on screen")
	assert_eq(_err(500, ""), "HTTP 500", "CONTROL: an empty body")
	assert_eq(_err(400, '{"error": {"code": 7}}'), "HTTP 400", "CONTROL: an error with no message")
	assert_eq(_err(400, '{"error": '), "HTTP 400", "CONTROL: a cut-off body")
	assert_eq(_err(400, '[1, 2]'), "HTTP 400", "CONTROL: a JSON body that is not an object")


func test_control_a_reply_that_succeeds_is_read_as_before() -> void:
	var got: Array = _b._extract_text(200, '{"choices": [{"message": {"content": "Kneel."}}]}'.to_utf8_buffer())
	assert_eq([got[0], got[1], got[2]], [true, "Kneel.", ""], "CONTROL: a 2xx never reaches the reason")
