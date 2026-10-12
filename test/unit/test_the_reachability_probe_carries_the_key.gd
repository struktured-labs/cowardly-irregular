extends GutTest

## A VALID paid API key read as "server unreachable" forever, and the BYOK panel said OK.
##
## HTTPBackend's reachability probe GETs the provider's MODEL-LISTING endpoint, and it sent
## `PackedStringArray()` — no headers at all. Measured unauthenticated, 2026-10-12:
##   401  https://api.openai.com/v1/models
##   401  https://api.groq.com/openai/v1/models
##   401  https://api.deepseek.com/v1/models
##   401  https://api.together.xyz/v1/models
##   200  https://openrouter.ai/api/v1/models      (public list — the lone survivor)
##   200  http://localhost:11434/api/tags          (Ollama authenticates nothing)
## So four of the five paid presets answered 401, `_ready_flag` went false, and
## LLMService gates EVERY generation path on is_ready() — dynamic NPCs, boss intent,
## party dialogue, Rule Composer all silently fell back to scripted for the whole session.
## The panel's Test Connection passes because `submit` DOES send the key: two surfaces
## disagreed, and the one that was right is the one the player stops looking at.

const FIXTURE_KEY := "sk-probe-fixture-not-a-real-key"
const PORT_LO := 49210
const PORT_HI := 49250


## A loopback listener that records the bytes a real HTTPRequest sends it. The point is to
## read the WIRE: asserting the source line that builds the headers would certify spelling,
## and the one thing this defect proves is that a header-builder nobody passes is inert.
func _listen() -> Array:
	var server := TCPServer.new()
	for p in range(PORT_LO, PORT_HI):
		if server.listen(p, "127.0.0.1") == OK:
			return [server, p]
	return [null, 0]


func _probe_backend(key: String, port: int) -> HTTPBackend:
	var b := HTTPBackend.new()
	b.base_url = "http://127.0.0.1:%d" % port
	b.api_format = "openai"
	b.model = "gpt-4o-mini"
	b.api_key = key
	add_child_autofree(b)   # _ready() kicks the probe
	return b


## Read the request head. We never answer, so the probe times out on its own 1.5s —
## by then the bytes are already here.
func _request_head(server: TCPServer) -> String:
	var raw: String = ""
	var peer: StreamPeerTCP = null
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		if peer != null:
			peer.poll()
			var n: int = peer.get_available_bytes()
			if n > 0:
				raw += peer.get_utf8_string(n)
			if raw.contains("\r\n\r\n"):
				break
	return raw


## First line only in failure text: the head carries the fixture's own Authorization value,
## and a guard that dumps a whole request head is a guard that will one day dump a real key.
func _first_line(raw: String) -> String:
	return raw.split("\r\n")[0] if raw != "" else "(nothing arrived)"


func test_the_probe_puts_the_key_on_the_wire() -> void:
	var got: Array = _listen()
	var server: TCPServer = got[0]
	if server == null:
		pending("no loopback port free in %d-%d" % [PORT_LO, PORT_HI])
		return
	_probe_backend(FIXTURE_KEY, int(got[1]))
	var raw: String = await _request_head(server)
	server.stop()
	assert_true(raw.contains("GET /v1/models"),
		"the probe never asked for the model list; request line was: %s" % _first_line(raw))
	assert_true(raw.contains("Authorization: Bearer " + FIXTURE_KEY),
		"the reachability probe sent NO credential, so every authenticated provider answers 401 and a valid key reads as 'server unreachable' for the whole session")


func test_a_keyless_probe_sends_no_authorization_header() -> void:
	## CONTROL, and it is the local-Ollama case: Ollama authenticates nothing, so the fix
	## must not start sending a header unconditionally. Without this arm, "always attach
	## Authorization: Bearer " would pass the arm above.
	var got: Array = _listen()
	var server: TCPServer = got[0]
	if server == null:
		pending("no loopback port free in %d-%d" % [PORT_LO, PORT_HI])
		return
	_probe_backend("", int(got[1]))
	var raw: String = await _request_head(server)
	server.stop()
	assert_true(raw.contains("GET /v1/models"),
		"CONTROL: the probe must still fire with no key; request line was: %s" % _first_line(raw))
	assert_false(raw.contains("Authorization:"),
		"a keyless config sent an Authorization header — Ollama is configured with no key and must stay byte-for-byte as it was")


func test_probe_headers_carries_the_key_only_when_there_is_one() -> void:
	## The builder itself, so a failure says WHICH half broke: the builder or the call site.
	var b := HTTPBackend.new()
	autofree(b)
	b.api_key = ""
	assert_eq(b.probe_headers(), PackedStringArray([]), "no key means no headers at all")
	b.api_key = FIXTURE_KEY
	assert_eq(b.probe_headers(), PackedStringArray(["Authorization: Bearer " + FIXTURE_KEY]),
		"a GET carries no body, so the credential is the only header the probe needs")


# ── A retry promise a 401 cannot keep ────────────────────────────────────────────────────

## Drive the real handler rather than setting the private field, so the mapping is tested
## through the path that actually assigns it.
func _after_probe(code: int, result: int = HTTPRequest.RESULT_SUCCESS) -> HTTPBackend:
	var b := HTTPBackend.new()
	autofree(b)
	b.base_url = "https://api.openai.com"
	b.api_format = "openai"
	b._on_probe_completed(result, code, PackedStringArray(), PackedByteArray())
	return b


