extends GutTest

## complete_json validated a reply against its schema but never sent the schema, so a JSON feature asked for "some JSON"
## and hoped. The server now gets it (OpenAI-compatible json_schema, Ollama format), and a refusal steps down a rung.

const SCHEMA := {"intent": ["press", "hold"], "turns": "int", "note": "String"}
const REFUSE_400 := '{"error": {"message": "\'response_format.type\' json_schema is not supported"}}'

var _server: TCPServer
var _peers: Array = []
var _refuse: Array = []
var _bodies: Array = []
var _svc: Node
var _orig_backends: Array = []
var _orig_enabled: bool = false


func after_each() -> void:
	_refuse = []
	_bodies = []
	for p in _peers:
		(p["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()
	if _svc != null:
		_svc._backends.clear()
		for b in _orig_backends:
			_svc._backends.append(b)
		_svc.llm_enabled = _orig_enabled
		_svc = null


func _respond(code: int, body: String) -> PackedByteArray:
	var b: PackedByteArray = body.to_utf8_buffer()
	var status: String = "200 OK" if code == 200 else "400 Bad Request"
	var out: PackedByteArray = ("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % [status, b.size()]).to_ascii_buffer()
	out.append_array(b)
	return out


## The JSON format a request body carried: the response_format type, Ollama's format ("json" or "schema"), or "".
static func _carried(body: Dictionary) -> String:
	if body.has("response_format"):
		return str(body["response_format"].get("type", "?"))
	if body.has("format"):
		return "schema" if body["format"] is Dictionary else str(body["format"])
	return ""


func _answer(head: String, request: String) -> PackedByteArray:
	if not head.begins_with("POST"):
		return _respond(200, '{"data": [{"id": "m"}], "models": [{"name": "m"}]}')
	var body: Dictionary = JSON.parse_string(request)
	_bodies.append(body)
	if _carried(body) in _refuse:
		return _respond(400, REFUSE_400 if body.has("response_format") else '{"error": "invalid format"}')
	var reply := '{\\"intent\\": \\"hold\\", \\"turns\\": 2, \\"note\\": \\"brace\\"}'
	if head.contains("/api/generate"):
		return _respond(200, '{"response": "%s", "done": true}' % reply)
	return _respond(200, '{"choices": [{"message": {"content": "%s"}}]}' % reply)


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


func _backend(api_format: String = "openai") -> HTTPBackend:
	_server = TCPServer.new()
	assert_eq(_server.listen(0, "127.0.0.1"), OK, "a local port to serve on")
	var b := HTTPBackend.new()
	b.base_url = "http://127.0.0.1:%d" % _server.get_local_port()
	b.api_format = api_format
	b.model = "m"
	add_child_autofree(b)
	var t0 := Time.get_ticks_msec()
	while not b._first_probe_done and Time.get_ticks_msec() - t0 < 5000:
		_serve()
		await get_tree().process_frame
	return b


func _ask(b: HTTPBackend, schema: Dictionary) -> Dictionary:
	var got := {}
	var on_done := func(id, ok, text, err): got[id] = {"ok": ok, "text": text, "err": err}
	b.request_finished.connect(on_done)
	b.submit("j", "Pick an intent. Reply as JSON.", {"json_mode": true, "json_schema": schema})
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 10000:
		_serve()
		await get_tree().process_frame
	b.request_finished.disconnect(on_done)
	return got.get("j", {})


func _formats() -> Array:
	return _bodies.map(func(body): return _carried(body))


func test_the_guard_schema_becomes_a_json_schema() -> void:
	var js: Dictionary = LLMService.to_json_schema(SCHEMA)
	assert_eq(js["type"], "object")
	assert_eq(js["properties"]["intent"], {"enum": ["press", "hold"]}, "an enum is the guard's own list")
	assert_eq(js["properties"]["turns"], {"type": "integer"})
	assert_eq(js["properties"]["note"], {"type": "string"})
	assert_eq(Array(js["required"]), SCHEMA.keys(), "every guard key is required, as the guard requires it")
	assert_eq(LLMService.to_json_schema({"x": "Variant"})["properties"]["x"], {}, "CONTROL: an untyped key constrains nothing, as in the guard")


func test_an_openai_server_gets_the_schema_as_json_schema() -> void:
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, LLMService.to_json_schema(SCHEMA))
	assert_true(bool(got.get("ok", false)), "it answers, err=%s" % str(got.get("err", "")))
	assert_eq(_formats(), ["json_schema"])
	assert_eq(_bodies[0]["response_format"]["json_schema"]["schema"], LLMService.to_json_schema(SCHEMA), "the schema on the wire is the caller's")


func test_an_ollama_server_gets_the_schema_as_its_format() -> void:
	var b: HTTPBackend = await _backend("ollama")
	var got: Dictionary = await _ask(b, LLMService.to_json_schema(SCHEMA))
	assert_true(bool(got.get("ok", false)), "it answers, err=%s" % str(got.get("err", "")))
	assert_eq(_formats(), ["schema"])
	assert_eq(_bodies[0]["format"], LLMService.to_json_schema(SCHEMA))


func test_a_refused_schema_steps_down_to_json_mode_and_is_remembered() -> void:
	_refuse = ["json_schema"]
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, LLMService.to_json_schema(SCHEMA))
	assert_true(bool(got.get("ok", false)), "it still answers, err=%s" % str(got.get("err", "")))
	await _ask(b, LLMService.to_json_schema(SCHEMA))
	assert_eq(_formats(), ["json_schema", "json_object", "json_object"], "one refused try, then json_object, and the next request skips the refused rung")


func test_a_server_refusing_both_still_answers_from_the_prompt() -> void:
	_refuse = ["json_schema", "json_object"]
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, LLMService.to_json_schema(SCHEMA))
	assert_true(bool(got.get("ok", false)), "it answers with no response_format at all, err=%s" % str(got.get("err", "")))
	assert_eq(_formats(), ["json_schema", "json_object", ""], "each refusal costs one rung, and the ladder ends")


