extends GutTest

## The BYOK URL is player-set, and HTTPRequest reads an unbounded body by default: a bad server could stream for the whole
## 30 s timeout into memory. The reply, the probe and the model list are capped and fail closed saying why (HTTPTTSBackend's shape).

var _server: TCPServer
var _peers: Array = []
var _reply_pad: int = 0
var _chunked: bool = false
var _list_pad: int = 0


func after_each() -> void:
	_reply_pad = 0
	_chunked = false
	_list_pad = 0
	for p in _peers:
		(p["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()


func _reply_body() -> PackedByteArray:
	return ('{"response": "Kneel.", "pad": "%s"}' % " ".repeat(_reply_pad)).to_utf8_buffer()


func _list_body() -> PackedByteArray:
	return ('{"models": [{"name": "llama3"}], "pad": "%s"}' % " ".repeat(_list_pad)).to_utf8_buffer()


func _as_chunks(body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var step := 64 * 1024
	var i := 0
	while i < body.size():
		var part: PackedByteArray = body.slice(i, mini(i + step, body.size()))
		out.append_array(("%x\r\n" % part.size()).to_ascii_buffer())
		out.append_array(part)
		out.append_array("\r\n".to_ascii_buffer())
		i += step
	out.append_array("0\r\n\r\n".to_ascii_buffer())
	return out


## One poll of a tiny HTTP/1.1 server: a GET is the listing endpoint, a POST is /api/generate.
func _serve() -> void:
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "out": PackedByteArray(), "done": false})
	for p in _peers:
		var peer: StreamPeerTCP = p["peer"]
		peer.poll()
		if p["done"]:
			_flush(p)
			continue
		var n: int = peer.get_available_bytes()
		var buf: PackedByteArray = p["buf"]
		if n > 0:
			buf.append_array(peer.get_data(n)[1])
			p["buf"] = buf
		var head: String = buf.get_string_from_ascii()
		var end: int = head.find("\r\n\r\n")
		if end == -1:
			continue
		var length := 0
		for line in head.substr(0, end).split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.get_slice(":", 1).strip_edges())
		if buf.size() < end + 4 + length:
			continue
		var body: PackedByteArray = _reply_body() if head.begins_with("POST") else _list_body()
		var resp := PackedByteArray()
		if head.begins_with("POST") and _chunked:
			resp.append_array("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n".to_ascii_buffer())
			resp.append_array(_as_chunks(body))
		else:
			resp.append_array(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % body.size()).to_ascii_buffer())
			resp.append_array(body)
		p["out"] = resp
		p["done"] = true
		_flush(p)


## Non-blocking: the reader is this same thread, so a blocking put_data of megabytes could wait on itself forever.
func _flush(p: Dictionary) -> void:
	var out: PackedByteArray = p["out"]
	if out.is_empty():
		return
	var peer: StreamPeerTCP = p["peer"]
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		p["out"] = PackedByteArray()
		return
	var r: Array = peer.put_partial_data(out)
	if r[0] != OK:
		p["out"] = PackedByteArray()
		return
	p["out"] = out.slice(int(r[1]))


func _backend() -> HTTPBackend:
	_server = TCPServer.new()
	assert_eq(_server.listen(0, "127.0.0.1"), OK, "a local port to serve on")
	var b := HTTPBackend.new()
	b.base_url = "http://127.0.0.1:%d" % _server.get_local_port()
	b.api_format = "ollama"
	add_child_autofree(b)
	var t0 := Time.get_ticks_msec()
	while not b._first_probe_done and Time.get_ticks_msec() - t0 < 5000:
		_serve()
		await get_tree().process_frame
	return b


func _ask(b: HTTPBackend) -> Dictionary:
	var got := {}
	b.request_finished.connect(func(_id, ok, text, err): got["ok"] = ok; got["text"] = text; got["err"] = err)
	b.submit("cap1", "Taunt them.")
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		_serve()
		await get_tree().process_frame
	return got


