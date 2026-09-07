extends GutTest

## The BYOK "Test connection" button used to call LLMService.complete() — the
## CURRENTLY APPLIED backend. With base_url/model blank that resolves to local
## Ollama, so a blank form printed "Status: OK" and struktured ran for weeks
## believing it had validated his OpenAI key. A green that names no backend.

const PANEL_PATH: String = "res://src/ui/BYOKConfigPanel.gd"
const SVC_PATH: String = "res://src/llm/LLMService.gd"


func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "file must exist: %s" % path)
	var t: String = f.get_as_text()
	f.close()
	return t


func test_the_test_button_does_not_use_the_applied_backend() -> void:
	var src: String = _read(PANEL_PATH)
	var i: int = src.find("func _on_test_pressed")
	assert_true(i != -1, "the Test handler must exist")
	var body: String = src.substr(i, 2200)
	assert_true(body.find("svc.complete(") == -1,
		"the Test button must NOT probe the applied backend — that is how a blank form reported OK from Ollama")
	assert_true(body.find("HTTPBackend.new()") != -1,
		"it must probe a throwaway backend built from the TYPED fields instead")


func test_the_probe_is_built_from_the_form_not_game_state() -> void:
	var src: String = _read(PANEL_PATH)
	var i: int = src.find("func _typed_config")
	assert_true(i != -1, "a typed-config reader must exist")
	var body: String = src.substr(i, 400)
	assert_true(body.find("_base_url_field.text") != -1, "base_url must come from the form field")
	assert_true(body.find("_model_field.text") != -1, "model must come from the form field")
	assert_true(body.find("GameState") == -1,
		"the tested config must NOT be read from GameState — that holds the last-APPLIED values, which is the bug")


func test_every_test_outcome_names_the_endpoint() -> void:
	var src: String = _read(PANEL_PATH)
	var i: int = src.find("func _on_test_pressed")
	var body: String = src.substr(i, 2200)
	assert_true(body.find("var where: String") != -1,
		"a single endpoint label must be built once and used by every branch")
	# The OK branch is the one that lied; it must carry the label.
	var ok_at: int = body.find("Status: OK")
	assert_true(ok_at != -1, "there must still be a success branch")
	assert_true(body.substr(ok_at, 120).find("where") != -1,
		"the SUCCESS message must name which base_url/model answered — an unnamed green is the defect")


func test_incomplete_config_is_refused_not_silently_tested() -> void:
	var src: String = _read(PANEL_PATH)
	assert_true(src.find("func _config_problem") != -1, "a config validator must exist")
	var i: int = src.find("func _config_problem")
	var body: String = src.substr(i, 700)
	assert_true(body.find("Base URL is empty") != -1, "an empty base_url must be named as the problem")
	assert_true(body.find("Model is empty") != -1, "an empty model must be named as the problem")
	assert_true(body.find("falls back to local Ollama") != -1,
		"the message must say WHERE it falls back to — that is the fact he was missing")


func test_service_warns_when_byok_is_on_but_incomplete() -> void:
	var src: String = _read(SVC_PATH)
	var i: int = src.find("http.base_url = \"http://localhost:11434\"")
	assert_true(i != -1, "the Ollama fallback must still exist")
	var before: String = src.substr(maxi(0, i - 600), 600)
	assert_true(before.find("push_warning") != -1,
		"falling back while BYOK is toggled ON must warn — silence is what made this invisible")
	assert_true(before.find("NOT in use") != -1,
		"the warning must state that the custom endpoint and key are not being used")
