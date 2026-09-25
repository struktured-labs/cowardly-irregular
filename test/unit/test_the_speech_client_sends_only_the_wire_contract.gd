extends GutTest

## The client sends exactly the wire contract: delivery (exaggeration/cfg/temperature/seed) is the server's, per voice.

const REFUSED_URL := "http://127.0.0.1:1"


func test_the_request_body_is_exactly_the_four_contract_keys() -> void:
	var b := HTTPTTSBackend.new()
	b.model = "chatterbox"
	var body: Dictionary = JSON.parse_string(b.build_body("Hello there.", "bard.wav"))
	var keys: Array = body.keys()
	keys.sort()
	assert_eq(keys, ["input", "model", "response_format", "voice"], "contract 4: no delivery parameters leave the client")
	assert_eq(body["response_format"], "wav")
	assert_eq(body["voice"], "bard.wav")
	assert_eq(body["input"], "Hello there.")
	b.free()


func test_the_voice_list_parses_the_real_servers_shape() -> void:
	## devnen server.py @ 915ae28 lines 1382-1386.
	assert_eq(HTTPTTSBackend.parse_voices('{"status": "ok", "voices": ["bard.wav", "fighter.wav"]}'),
		["bard.wav", "fighter.wav"] as Array[String])
	assert_eq(HTTPTTSBackend.parse_voices('[{"filename": "mage.wav", "display_name": "Mage"}]'),
		["mage.wav"] as Array[String], "the /get_predefined_voices shape too")
	assert_eq(HTTPTTSBackend.parse_voices("not json"), [] as Array[String])


func test_a_refused_connection_answers_once_and_not_ok() -> void:
	var b := HTTPTTSBackend.new()
	b.base_url = REFUSED_URL
	add_child_autofree(b)
	var got: Array = []
	b.synthesis_finished.connect(func(id, ok, wav, err): got.append([id, ok, wav.size(), err]))
	b.synthesize("t1", "Hello.", "bard.wav")
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1, "exactly one answer per id, or a caller waits forever")
	assert_eq(got[0][0], "t1")
	assert_false(got[0][1])
	assert_ne(got[0][3], "", "a failure says why")


func test_contacts_url_names_where_requests_go() -> void:
	var h := HTTPTTSBackend.new()
	h.base_url = "http://127.0.0.1:8004/v1/"
	assert_eq(h.contacts_url(), "http://127.0.0.1:8004", "trailing /v1 and slash are ours to add")
	h.free()
	var n := NullTTSBackend.new()
	assert_eq(n.contacts_url(), "", "the null backend contacts nothing")
	assert_false(n.is_ready())
	n.free()
