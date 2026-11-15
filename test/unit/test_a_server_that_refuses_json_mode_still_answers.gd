extends GutTest

## Some OpenAI-compatible servers take response_format json_schema or text only, and answer json_object with a 400 that names
## response_format. Every JSON feature (boss strategy, rule composer, rebalance) then failed on every call while plain dialogue worked.

const STRICT_400 := '{"error": {"message": "\'response_format.type\' must be \'json_schema\' or \'text\'"}}'
const OTHER_400 := '{"error": {"message": "model not loaded"}}'

var _server: TCPServer
var _peers: Array = []
var _mode: String = "strict"
var _posts: int = 0
var _carried: int = 0


func after_each() -> void:
	_mode = "strict"
	_posts = 0
	_carried = 0
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
	_posts += 1
	var carries: bool = request.contains("response_format")
	if carries:
		_carried += 1
	if _mode == "broken":
		return _respond(400, OTHER_400)
	if _mode == "strict" and carries:
		return _respond(400, STRICT_400)
	return _respond(200, '{"choices": [{"message": {"content": "{\\"intent\\": \\"press\\"}"}}]}')


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


func _backend() -> HTTPBackend:
	_server = TCPServer.new()
	assert_eq(_server.listen(0, "127.0.0.1"), OK, "a local port to serve on")
	var b := HTTPBackend.new()
	b.base_url = "http://127.0.0.1:%d" % _server.get_local_port()
	b.api_format = "openai"
	b.model = "m"
	add_child_autofree(b)
	var t0 := Time.get_ticks_msec()
	while not b._first_probe_done and Time.get_ticks_msec() - t0 < 5000:
		_serve()
		await get_tree().process_frame
	return b


## Submits every id at once and waits for all of them; returns id -> {ok, text, err}.
func _ask(b: HTTPBackend, ids: Array, json_mode: bool = true) -> Dictionary:
	var got := {}
	var on_done := func(id, ok, text, err): got[id] = {"ok": ok, "text": text, "err": err}
	b.request_finished.connect(on_done)
	for id in ids:
		b.submit(id, "Pick an intent. Reply as JSON.", {"json_mode": json_mode})
	var t0 := Time.get_ticks_msec()
	while got.size() < ids.size() and Time.get_ticks_msec() - t0 < 10000:
		_serve()
		await get_tree().process_frame
	b.request_finished.disconnect(on_done)
	return got


func test_a_refused_json_object_is_retried_without_it_and_answers() -> void:
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, ["j1"])
	assert_true(bool(got.get("j1", {}).get("ok", false)), "the JSON feature gets its answer, err=%s" % str(got.get("j1", {}).get("err", "")))
	assert_eq(str(got.get("j1", {}).get("text", "")), "{\"intent\": \"press\"}")
	assert_eq([_posts, _carried], [2, 1], "one refused try with response_format, one retry without it")


func test_the_refusal_is_remembered_for_that_server() -> void:
	var b: HTTPBackend = await _backend()
	await _ask(b, ["j1"])
	var got: Dictionary = await _ask(b, ["j2"])
	assert_true(bool(got.get("j2", {}).get("ok", false)), "the next JSON request answers")
	assert_eq([_posts, _carried], [3, 1], "and goes straight out without response_format: no second refused round trip")


func test_requests_in_flight_together_each_retry() -> void:
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, ["j1", "j2"])
	assert_true(bool(got.get("j1", {}).get("ok", false)) and bool(got.get("j2", {}).get("ok", false)), "both sent with response_format, so both retry: %s" % str(got))
	assert_eq([_posts, _carried], [4, 2])


func test_control_a_server_that_accepts_json_object_keeps_getting_it() -> void:
	_mode = "lenient"
	var b: HTTPBackend = await _backend()
	await _ask(b, ["j1"])
	var got: Dictionary = await _ask(b, ["j2"])
	assert_true(bool(got.get("j2", {}).get("ok", false)), "CONTROL: a lenient server answers")
	assert_eq([_posts, _carried], [2, 2], "CONTROL: response_format is dropped only for a server that refused it")


func test_control_an_unrelated_400_is_not_retried() -> void:
	_mode = "broken"
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, ["j1"])
	assert_false(bool(got.get("j1", {}).get("ok", true)), "CONTROL: a 400 for another reason still fails")
	assert_eq(str(got.get("j1", {}).get("err", "")), "HTTP 400")
	assert_eq(_posts, 1, "CONTROL: and is sent once")


func test_control_a_plain_request_never_carries_response_format() -> void:
	var b: HTTPBackend = await _backend()
	var got: Dictionary = await _ask(b, ["p1"], false)
	assert_true(bool(got.get("p1", {}).get("ok", false)), "CONTROL: dialogue answers on the strict server")
	assert_eq([_posts, _carried], [1, 0])
