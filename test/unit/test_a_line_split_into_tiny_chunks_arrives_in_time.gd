extends GutTest

## devnen streams its WAV as io.BytesIO lines (2087 chunks for a 5 s line); read one chunk per frame it took 14.4 s headless, ~35 s at 60 fps.

const CHUNKS := 1000
const BUDGET_MS := 3000

var _server: TCPServer
var _peers: Array = []


func after_each() -> void:
	for p in _peers:
		(p["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()


func _chunked(wav: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var step: int = ceili(wav.size() / float(CHUNKS))
	var i := 0
	while i < wav.size():
		var part: PackedByteArray = wav.slice(i, mini(i + step, wav.size()))
		out.append_array(("%x\r\n" % part.size()).to_ascii_buffer())
		out.append_array(part)
		out.append_array("\r\n".to_ascii_buffer())
		i += step
	out.append_array("0\r\n\r\n".to_ascii_buffer())
	return out


## One poll of a tiny HTTP/1.1 server: the probe's GET gets a voice list, the speech POST gets the chunked WAV.
func _serve(wav: PackedByteArray) -> void:
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
		var resp := PackedByteArray()
		if head.begins_with("POST"):
			resp.append_array("HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nTransfer-Encoding: chunked\r\n\r\n".to_ascii_buffer())
			resp.append_array(_chunked(wav))
		else:
			var body := '{"status": "ok", "voices": ["bard.wav"]}'.to_utf8_buffer()
			resp.append_array(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % body.size()).to_ascii_buffer())
			resp.append_array(body)
		peer.put_data(resp)
		p["done"] = true


func test_a_wav_in_a_thousand_chunks_arrives_whole_and_in_time() -> void:
	var wav := WavFixture.tone(1.0, 20000)
	_server = TCPServer.new()
	assert_eq(_server.listen(0, "127.0.0.1"), OK, "a local port to serve on")
	var b := HTTPTTSBackend.new()
	b.base_url = "http://127.0.0.1:%d" % _server.get_local_port()
	add_child_autofree(b)
	var got := {}
	b.synthesis_finished.connect(func(_id, ok, bytes, err): got["ok"] = ok; got["bytes"] = bytes; got["err"] = err)
	var t0 := Time.get_ticks_msec()
	b.synthesize("c1", "Cue the bard.", "bard.wav")
	while got.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		_serve(wav)
		await get_tree().process_frame
	var took := Time.get_ticks_msec() - t0
	assert_false(got.is_empty(), "no answer within 15 s")
	if got.is_empty():
		return
	assert_true(got["ok"], "error: %s" % got["err"])
	assert_eq((got["bytes"] as PackedByteArray).size(), wav.size(), "every chunk reassembled")
	assert_true(took < BUDGET_MS, "%d chunks took %d ms; read one per frame this is several seconds, ~35 s for a real line at 60 fps" % [CHUNKS, took])
