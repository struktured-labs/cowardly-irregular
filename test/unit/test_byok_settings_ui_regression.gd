extends GutTest

## tick 40: BYOK toggle lands in SettingsMenu so the user can actually
## flip the master switch from in-game. The text-input UI for
## base_url / model / api_key comes in a follow-up — for this tick,
## the toggle subtitle directs power users to edit settings.json by
## hand.
##
## Pins:
##   - SettingsMenu has the llm_custom_backend_enabled state variable
##   - the toggle is HIDDEN on web build (sandbox can't hold the key)
##   - toggling it calls _save_llm_custom_backend_setting
##   - the save handler mirrors to GameState AND calls
##     LLMService.apply_byok_config (without the apply call, the swap
##     waits for next restart)
##   - the save handler logs with the MASKED key, never the raw value

const SETTINGS_MENU := "res://src/ui/SettingsMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(SETTINGS_MENU)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_settings_menu_has_local_byok_state() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("var llm_custom_backend_enabled"),
		"SettingsMenu must hold a local copy of the BYOK toggle state (mirrors GameState on _ready)")


func test_byok_toggle_hidden_on_web() -> void:
	# Browser sandbox can't safely hold the API key — toggle must not
	# even appear in web builds. Pin literally: the toggle creation is
	# inside `if not OS.has_feature("web"):`.
	var src := _read(SETTINGS_MENU)
	var idx := src.find("Custom LLM Backend / BYOK")
	assert_gt(idx, -1, "BYOK toggle title must appear in the menu builder")
	# Look BACKWARDS for the web-feature gate within ~500 chars.
	var window_start := max(0, idx - 500)
	var window := src.substr(window_start, idx - window_start)
	assert_true(window.contains("not OS.has_feature(\"web\")"),
		"BYOK toggle creation must be gated behind `not OS.has_feature('web')`")


func test_toggle_action_calls_save_handler() -> void:
	var src := _read(SETTINGS_MENU)
	# Find the toggle dispatcher branch.
	var idx := src.find("item[\"id\"] == \"llm_custom_backend_enabled\"")
	assert_gt(idx, -1, "toggle dispatcher must handle llm_custom_backend_enabled")
	var body := src.substr(idx, 400)
	assert_true(body.contains("_save_llm_custom_backend_setting()"),
		"toggling BYOK must call _save_llm_custom_backend_setting — without it the change isn't persisted")


func test_save_handler_mirrors_and_applies() -> void:
	var body := _body_of("_save_llm_custom_backend_setting")
	# Must mirror local state → GameState — otherwise the persist call
	# writes stale data.
	assert_true(body.contains("GameState.llm_custom_backend_enabled = llm_custom_backend_enabled"),
		"save handler must mirror local state to GameState before persist")
	# Must call LLMService.apply_byok_config — without it, the
	# HTTPBackend swap doesn't take effect until the next game restart.
	assert_true(body.contains("apply_byok_config"),
		"save handler must call LLMService.apply_byok_config so the swap is immediate")
	# Must persist.
	assert_true(body.contains("_persist_settings"),
		"save handler must persist settings (so the choice survives a restart)")


func test_save_handler_logs_masked_key_only() -> void:
	# Logs are the primary leak vector. The print must use the MASKED
	# key (via the GameState helper) — NOT the raw api_key field.
	var body := _body_of("_save_llm_custom_backend_setting")
	# Sanity check the masking helper is referenced.
	assert_true(body.contains("get_llm_custom_api_key_masked"),
		"save handler must use the masking helper for any log output")
	# Negative: must NOT print the raw api_key directly.
	assert_false(body.contains("GameState.llm_custom_api_key"),
		"save handler must NEVER reference GameState.llm_custom_api_key in a print — must go through get_llm_custom_api_key_masked")
