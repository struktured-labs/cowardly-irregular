extends GutTest

## Regression 2026-09-29: after .547 the Settings toggle refused ON until an endpoint was saved, while Configure BYOK's Test
## refused while BYOK was OFF and its Save toasted "INCOMPLETE". A first-time player met two refusals before anything worked.

const SettingsScript = preload("res://src/ui/SettingsMenu.gd")
const PanelScript = preload("res://src/ui/BYOKConfigPanel.gd")
const SETTINGS_FILE := "user://settings.json"

var _saved := {}
var _settings_bytes: PackedByteArray = PackedByteArray()
var _settings_existed := false


func before_each() -> void:
	for k in ["llm_custom_backend_enabled", "llm_custom_base_url", "llm_custom_model", "llm_custom_api_format", "llm_custom_api_key"]:
		_saved[k] = GameState.get(k)
	_settings_existed = FileAccess.file_exists(SETTINGS_FILE)
	_settings_bytes = FileAccess.get_file_as_bytes(SETTINGS_FILE) if _settings_existed else PackedByteArray()
	GameState.llm_custom_backend_enabled = false
	GameState.llm_custom_base_url = ""
	GameState.llm_custom_model = ""
	GameState.llm_custom_api_format = "ollama"
	GameState.llm_custom_api_key = ""


func after_each() -> void:
	for k in _saved:
		GameState.set(k, _saved[k])
	LLMService.apply_byok_config()
	if _settings_existed:
		var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
		f.store_buffer(_settings_bytes)
		f.close()
	elif FileAccess.file_exists(SETTINGS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))


## The fields a player types: an Ollama-format endpoint, so no key is needed.
func _type(panel, base_url: String, model: String) -> void:
	panel._base_url_field.text = base_url
	panel._format_picker.select(1)
	panel._model_field.text = model
	panel._api_key_field.text = ""


func test_test_connection_is_not_refused_just_because_byok_is_off() -> void:
	var panel = PanelScript.new()
	add_child_autofree(panel)
	_type(panel, "http://127.0.0.1:9", "tiny-model")
	assert_false(GameState.llm_custom_backend_enabled, "CONTROL: BYOK starts OFF, as it does for every first-time player")
	assert_eq(panel._config_problem(panel._typed_config()), "",
		"Test refused a complete typed config because BYOK is OFF — the toggle cannot go ON until one is saved, so this was a dead end")


func test_control_an_empty_endpoint_is_still_refused() -> void:
	var panel = PanelScript.new()
	add_child_autofree(panel)
	_type(panel, "", "tiny-model")
	assert_string_contains(panel._config_problem(panel._typed_config()), "Base URL is empty",
		"CONTROL: a config with no endpoint must still refuse instantly")


func test_save_and_apply_with_an_endpoint_switches_byok_on() -> void:
	var panel = PanelScript.new()
	add_child(panel)
	_type(panel, "http://127.0.0.1:9", "tiny-model")
	panel._on_save_pressed()
	assert_true(GameState.llm_custom_backend_enabled,
		"Save & Apply stored a usable endpoint and left BYOK OFF — the player still has to find the toggle")


func test_save_without_an_endpoint_leaves_byok_off() -> void:
	var panel = PanelScript.new()
	add_child(panel)
	_type(panel, "", "")
	panel._on_save_pressed()
	assert_false(GameState.llm_custom_backend_enabled, "saving an empty config switched BYOK ON with nothing to reach")


func test_first_time_setup_from_settings_ends_with_the_row_reading_on() -> void:
	if OS.has_feature("web"):
		pending("the BYOK row does not exist on web")
		return
	var menu = SettingsScript.new()
	add_child_autofree(menu)
	assert_false(menu._byok_configured(), "CONTROL: nothing is configured yet, so the Settings toggle refuses ON")
	menu._open_byok_config()
	var panel = null
	for c in menu.get_children():
		if c.get_script() == PanelScript:
			panel = c
	assert_not_null(panel, "CONTROL: Configure BYOK did not open from Settings")
	if panel == null:
		return
	_type(panel, "http://127.0.0.1:9", "tiny-model")
	panel._on_save_pressed()
	assert_true(menu.llm_custom_backend_enabled,
		"after configuring from Settings the BYOK row still reads OFF — setup took a second trip to the toggle")
