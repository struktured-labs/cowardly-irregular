extends GutTest

## Regression 2026-09-28: struktured's settings held BYOK ON with no base URL, model or key from 09-23 on.
## Every boot logged a fallback warning while the Settings row kept reading ON and every call went to local Ollama.

const SettingsScript = preload("res://src/ui/SettingsMenu.gd")

var _saved := {}


func before_each() -> void:
	for k in ["llm_custom_backend_enabled", "llm_custom_base_url", "llm_custom_model", "llm_custom_api_format", "llm_custom_api_key"]:
		_saved[k] = GameState.get(k)


func after_each() -> void:
	for k in _saved:
		GameState.set(k, _saved[k])
	LLMService.apply_byok_config()


func _set_byok(on: bool, base_url: String, model: String) -> void:
	GameState.llm_custom_backend_enabled = on
	GameState.llm_custom_base_url = base_url
	GameState.llm_custom_model = model
	GameState.llm_custom_api_format = "openai"
	GameState.llm_custom_api_key = ""


func _http() -> HTTPBackend:
	for be in LLMService._backends:
		if be is HTTPBackend:
			return be
	return null


func test_a_saved_on_with_nothing_set_is_turned_off_when_applied() -> void:
	assert_not_null(_http(), "CONTROL: no HTTPBackend, so apply_byok_config has nothing to configure")
	_set_byok(true, "", "")
	assert_true(LLMService.apply_byok_config(), "CONTROL: the config was applied")
	assert_false(GameState.llm_custom_backend_enabled,
		"BYOK stayed ON with no endpoint — the Settings row reads ON while every call goes to local Ollama")
	assert_eq(_http().base_url, "http://localhost:11434", "CONTROL: the fallback is still local Ollama")


func test_control_a_complete_config_stays_on_and_is_used() -> void:
	_set_byok(true, "http://127.0.0.1:9", "tiny-model")
	LLMService.apply_byok_config()
	assert_true(GameState.llm_custom_backend_enabled, "CONTROL: a configured BYOK was switched off")
	assert_eq(_http().base_url, "http://127.0.0.1:9", "CONTROL: the configured endpoint must be the one in use")


func test_the_settings_toggle_refuses_on_while_nothing_is_set() -> void:
	if OS.has_feature("web"):
		pending("the BYOK row does not exist on web")
		return
	_set_byok(false, "", "")
	var menu = SettingsScript.new()
	add_child(menu)
	var row := -1
	for i in range(menu._settings_items.size()):
		if str(menu._settings_items[i].get("id", "")) == "llm_custom_backend_enabled":
			row = i
	assert_gt(row, -1, "CONTROL: the Settings menu has no BYOK row to press")
	menu.selected_index = row
	menu._adjust_setting(1)
	assert_false(menu.llm_custom_backend_enabled, "pressing the BYOK row with nothing set switched it ON")
	assert_false(GameState.llm_custom_backend_enabled, "pressing the BYOK row with nothing set saved it ON")
	menu.free()


func test_the_toggle_accepts_on_once_an_endpoint_and_model_exist() -> void:
	_set_byok(false, "http://127.0.0.1:9", "tiny-model")
	var menu = SettingsScript.new()
	assert_true(menu._byok_configured(), "CONTROL: a base URL and a model must be enough to switch BYOK on")
	_set_byok(false, "http://127.0.0.1:9", "   ")
	assert_false(menu._byok_configured(), "a whitespace model reached the toggle as configured")
	menu.free()


func test_the_row_rereads_the_state_when_the_panel_closes() -> void:
	if OS.has_feature("web"):
		pending("the BYOK row does not exist on web")
		return
	var menu = SettingsScript.new()
	add_child(menu)
	menu.llm_custom_backend_enabled = true
	GameState.llm_custom_backend_enabled = false
	menu._on_byok_config_closed()
	assert_false(menu.llm_custom_backend_enabled,
		"the panel's Save turned BYOK OFF and the Settings row behind it still read ON")
	menu.free()