func test_the_probe_code_decides_which_failure_the_player_is_told_about() -> void:
	assert_eq(_after_probe(401).unavailable_kind(), "key_rejected", "401 is a refusal, not silence")
	assert_eq(_after_probe(403).unavailable_kind(), "key_rejected", "403 too — the key is present and unwelcome")
	assert_eq(_after_probe(404).unavailable_kind(), "not_found")
	assert_eq(_after_probe(429).unavailable_kind(), "rate_limited")
	assert_eq(_after_probe(500).unavailable_kind(), "http_error")
	## RESULT_SUCCESS is about the TRANSPORT: no server answered, so there is no status to read.
	assert_eq(_after_probe(0, HTTPRequest.RESULT_CANT_CONNECT).unavailable_kind(), "unreachable",
		"a refused connection must stay 'unreachable' — that IS the case the 30s retry fixes")
	assert_eq(_after_probe(200).unavailable_kind(), "", "a reachable backend has no failure kind")


func test_a_rejected_key_is_not_reported_as_unreachable() -> void:
	## THE CONSEQUENCE. Both strings say "it does not work"; only one sends the player
	## somewhere that can fix it, and a retry is the wrong instruction for a 401.
	var rejected: String = _after_probe(401).unavailable_reason()
	var silent: String = _after_probe(0, HTTPRequest.RESULT_CANT_CONNECT).unavailable_reason()
	assert_ne(rejected, silent, "a refused credential and an absent server read identically")
	assert_true(rejected.to_lower().contains("key"), "a 401 must name the key: %s" % rejected)
	assert_false(rejected.to_lower().contains("unreachable"),
		"a 401 called the reachable server unreachable: %s" % rejected)
	assert_true(silent.to_lower().contains("unreachable"), "CONTROL: a dead server still reads unreachable")
	assert_true(silent.contains("30"), "CONTROL: the unreachable case must keep naming the retry interval")


func test_no_failure_text_can_carry_the_api_key() -> void:
	## llm_custom_api_key is sensitive and these strings go to push_warning, which lands in
	## user://logs. The reason is built from the probe URL, which is base_url-derived.
	for code in [0, 401, 403, 404, 429, 500]:
		var b := HTTPBackend.new()
		autofree(b)
		b.base_url = "https://api.openai.com"
		b.api_key = FIXTURE_KEY
		b._on_probe_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), PackedByteArray())
		assert_false(b.unavailable_reason().contains(FIXTURE_KEY),
			"the HTTP %d reason leaked the API key into a logged warning" % code)
		assert_false(str(b.get_availability_info()).contains(FIXTURE_KEY),
			"the HTTP %d availability readout leaked the API key" % code)


## Put a backend in a known post-probe state in front of the real LLMService, so the
## subtitle is DRIVEN rather than greped. A whole-file `in` cannot support a runtime
## claim (@cowir-battle, 2026-10-12: their arm stayed green with the call moved into a
## dead function), and here the grep is weaker than the drive in a way that matters —
## the string could be present while the row never reaches it.
func _subtitle_for(backend: HTTPBackend) -> String:
	var svc: Node = get_node_or_null("/root/LLMService")
	assert_not_null(svc, "CONTROL: LLMService autoload must exist")
	var saved_backends: Array = svc._backends.duplicate()
	var saved_active = svc._active_backend
	var saved_on: bool = svc.llm_enabled
	svc._backends.clear()
	svc._backends.append(backend)
	svc._active_backend = backend
	svc.llm_enabled = true
	var menu = load("res://src/ui/SettingsMenu.gd").new()
	add_child_autofree(menu)
	var subtitle: String = menu._get_llm_status_subtitle()
	svc._backends.assign(saved_backends)
	svc._active_backend = saved_active
	svc.llm_enabled = saved_on
	return subtitle


func test_the_settings_row_tells_a_rejected_key_from_a_dead_server() -> void:
	## THE PLAYER-VISIBLE CONSEQUENCE, end to end: probe status -> backend kind ->
	## service passthrough -> the row's own text. A renamed payload key drops the row
	## to its default branch, and this arm is what notices.
	var rejected: String = _subtitle_for(_after_probe(401))
	var dead: String = _subtitle_for(_after_probe(0, HTTPRequest.RESULT_CANT_CONNECT))
	assert_ne(rejected, dead, "the row read identically for a refused key and an absent server")
	assert_false(rejected.contains("UNREACHABLE"),
		"the row called a reachable server UNREACHABLE on a 401: %s" % rejected)
	assert_true(rejected.to_lower().contains("key"), "the row must send the player to the key: %s" % rejected)
	## CONTROL: the sentence the earlier arc added — a genuinely dead server must still
	## promise the retry, or this change traded one wrong instruction for another.
	assert_true(dead.contains("UNREACHABLE"), "CONTROL: a refused connection still reads UNREACHABLE: %s" % dead)
	assert_true(dead.contains("retrying every"), "CONTROL: the unreachable row must keep promising self-healing: %s" % dead)


func test_the_row_still_reports_a_working_backend() -> void:
	## CONTROL for the whole match: without it, a row that returned the 401 text
	## unconditionally would satisfy every assert above.
	var ok: String = _subtitle_for(_after_probe(200))
	assert_true(ok.contains("Connected"), "a reachable backend must still read as connected: %s" % ok)


func test_the_backend_hands_the_ui_what_the_row_reads() -> void:
	## Both halves of the derivation, so a renamed key cannot leave the row on its default.
	var info: Dictionary = _after_probe(401).get_availability_info()
	assert_eq(int(info.get("probe_code", -1)), 401, "the readout must carry the status the row prints")
	assert_eq(str(info.get("kind", "")), "key_rejected", "the readout must carry the kind the row switches on")
	var ok: Dictionary = _after_probe(200).get_availability_info()
	assert_true(bool(ok.get("available", false)), "CONTROL: a 200 is still available")
	assert_eq(str(ok.get("kind", "x")), "", "CONTROL: a working backend reports no failure kind")