func _list(b: HTTPBackend) -> Dictionary:
	var got := {}
	b.models_listed.connect(func(ok, models, err): got["ok"] = ok; got["models"] = models; got["err"] = err)
	b.list_models()
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		_serve()
		await get_tree().process_frame
	return got


func test_a_reply_past_the_cap_fails_closed_and_says_why() -> void:
	var b: HTTPBackend = await _backend()
	_reply_pad = HTTPBackend.MAX_REPLY_BYTES + 1024
	var got: Dictionary = await _ask(b)
	assert_false(got.is_empty(), "the request must conclude")
	assert_false(bool(got.get("ok", true)), "a reply over the cap is refused, not parsed")
	assert_string_contains(str(got.get("err", "")), "%d-byte cap" % HTTPBackend.MAX_REPLY_BYTES)


func test_a_chunked_reply_past_the_cap_is_refused_mid_stream() -> void:
	var b: HTTPBackend = await _backend()
	_chunked = true
	_reply_pad = HTTPBackend.MAX_REPLY_BYTES + 1024
	var got: Dictionary = await _ask(b)
	assert_false(bool(got.get("ok", true)), "no declared length, so the cap must hold while it streams")
	assert_string_contains(str(got.get("err", "")), "byte cap")


func test_control_a_normal_reply_arrives() -> void:
	var b: HTTPBackend = await _backend()
	_chunked = true
	var got: Dictionary = await _ask(b)
	assert_true(bool(got.get("ok", false)), "CONTROL: the same server with a normal reply answers, err=%s" % str(got.get("err", "")))
	assert_eq(str(got.get("text", "")), "Kneel.")


func test_an_oversized_listing_is_refused_by_the_probe_and_the_model_list() -> void:
	_list_pad = HTTPBackend.MAX_LISTING_BYTES + 1024
	var b: HTTPBackend = await _backend()
	assert_true(b._first_probe_done, "the probe must conclude")
	assert_false(b.is_ready(), "a listing over the cap does not make the server ready")
	var got: Dictionary = await _list(b)
	assert_false(bool(got.get("ok", true)), "the model list is refused too")
	assert_string_contains(str(got.get("err", "")), "%d-byte cap" % HTTPBackend.MAX_LISTING_BYTES)


func test_control_a_normal_listing_is_ready_and_listed() -> void:
	var b: HTTPBackend = await _backend()
	assert_true(b.is_ready(), "CONTROL: a normal listing makes the server ready")
	var got: Dictionary = await _list(b)
	assert_true(bool(got.get("ok", false)), "CONTROL: and lists its models, err=%s" % str(got.get("err", "")))
	assert_eq(Array(got.get("models", PackedStringArray())), ["llama3"])


## Files under src/ where HTTPRequest.new() outnumbers body_size_limit assignments; code only, comments stripped.
func _uncapped(dir_path: String, out: Dictionary) -> int:
	var seen: int = 0
	var d := DirAccess.open(dir_path)
	if d == null:
		return 0
	for sub in d.get_directories():
		if not sub.begins_with("."):
			seen += _uncapped(dir_path + "/" + sub, out)
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var code: String = GdSource.code_of(dir_path + "/" + f)
		var made: int = RegEx.create_from_string("HTTPRequest\\.new\\(\\)").search_all(code).size()
		var capped: int = RegEx.create_from_string("\\.body_size_limit\\s*=").search_all(code).size()
		seen += made
		if made > capped:
			out[dir_path + "/" + f] = "%d request(s), %d cap(s)" % [made, capped]
	return seen


func test_every_http_request_in_src_has_a_body_cap() -> void:
	var bad := {}
	var seen: int = _uncapped("res://src", bad)
	assert_gte(seen, 4, "CONTROL: the walk finds the LLM and TTS clients' requests")
	assert_eq(bad, {}, "an HTTPRequest with no body_size_limit reads a player-set server unbounded: %s" % str(bad))
