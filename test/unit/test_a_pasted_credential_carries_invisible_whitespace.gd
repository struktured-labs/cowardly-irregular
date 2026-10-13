extends GutTest

## A pasted API key or Base URL carries whitespace the player cannot see, and the game answered
## with a retry promise it could never keep.
##
## MEASURED in-engine against the live local Ollama, 2026-10-13 (controls in the same run, both
## clean rows request()=0 / HTTP 200, so the instrument was alive):
##   url with a leading or inner SPACE   HTTPRequest.request() -> 31, the request NEVER STARTS
##                                       -> _start_probe's kickoff arm -> code 0 -> "unreachable"
##                                       -> the row says "UNREACHABLE — retrying every 30s"
##   url with a trailing NEWLINE         request() -> 0, sent, server answers HTTP 400
##                                       -> kind "http_error" -> "SERVER ERROR (HTTP 400) —
##                                          retrying every 30s"
##   Authorization header with a NEWLINE request() -> 0, sent, server answers HTTP 400
## Both paths promise a retry, and waiting cannot fix a malformed string. Same sin as the .663
## key-rejected case, arriving from a character with no glyph.
##
## ⛔ AND A TRAILING SPACE DEFEATS THE /v1 DE-DUPLICATION THAT HAS ITS OWN GUARD. `_base()` does
## `rstrip("/")`, which removes nothing when the last character is a space, so the `ends_with("/v1")`
## test then fails too: measured, "https://api.openai.com/v1 " builds
## "https://api.openai.com/v1 /v1/chat/completions". One invisible character reopens the exact
## defect test_a_byok_base_url_must_not_double_the_version_segment exists to prevent.
##
## ROOT CAUSE — two sources for one config, which is CLAUDE.md's category (a): Test Connection
## probed `_typed_config()`, which strips base_url and model, while `_on_save_pressed` re-read the
## raw LineEdits. So Test PASSED on a string that was never what Save stored. The repair is not a
## third spelling of the normalisation: Save now persists `_typed_config()` itself, so the two
## cannot disagree, and `apply_byok_config` strips at the funnel every saved config comes through —
## which is what reaches a settings.json written before this fix.
##
## Edges only, deliberately: a value with an inner space is left exactly as typed (arm below), so
## this cannot grow into a whitespace purge that mangles a legitimate field.

const PANEL := preload("res://src/ui/BYOKConfigPanel.gd")

## One dirty value per field, each with a different whitespace character.
const DIRTY_URL := "  http://127.0.0.1:11434\t"
const DIRTY_MODEL := " llama3:latest\n"
const DIRTY_KEY := "\n sk-test-not-a-real-key-0000 "
const WHITESPACE := [" ", "\t", "\n", "\r"]

var _gs: Node = null
var _svc: Node = null
var _snap: Dictionary = {}
var _settings_backup: String = ""
var _settings_existed: bool = false


func before_each() -> void:
	_gs = get_node_or_null("/root/GameState")
	_svc = get_node_or_null("/root/LLMService")
	_snap = {}
	if _gs != null:
		for f in ["llm_custom_base_url", "llm_custom_api_format", "llm_custom_model",
				"llm_custom_api_key", "llm_custom_backend_enabled"]:
			_snap[f] = _gs.get(f)
	## The save handler writes settings.json for real, so keep his file byte-for-byte.
	_settings_existed = FileAccess.file_exists("user://settings.json")
	_settings_backup = FileAccess.get_file_as_string("user://settings.json") if _settings_existed else ""


func after_each() -> void:
	if _gs != null:
		for f in _snap:
			_gs.set(f, _snap[f])
	if _svc != null and _svc.has_method("apply_byok_config"):
		_svc.apply_byok_config()
	if _settings_existed:
		var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
		if f != null:
			f.store_string(_settings_backup)
			f.close()


# ── the floor: every symbol this file drives, so a rename reds here by NAME ──────────────────────

func test_the_symbols_this_guard_drives_all_exist() -> void:
	assert_not_null(_gs, "GameState autoload must exist")
	assert_not_null(_svc, "LLMService autoload must exist")
	assert_true(_svc.has_method("apply_byok_config"), "LLMService.apply_byok_config")
	assert_true(_gs.has_method("byok_config_complete"), "GameState.byok_config_complete")
	var p = _panel()
	for m in ["_typed_config", "_on_save_pressed", "_config_problem"]:
		assert_true(p.has_method(m), "BYOKConfigPanel.%s" % m)
	var b := HTTPBackend.new()
	autofree(b)
	for m in ["_probe_url", "_base", "probe_headers"]:
		assert_true(b.has_method(m), "HTTPBackend.%s" % m)


# ── the door: Test and Save are ONE source ───────────────────────────────────────────────────────

func _panel() -> Control:
	var p = PANEL.new()
	add_child_autofree(p)
	return p


