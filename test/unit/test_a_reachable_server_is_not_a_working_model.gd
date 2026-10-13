extends GutTest

## Settings said "Connected — <model>" while every line of dialogue fell back to scripted, because
## a reachable SERVER says nothing about the MODEL.
##
## The reachability probe GETs the provider's listing endpoint — `/api/tags` or `/v1/models` — and
## the model is not part of that request. Measured against the live local Ollama, 2026-10-13:
##   GET  /api/tags            with a bogus model configured -> HTTP 200
##   POST /api/generate        with that model               -> {"error":"model '...' not found"}
## So `is_ready()` is true, the row reports Connected, and every generation errors into its
## fallback. This is the mirror of the .663 defect: there the probe 401'd and called a working key
## UNREACHABLE; here it 200s and calls a non-existent model Connected.
##
## REACH: Save does not require Test Connection (BYOKConfigPanel._on_save_pressed), and before
## a61aa4147 the dropdown offered nine static Ollama names of which ONE resolves on this box. A
## player who picks and saves without testing lands here with nothing anywhere saying why.
##
## THE FIX COSTS NO REQUEST: the probe already fetched the listing and discarded the body.
##
## ⛔ IT DOES NOT TOUCH `is_ready()`, deliberately. A provider may serve a model its listing does
## not enumerate for a given key, so disabling on an absent name would break a WORKING config on a
## heuristic — the coincidental-ratchet direction. The remedy is the diagnosis, as it was in .663.

const OLLAMA_LISTING := '{"models":[{"name":"llama3:latest"},{"name":"qwen2.5:7b"}]}'
const OPENAI_LISTING := '{"data":[{"id":"gpt-4o-mini"},{"id":"o4-mini"}]}'


## Drive the REAL handler with a REAL listing body, which is the path that assigns the state.
func _probed(fmt: String, model_name: String, body: String, code: int = 200) -> HTTPBackend:
	var b := HTTPBackend.new()
	autofree(b)
	b.base_url = "http://127.0.0.1:11434"
	b.api_format = fmt
	b.model = model_name
	b._on_probe_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(),
		body.to_utf8_buffer())
	return b


# ── the defect ───────────────────────────────────────────────────────────────────────────────────

func test_a_model_the_server_did_not_list_is_reported_absent() -> void:
	var b := _probed("ollama", "definitely-not-installed", OLLAMA_LISTING)
	assert_true(b.is_ready(), "PREMISE: a 200 means the SERVER is reachable — that is not in dispute")
	assert_false(b.model_is_on_server(),
		"a model absent from the server's own listing read as present, which is how 'Connected' was reported for a model that cannot answer")


func test_a_model_the_server_listed_is_reported_present() -> void:
	## CONTROL: without this, "always absent" would satisfy the arm above.
	var b := _probed("ollama", "llama3:latest", OLLAMA_LISTING)
	assert_true(b.model_is_on_server(), "a model the server listed must read as present")


func test_each_format_is_checked_against_its_own_listing_shape() -> void:
	## The two providers answer different shapes; checking one against the other's would report
	## every model absent and turn a diagnosis into a false alarm on every OpenAI config.
	assert_true(_probed("openai", "gpt-4o-mini", OPENAI_LISTING).model_is_on_server(),
		"an OpenAI model in data[].id must be found")
	assert_false(_probed("openai", "gpt-9-imaginary", OPENAI_LISTING).model_is_on_server(),
		"an OpenAI model NOT in the listing must read absent")


# ── absence of evidence is not evidence of absence ───────────────────────────────────────────────

func test_an_unparseable_or_empty_listing_reads_as_UNKNOWN_not_absent() -> void:
	## ⛔ THE ARM THAT KEEPS THIS A DIAGNOSIS RATHER THAN A FALSE ALARM. A provider may serve a model
	## its listing does not enumerate for this key, and a listing can fail to parse. Every one of
	## these must read PRESENT, or a working config gets told its model does not exist.
	for body in ["", "not json", "{}", "[]", '{"models":[]}', '{"data":[]}', '{"models":"x"}']:
		assert_true(_probed("ollama", "llama3:latest", body).model_is_on_server(),
			"an unparseable/empty listing (%s) must read UNKNOWN, not absent" % [body])
		assert_true(_probed("openai", "gpt-4o-mini", body).model_is_on_server(),
			"same for openai: %s" % [body])


