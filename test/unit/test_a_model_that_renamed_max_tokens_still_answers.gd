extends GutTest

## OpenAI's newer models 400 on max_tokens ("Use 'max_completion_tokens' instead") and on any set temperature. A BYOK key
## pointed at one failed every dialogue, strategy and Test Connection call with a bare "HTTP 400".

const TOKENS_400 := '{"error": {"message": "Unsupported parameter: \'max_tokens\' is not supported with this model. Use \'max_completion_tokens\' instead.", "param": "max_tokens"}}'
const TEMP_400 := '{"error": {"message": "Unsupported value: \'temperature\' does not support 0.7 with this model. Only the default (1) value is supported.", "param": "temperature"}}'
const TOO_LARGE_400 := '{"error": {"message": "max_tokens is too large: 64. This model supports at most 32."}}'

var _server: TCPServer
var _peers: Array = []
var _mode: String = "new"
var _bodies: Array = []


func after_each() -> void:
	_mode = "new"
	_bodies.clear()
	for p in _peers:
		(p["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()


func _respond(code: int, body: String) -> PackedByteArray:
	var b: PackedByteArray = body.to_utf8_buffer()
	var status: String = "200 OK" if code == 200 else "400 Bad Request"
	var out: PackedByteArray = ("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % [status, b.size()]).to_ascii_buffer()
	out.append_array(b)
	return out


func _answer(head: String, request: String) -> PackedByteArray:
	if not head.begins_with("POST"):
		return _respond(200, '{"data": [{"id": "m"}]}')
	var parsed = JSON.parse_string(request)
	var sent: Dictionary = parsed if parsed is Dictionary else {}
	_bodies.append(sent)
	if _mode == "too_large":
		return _respond(400, TOO_LARGE_400)
	if _mode == "new" and sent.has("max_tokens"):
		return _respond(400, TOKENS_400)
	if _mode == "new" and sent.has("temperature"):
		return _respond(400, TEMP_400)
	return _respond(200, '{"choices": [{"message": {"content": "Kneel."}}], "response": "Kneel."}')


## One poll of a tiny HTTP/1.1 server; replies are small, so a single put_data never waits on this thread's reader.
func _serve() -> void:
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "done": false})
	for p in _peers:
		if p["done"]:
			continue
		var peer: StreamPeerTCP = p["peer"]
		peer.poll()
		var n: int = peer.get_available_bytes()
		var buf: PackedByteArray = p["buf"]
		if n > 0:
			buf.append_array(peer.get_data(n)[1])
			p["buf"] = buf
		var text: String = buf.get_string_from_utf8()
		var end: int = text.find("\r\n\r\n")
		if end == -1:
			continue
		var length := 0
		for line in text.substr(0, end).split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.get_slice(":", 1).strip_edges())
		if buf.size() < end + 4 + length:
			continue
		peer.put_data(_answer(text.substr(0, end), text.substr(end + 4)))
		p["done"] = true


func _backend(format: String = "openai") -> HTTPBackend:
	_server = TCPServer.new()
	assert_eq(_server.listen(0, "127.0.0.1"), OK, "a local port to serve on")
	var b := HTTPBackend.new()
	b.base_url = "http://127.0.0.1:%d" % _server.get_local_port()
	b.api_format = format
	b.model = "m"
	add_child_autofree(b)
	var t0 := Time.get_ticks_msec()
	while not b._first_probe_done and Time.get_ticks_msec() - t0 < 5000:
		_serve()
		await get_tree().process_frame
	return b


## Submits one request and waits for it; returns {ok, text, err}, or {} if it never finished.
func _ask(b: HTTPBackend, id: String) -> Dictionary:
	var got := {}
	var on_done := func(rid, ok, text, err): got[rid] = {"ok": ok, "text": text, "err": err}
	b.request_finished.connect(on_done)
	b.submit(id, "Gloat.", {"max_tokens": 64, "temperature": 0.7})
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 10000:
		_serve()
		await get_tree().process_frame
	b.request_finished.disconnect(on_done)
	return got.get(id, {})


func test_a_model_that_refuses_both_params_still_answers() -> void:
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, "r1")
	assert_true(bool(got.get("ok", false)), "the request answers, err=%s" % str(got.get("err", "")))
	assert_eq(str(got.get("text", "")), "Kneel.")
	assert_eq(_bodies.size(), 3, "one try as written, one with the token cap renamed, one with no temperature")
	var last: Dictionary = _bodies.back() if not _bodies.is_empty() else {}
	assert_eq(int(last.get("max_completion_tokens", 0)), 64, "the caller's cap travels under the new name")
	assert_false(last.has("max_tokens") or last.has("temperature"), "and neither refused param is sent: %s" % str(last.keys()))


func test_the_refusals_are_remembered_for_that_model() -> void:
	var b: HTTPBackend = await _backend()
	await _ask(b, "r1")
	var got: Dictionary = await _ask(b, "r2")
	assert_true(bool(got.get("ok", false)), "the next request answers")
	assert_eq(_bodies.size(), 4, "and goes straight out in the accepted shape: no second refused round trips")


func test_control_another_model_on_that_server_starts_as_written() -> void:
	var b: HTTPBackend = await _backend()
	await _ask(b, "r1")
	_mode = "lenient"
	b.model = "older"
	var got: Dictionary = await _ask(b, "r2")
	assert_true(bool(got.get("ok", false)), "CONTROL: the other model answers")
	var last: Dictionary = _bodies.back() if not _bodies.is_empty() else {}
	assert_true(last.has("max_tokens") and last.has("temperature"), "CONTROL: one model's refusal does not rewrite another's requests: %s" % str(last.keys()))


func test_control_a_server_that_accepts_both_keeps_getting_them() -> void:
	_mode = "lenient"
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, "r1")
	assert_true(bool(got.get("ok", false)), "CONTROL: a lenient server answers")
	assert_eq(_bodies.size(), 1, "CONTROL: in one request")
	var only: Dictionary = _bodies.back() if not _bodies.is_empty() else {}
	assert_eq([int(only.get("max_tokens", 0)), only.has("temperature"), only.has("max_completion_tokens")], [64, true, false], "CONTROL: with the body as written")


func test_control_a_400_that_offers_no_new_name_is_not_retried() -> void:
	_mode = "too_large"
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, "r1")
	assert_false(bool(got.get("ok", true)), "CONTROL: a cap the model cannot meet still fails")
	assert_eq(str(got.get("err", "")), "HTTP 400")
	assert_eq(_bodies.size(), 1, "CONTROL: and is sent once, since renaming the param would not fix it")


func test_control_an_ollama_request_is_never_rewritten() -> void:
	_mode = "too_large"
	var b: HTTPBackend = await _backend("ollama")
	b._param_refused[b._json_key()] = {"max_tokens": true, "temperature": true}
	var got: Dictionary = await _ask(b, "r1")
	assert_false(bool(got.get("ok", true)), "CONTROL: the 400 reaches the caller")
	assert_eq(_bodies.size(), 1, "CONTROL: sent once")
	var only: Dictionary = _bodies.back() if not _bodies.is_empty() else {}
	assert_eq(int((only.get("options", {}) as Dictionary).get("num_predict", 0)), 64, "CONTROL: Ollama's own cap and shape are untouched")
