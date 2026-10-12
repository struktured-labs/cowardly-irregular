extends GutTest

## The BYOK model dropdown was a hardcoded list while the reachability probe already GET the
## provider's model-listing endpoint and threw the body away.
##
## MEASURED on this box, 2026-10-12: Ollama has `llama3:latest` installed, and of the nine static
## entries the Ollama preset offers, ONE resolves. Eight name a model that is not there — so a
## player picking from the dropdown has a 1-in-9 chance and no way to tell, because Test Connection
## submits a real generation and fails with the server's own error only AFTER they guess.
##
## The listing is requested at the one moment it is guaranteed usable: straight after a successful
## Test Connection, while the probe that just proved the config is still alive. Ollama needs no key
## for this; paid providers need the one the probe now sends (bfc36ccde), which is why a live list
## can only ever AUGMENT the static one rather than replace it.

const PANEL := preload("res://src/ui/BYOKConfigPanel.gd")
const REFUSED := "http://127.0.0.1:1"

## Real shapes, from each provider's documented listing response.
const OLLAMA_BODY := '{"models":[{"name":"llama3:latest","size":1},{"name":"qwen2.5:7b"}]}'
const OPENAI_BODY := '{"data":[{"id":"gpt-4o-mini","object":"model"},{"id":"o4-mini"}],"object":"list"}'


# ── the parser: pure, no server ───────────────────────────────────────────────────────────────────

func test_each_format_is_read_from_its_own_documented_shape() -> void:
	assert_eq(HTTPBackend.parse_model_list("ollama", OLLAMA_BODY),
		PackedStringArray(["llama3:latest", "qwen2.5:7b"]), "ollama answers models[].name")
	assert_eq(HTTPBackend.parse_model_list("openai", OPENAI_BODY),
		PackedStringArray(["gpt-4o-mini", "o4-mini"]), "openai answers data[].id")


func test_the_parser_follows_the_same_branching_as_the_probe_url() -> void:
	## The two must agree or we parse one provider's body with another's shape. An unknown format
	## follows OpenAI in _probe_url, so it must here too — asserted as the RELATION, not by
	## restating either spelling.
	var b := HTTPBackend.new()
	autofree(b)
	b.base_url = "https://example.invalid"
	for fmt in ["openai", "something_else", ""]:
		b.api_format = fmt
		assert_eq(HTTPBackend.parse_model_list(fmt, OPENAI_BODY).size(), 2,
			"format '%s' routes to /v1/models in _probe_url, so it must read the OpenAI shape" % fmt)
		assert_eq(HTTPBackend.parse_model_list(fmt, OLLAMA_BODY).size(), 0,
			"format '%s' must NOT read the ollama shape, or one provider's body is parsed as another's" % fmt)
	b.api_format = "ollama"
	assert_eq(HTTPBackend.parse_model_list("ollama", OPENAI_BODY).size(), 0,
		"ollama must not read the OpenAI shape either")


func test_nothing_a_server_can_send_makes_the_parser_invent_a_model() -> void:
	for raw in ["", "not json", "[]", "null", "{}", '{"models":"llama3"}', '{"models":[1,2]}',
			'{"models":[{"nope":"x"}]}', '{"data":[{"id":""}]}', '{"data":[{"id":"   "}]}']:
		assert_eq(HTTPBackend.parse_model_list("ollama", raw), PackedStringArray([]),
			"ollama parse of %s must yield nothing" % [raw])
		assert_eq(HTTPBackend.parse_model_list("openai", raw), PackedStringArray([]),
			"openai parse of %s must yield nothing" % [raw])


func test_a_name_is_listed_once_and_trimmed() -> void:
	assert_eq(HTTPBackend.parse_model_list("ollama", '{"models":[{"name":" a "},{"name":"a"},{"name":"b"}]}'),
		PackedStringArray(["a", "b"]), "a duplicate after trimming must not become two picker rows")


# ── the fetch: answers exactly once, never hangs ─────────────────────────────────────────────────

func test_an_unreachable_endpoint_answers_once_and_not_ok() -> void:
	var b := HTTPBackend.new()
	b.base_url = REFUSED
	b.api_format = "ollama"
	add_child_autofree(b)
	var got: Array = []
	b.models_listed.connect(func(ok, models, err): got.append([ok, models.size(), err]))
	b.list_models()
	var t0: int = Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1, "exactly one answer per call, or the panel waits forever")
	assert_false(bool(got[0][0]), "a refused endpoint is not ok")
	assert_eq(int(got[0][1]), 0, "and lists no models")
	assert_ne(str(got[0][2]), "", "a failure must say why")


## A blackhole address: the connection neither completes nor is refused, so the probe stays
## IN FLIGHT long enough to test what a listing does to it. REFUSED fails instantly and leaves
## _probe_request null, which made the first version of this arm vacuous — its mutation passed.
const BLACKHOLE := "http://10.255.255.1:65000"


func test_a_listing_never_cancels_an_IN_FLIGHT_reachability_probe() -> void:
	## They would share one HTTPRequest if _list_request did not exist, and a player opening the
	## panel would knock the live backend's availability probe over mid-flight.
	var b := HTTPBackend.new()
	b.base_url = BLACKHOLE
	add_child_autofree(b)
	b._start_probe()
	## PREMISE: without an in-flight probe there is nothing for a listing to disturb.
	assert_not_null(b._probe_request, "PREMISE: the probe must be in flight for this arm to mean anything")
	var probe_node: HTTPRequest = b._probe_request
	b.list_models()
	assert_eq(b._probe_request, probe_node, "the listing replaced the probe's own request node")
	assert_true(is_instance_valid(probe_node), "the listing freed the in-flight probe's request")
	assert_true(probe_node.request_completed.is_connected(b._on_probe_completed),
		"the listing disconnected the probe's completion handler, so availability would never resolve")
	assert_ne(b._list_request, probe_node,
		"one node for both means a model listing aborts the availability probe mid-flight")