func _fill(p: Control, url: String, model: String, key: String) -> void:
	p._base_url_field.text = url
	p._model_field.text = model
	p._api_key_field.text = key


func test_save_persists_exactly_what_test_connection_probed() -> void:
	## Asserted as AGREEMENT between the two sources, derived from _typed_config rather than
	## restated: a second literal here would just be a third place to keep in step.
	var p := _panel()
	_fill(p, DIRTY_URL, DIRTY_MODEL, DIRTY_KEY)
	var probed: Dictionary = p._typed_config()
	assert_eq(str(probed["base_url"]), DIRTY_URL.strip_edges(), "PREMISE: Test strips the URL")
	p._on_save_pressed()
	assert_eq(str(_gs.llm_custom_base_url), str(probed["base_url"]),
		"Save stored a base_url Test Connection never probed")
	assert_eq(str(_gs.llm_custom_model), str(probed["model"]),
		"Save stored a model Test Connection never probed")
	assert_eq(str(_gs.llm_custom_api_key), str(probed["api_key"]),
		"Save stored a key Test Connection never probed")


func test_what_save_stores_has_no_edge_whitespace_at_all() -> void:
	## The consequence of the arm above, stated so it cannot pass by both sides being dirty.
	var p := _panel()
	_fill(p, DIRTY_URL, DIRTY_MODEL, DIRTY_KEY)
	p._on_save_pressed()
	for field in ["llm_custom_base_url", "llm_custom_model", "llm_custom_api_key"]:
		var v: String = str(_gs.get(field))
		assert_eq(v, v.strip_edges(), "%s was persisted with edge whitespace" % field)
		assert_ne(v, "", "%s must not be emptied — stripping is not deleting" % field)


func test_a_clean_config_is_persisted_byte_for_byte() -> void:
	## CONTROL: without this, "store a constant" or "store nothing" would satisfy the arms above.
	var p := _panel()
	_fill(p, "http://127.0.0.1:11434", "llama3:latest", "sk-clean-key")
	p._on_save_pressed()
	assert_eq(str(_gs.llm_custom_base_url), "http://127.0.0.1:11434", "a clean URL must be untouched")
	assert_eq(str(_gs.llm_custom_model), "llama3:latest", "a clean model must be untouched")
	assert_eq(str(_gs.llm_custom_api_key), "sk-clean-key", "a clean key must be untouched")


func test_an_inner_space_is_left_exactly_as_the_player_typed_it() -> void:
	## SCOPE CONTROL. strip_edges is edges-only on purpose; a global whitespace purge would
	## silently rewrite a legitimate value, and nothing downstream would say it had.
	var p := _panel()
	_fill(p, " http://host/a b ", " my model ", " key with space ")
	p._on_save_pressed()
	assert_eq(str(_gs.llm_custom_base_url), "http://host/a b", "an inner space in the URL was removed")
	assert_eq(str(_gs.llm_custom_model), "my model", "an inner space in the model was removed")
	assert_eq(str(_gs.llm_custom_api_key), "key with space", "an inner space in the key was removed")


# ── the funnel: a settings.json written before this fix ──────────────────────────────────────────

func _live_backend() -> HTTPBackend:
	for be in _svc._backends:
		if be is HTTPBackend:
			return be
	return null


func test_the_funnel_normalises_a_config_saved_before_this_fix() -> void:
	## The panel can no longer write a dirty config, but every settings.json already on disk can,
	## and load_settings assigns it verbatim. apply_byok_config is the one place they all pass.
	var http := _live_backend()
	assert_not_null(http, "PREMISE: LLMService must hold an HTTPBackend to configure")
	_gs.llm_custom_base_url = DIRTY_URL
	_gs.llm_custom_api_format = "ollama"
	_gs.llm_custom_model = DIRTY_MODEL
	_gs.llm_custom_api_key = DIRTY_KEY
	_gs.llm_custom_backend_enabled = true
	assert_true(_gs.byok_config_complete(), "PREMISE: a dirty-but-present config still counts as complete")
	assert_true(_svc.apply_byok_config(), "the funnel must accept a complete config")
	assert_eq(http.base_url, DIRTY_URL.strip_edges(), "a dirty base_url reached the backend")
	assert_eq(http.model, DIRTY_MODEL.strip_edges(), "a dirty model reached the backend")
	assert_eq(http.api_key, DIRTY_KEY.strip_edges(), "a dirty key reached the Authorization header")


func test_the_funnel_leaves_a_clean_config_alone() -> void:
	## CONTROL for the arm above.
	var http := _live_backend()
	_gs.llm_custom_base_url = "http://127.0.0.1:11434"
	_gs.llm_custom_api_format = "ollama"
	_gs.llm_custom_model = "llama3:latest"
	_gs.llm_custom_api_key = "sk-clean-key"
	_gs.llm_custom_backend_enabled = true
	assert_true(_svc.apply_byok_config(), "PREMISE: the clean config must apply")
	assert_eq(http.base_url, "http://127.0.0.1:11434", "a clean URL must survive the funnel")
	assert_eq(http.model, "llama3:latest", "a clean model must survive the funnel")
	assert_eq(http.api_key, "sk-clean-key", "a clean key must survive the funnel")