func test_an_unreachable_probe_forgets_the_listing() -> void:
	## A stale list from a previous endpoint would judge the NEW one. The listing is state about a
	## server that just answered; a probe that did not reach one must leave nothing behind.
	var b := _probed("ollama", "llama3:latest", OLLAMA_LISTING)
	assert_eq(int(b.get_availability_info()["server_model_count"]), 2, "PREMISE: the listing was read")
	b._on_probe_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	assert_eq(int(b.get_availability_info()["server_model_count"]), 0,
		"the listing survived a failed probe, so a dead endpoint still judges the model")
	assert_true(b.model_is_on_server(), "and with nothing known it must read UNKNOWN, not absent")


func test_an_empty_model_is_not_judged() -> void:
	## An unset model is the incomplete-config case, which the panel's own save-time toast owns.
	assert_true(_probed("ollama", "", OLLAMA_LISTING).model_is_on_server(),
		"an empty model must not be reported as missing from the server")


# ── the readout the player actually sees ─────────────────────────────────────────────────────────

func _subtitle_for(b: HTTPBackend) -> String:
	var svc: Node = get_node_or_null("/root/LLMService")
	assert_not_null(svc, "CONTROL: LLMService autoload must exist")
	var saved: Array = svc._backends.duplicate()
	var saved_active = svc._active_backend
	var saved_on: bool = svc.llm_enabled
	svc._backends.clear()
	svc._backends.append(b)
	assert_eq(svc._backends.size(), 1, "PREMISE: the backend must actually be in _backends")
	svc._active_backend = b
	svc.llm_enabled = true
	var menu = load("res://src/ui/SettingsMenu.gd").new()
	add_child_autofree(menu)
	var out: String = menu._get_llm_status_subtitle()
	svc._backends.assign(saved)
	svc._active_backend = saved_active
	svc.llm_enabled = saved_on
	return out


func test_the_row_stops_claiming_connected_when_the_model_is_missing() -> void:
	## THE PLAYER-VISIBLE CONSEQUENCE, end to end: probe body -> backend -> service -> the row.
	var missing: String = _subtitle_for(_probed("ollama", "definitely-not-installed", OLLAMA_LISTING))
	assert_false(missing.contains("Connected"),
		"the row still said Connected for a model the server does not have: %s" % missing)
	assert_true(missing.contains("definitely-not-installed"),
		"the row must NAME the model, or the player cannot tell which field is wrong: %s" % missing)
	assert_true(missing.contains("2"),
		"the row should say how many the server DID list, so the player knows the list is worth opening: %s" % missing)


func test_the_row_still_says_connected_when_the_model_is_there() -> void:
	## CONTROL for the arm above, and for the whole change: a correct config must read unchanged.
	var ok: String = _subtitle_for(_probed("ollama", "llama3:latest", OLLAMA_LISTING))
	assert_true(ok.contains("Connected"), "a working config must still read Connected: %s" % ok)
	assert_false(ok.contains("no model called"), "and must not carry the warning: %s" % ok)


func test_an_unknown_listing_still_reads_connected() -> void:
	## The UNKNOWN path at the surface: a server that lists nothing must not scare a working player.
	var unknown: String = _subtitle_for(_probed("ollama", "llama3:latest", "{}"))
	assert_true(unknown.contains("Connected"),
		"an unparseable listing turned a working config into a warning: %s" % unknown)


func test_is_ready_is_deliberately_untouched() -> void:
	## Pinned because the tempting next edit is to disable the backend on an absent name, and that
	## breaks a provider whose listing does not enumerate every model it serves. The remedy here is
	## the DIAGNOSIS; `.663` made the same choice for a rejected key.
	var b := _probed("ollama", "definitely-not-installed", OLLAMA_LISTING)
	assert_true(b.is_ready(),
		"a missing model must not flip is_ready() — a listing that omits a working model would then disable a working config")
	assert_eq(str(b.unavailable_kind()), "",
		"and a reachable backend still has no failure kind: the model check is a separate axis")