# ── the merge: the field stays authoritative ─────────────────────────────────────────────────────

func _panel_on_ollama() -> Control:
	var p = PANEL.new()
	add_child_autofree(p)
	for i in _provider_count(p):
		if str(p.PROVIDER_PRESETS[i]["label"]).begins_with("Ollama"):
			p._provider_picker.selected = i
			p._on_provider_selected(i)
			break
	return p


func _provider_count(p) -> int:
	return (p.PROVIDER_PRESETS as Array).size()


func _picker_texts(p) -> Array:
	var out: Array = []
	for i in p._model_picker.item_count:
		out.append(p._model_picker.get_item_text(i))
	return out


func test_the_servers_models_come_before_the_ones_it_does_not_have() -> void:
	## The ORDER is the feature: a player picks the first row, and before this change that row was
	## a guess. Asserted as a relation between the two groups, never as fixed indices.
	var p = _panel_on_ollama()
	var statics: Array = []
	for m in p.PROVIDER_PRESETS[p._provider_picker.selected].get("models", []):
		statics.append(str(m))
	assert_gt(statics.size(), 1, "CONTROL: the Ollama preset must still carry a static list")
	p._model_field.text = ""
	p._merge_live_models(PackedStringArray(["live-a", "live-b"]))
	var texts: Array = _picker_texts(p)
	var first_static: int = texts.size()
	for i in texts.size():
		if statics.has(texts[i]) and not ["live-a", "live-b"].has(texts[i]):
			first_static = i
			break
	## PRESENCE FIRST: find() returns -1 for an absent item, and -1 < any index — so dropping the
	## live models entirely satisfied the ordering assert below. Measured: that mutation passed.
	assert_gt(texts.find("live-a"), -1, "the server's models must appear in the picker at all")
	assert_gt(texts.find("live-b"), -1, "both of them")
	assert_lt(texts.find("live-a"), first_static, "a model the server HAS must sort above one it does not")
	assert_lt(texts.find("live-b"), first_static, "both of them")
	assert_eq(texts[texts.size() - 1], p.CUSTOM_MODEL_LABEL, "Custom… stays last")


func test_a_model_the_player_typed_is_never_overwritten() -> void:
	## _model_field is the authoritative value the probe reads. A live listing may reorder the
	## picker; it may not silently change what will be sent.
	var p = _panel_on_ollama()
	p._model_field.text = "my-own-finetune"
	var note: String = p._merge_live_models(PackedStringArray(["live-a", "live-b"]))
	assert_eq(p._model_field.text, "my-own-finetune", "the typed model was replaced by the server's first")
	assert_true(note.to_lower().contains("not"),
		"a model the server does not list must be REPORTED, not silently kept: %s" % note)


func test_a_typed_model_the_server_does_have_is_confirmed_not_warned() -> void:
	## CONTROL for the arm above: without it, "always warn" would pass.
	var p = _panel_on_ollama()
	p._model_field.text = "live-b"
	var note: String = p._merge_live_models(PackedStringArray(["live-a", "live-b"]))
	assert_eq(p._model_field.text, "live-b", "a confirmed model is still not rewritten")
	assert_false(note.to_lower().contains("not "),
		"a model the server DOES list must not be reported as missing: %s" % note)


func test_an_empty_listing_leaves_the_static_list_exactly_as_it_was() -> void:
	## The failure path a player meets most: a server that answers but lists nothing must not
	## empty the dropdown and leave them with no options at all.
	var p = _panel_on_ollama()
	var before: Array = _picker_texts(p)
	var field_before: String = p._model_field.text
	var note: String = p._merge_live_models(PackedStringArray([]))
	assert_eq(_picker_texts(p), before, "an empty listing must not touch the picker")
	assert_eq(p._model_field.text, field_before, "nor the field")
	assert_eq(note, "", "and must say nothing rather than claim a count")


func test_the_panel_asks_for_the_list_while_the_probe_is_still_alive() -> void:
	## queue_free is deferred and _await_models yields across frames, so a listing requested after
	## the free can never answer and stalls the full timeout before reporting nothing. My first
	## version did exactly that. STATEMENT ORDER is a textual fact, present before anything runs,
	## which is what makes a source pin the right instrument here — the runtime symptom needs a
	## live server, which no unit test has.
	var src: String = FileAccess.get_file_as_string("res://src/ui/BYOKConfigPanel.gd")
	assert_ne(src, "", "CONTROL: the panel must be readable")
	var body: String = src.substr(src.find("func _on_test_pressed"))
	body = body.substr(0, body.find("\nfunc "))
	var ask: int = body.find("_await_models(probe)")

	var free_at: int = body.find("probe.queue_free()")
	assert_gt(ask, -1, "the test handler must ask for the model list at all")
	assert_gt(free_at, -1, "CONTROL: it must still free the probe")
	assert_lt(ask, free_at, "the listing is requested after the probe is freed — it can never answer")