func test_the_funnel_leaves_an_inner_space_alone() -> void:
	## THE OVER-REACH DIRECTION AT THE FUNNEL, and the arm this file was missing. The panel-side
	## inner-space control asserts what GameState holds; it never looks at the backend, so swapping
	## the funnel's strip_edges for a global whitespace removal passed 11/11. Measured: that mutation
	## survived until this arm existed. A value that silently loses an inner character is a worse
	## failure than the whitespace it was added to clean.
	var http := _live_backend()
	_gs.llm_custom_base_url = " http://host/a b "
	_gs.llm_custom_api_format = "ollama"
	_gs.llm_custom_model = " my model "
	_gs.llm_custom_api_key = " key with space "
	_gs.llm_custom_backend_enabled = true
	assert_true(_svc.apply_byok_config(), "PREMISE: the config must apply")
	assert_eq(http.base_url, "http://host/a b", "the funnel removed an inner space from the URL")
	assert_eq(http.model, "my model", "the funnel removed an inner space from the model")
	assert_eq(http.api_key, "key with space", "the funnel removed an inner space from the key")


# ── the consequence a player meets: the URL and the header ───────────────────────────────────────

func test_whitespace_in_a_base_url_really_does_reach_the_request_url() -> void:
	## PREMISE for the arm below, and the measured defect itself: without this the next arm could
	## pass because strip_edges works rather than because the URL was ever at risk.
	var raw := HTTPBackend.new()
	autofree(raw)
	raw.base_url = DIRTY_URL
	raw.api_format = "ollama"
	var dirty_url: String = raw._probe_url()
	assert_true(dirty_url.contains("\t"), "the probe URL must be shown to carry the raw tab: %s" % [dirty_url])
	var v1 := HTTPBackend.new()
	autofree(v1)
	v1.base_url = "https://api.openai.com/v1 "
	v1.api_format = "openai"
	assert_true(v1._probe_url().contains("/v1 /v1"),
		"a trailing space must be shown to defeat the /v1 de-duplication: %s" % [v1._probe_url()])


func test_a_url_built_through_the_funnel_carries_no_whitespace() -> void:
	var http := _live_backend()
	_gs.llm_custom_base_url = DIRTY_URL
	_gs.llm_custom_api_format = "ollama"
	_gs.llm_custom_model = DIRTY_MODEL
	_gs.llm_custom_api_key = DIRTY_KEY
	_gs.llm_custom_backend_enabled = true
	assert_true(_svc.apply_byok_config(), "PREMISE: the config must apply")
	var url: String = http._probe_url()
	for w in WHITESPACE:
		assert_false(url.contains(w),
			"the probe URL still carries %s, which Godot either refuses (31) or sends for a 400: %s"
				% [JSON.stringify(w), url])


func test_the_authorization_header_carries_no_newline() -> void:
	## A newline in a header value is what produced the measured HTTP 400. Asserted on the RENDERED
	## header rather than on the field, because that is what crosses the wire — and the key itself
	## is never printed here, only its whitespace content tested.
	var http := _live_backend()
	_gs.llm_custom_base_url = "http://127.0.0.1:11434"
	_gs.llm_custom_api_format = "openai"
	_gs.llm_custom_model = "gpt-4o-mini"
	_gs.llm_custom_api_key = DIRTY_KEY
	_gs.llm_custom_backend_enabled = true
	assert_true(_svc.apply_byok_config(), "PREMISE: the config must apply")
	var headers: PackedStringArray = http.probe_headers()
	assert_eq(headers.size(), 1, "PREMISE: a key must produce exactly one Authorization header")
	for w in ["\n", "\r", "\t"]:
		assert_false(str(headers[0]).contains(w),
			"the Authorization header carries %s — measured HTTP 400 on the live server" % JSON.stringify(w))


func test_the_key_is_trimmed_and_not_otherwise_altered() -> void:
	## Length is the safe way to say this: the key's VALUE never appears in an assert message.
	var http := _live_backend()
	_gs.llm_custom_base_url = "http://127.0.0.1:11434"
	_gs.llm_custom_api_format = "openai"
	_gs.llm_custom_model = "gpt-4o-mini"
	_gs.llm_custom_api_key = DIRTY_KEY
	_gs.llm_custom_backend_enabled = true
	assert_true(_svc.apply_byok_config(), "PREMISE: the config must apply")
	assert_eq(http.api_key.length(), DIRTY_KEY.strip_edges().length(),
		"the key lost or gained characters beyond its edge whitespace")
	assert_true(http.api_key.begins_with("sk-"), "the key's first real characters must survive")