func test_an_ollama_that_refuses_a_schema_steps_down_to_json() -> void:
	_refuse = ["schema"]
	var b: HTTPBackend = await _backend("ollama")
	var got: Dictionary = await _ask(b, LLMService.to_json_schema(SCHEMA))
	assert_true(bool(got.get("ok", false)), "an Ollama without structured outputs still answers, err=%s" % str(got.get("err", "")))
	assert_eq(_formats(), ["schema", "json"])


func test_complete_json_puts_its_schema_on_the_wire() -> void:
	var b: HTTPBackend = await _backend()
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: the LLMService autoload exists")
	_orig_backends = _svc._backends.duplicate()
	_orig_enabled = _svc.llm_enabled
	_svc._backends.clear()
	_svc._backends.append(b)
	_svc.llm_enabled = true
	var done := [false]
	var out := [null]
	var run := func():
		out[0] = await _svc.complete_json("Pick an intent. Reply as JSON.", SCHEMA, {"fallback": true})
		done[0] = true
	run.call()
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 10000:
		_serve()
		await get_tree().process_frame
	assert_true(done[0], "CONTROL: complete_json returned")
	assert_eq(_formats(), ["json_schema"], "the feature's own schema reached the server")
	assert_eq(_bodies[0]["response_format"]["json_schema"]["schema"], LLMService.to_json_schema(SCHEMA))
	assert_eq(str((out[0] as Dictionary).get("intent", "")), "hold", "and the guarded reply comes back to the caller")


func test_control_no_schema_keeps_json_mode() -> void:
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, {})
	assert_true(bool(got.get("ok", false)), "CONTROL: answers")
	assert_eq(_formats(), ["json_object"], "CONTROL: a caller with no schema gets json_object, as before")
