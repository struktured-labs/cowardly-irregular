extends GutTest

## tick 50: BYOK field-input panel. Replaces "edit settings.json by
## hand" with a clickable form (base_url + format + model + api_key).
## Bound to ticks 38-39 (GameState fields + LLMService.apply_byok_config).
##
## Critical invariants pinned:
##   - api_key field uses secret=true so the visible text renders
##     as dots, not the raw key
##   - Save path writes ALL FOUR fields to GameState, persists via
##     SaveSystem, and calls LLMService.apply_byok_config for
##     immediate effect
##   - Save's Toast uses the MASKED key (never the raw value)
##   - Cancel path does NOT mutate GameState
##   - Panel only available on non-web (action row gated; open helper
##     belt-and-suspenders gated)

const PANEL := "res://src/ui/BYOKConfigPanel.gd"
const SETTINGS := "res://src/ui/SettingsMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(file_path: String, func_name: String) -> String:
	var src := _read(file_path)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist in " + file_path)
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_panel_declares_class_and_signal() -> void:
	var src := _read(PANEL)
	assert_true(src.contains("class_name BYOKConfigPanel"),
		"panel must declare class_name for SettingsMenu's loader")
	assert_true(src.contains("signal closed()"),
		"panel must emit closed so SettingsMenu clears _byok_config_open")


func test_api_key_field_uses_secret_mode() -> void:
	# CRITICAL: the LineEdit must render as dots, not the raw key.
	var src := _read(PANEL)
	assert_true(src.contains("_api_key_field.secret = true"),
		"api_key LineEdit must have secret=true so the visible text renders as dots")
	assert_true(src.contains("secret_character"),
		"api_key LineEdit must explicitly set the masking character (defensive — the default could change in a future Godot)")


func test_save_writes_all_four_fields_and_applies() -> void:
	var body := _body_of(PANEL, "_on_save_pressed")
	# All four fields mirror to GameState.
	for field in ["llm_custom_base_url",
				  "llm_custom_api_format",
				  "llm_custom_model",
				  "llm_custom_api_key"]:
		assert_true(body.contains("GameState." + field),
			"save must mirror %s to GameState" % field)
	# Persist via SaveSystem (settings.json — tick 38 gated off on web).
	assert_true(body.contains("save_settings"),
		"save must persist via SaveSystem.save_settings — without this the config doesn't survive restart")
	# Apply to the HTTPBackend so the change is immediate.
	assert_true(body.contains("apply_byok_config"),
		"save must call LLMService.apply_byok_config — without this the user has to restart for the change to take effect")


func test_save_toast_uses_masked_key_only() -> void:
	# Same safety as tick 40's settings-menu save handler. The Toast
	# must NEVER include the raw api_key — masked-only via the
	# GameState helper.
	var body := _body_of(PANEL, "_on_save_pressed")
	assert_true(body.contains("get_llm_custom_api_key_masked"),
		"save Toast must format via get_llm_custom_api_key_masked")
	# Negative: must NOT reference GameState.llm_custom_api_key in the
	# format args.
	assert_false(body.contains("Toast.show(self, GameState.llm_custom_api_key"),
		"Toast must NEVER pass the raw key — only the masked form")


func test_cancel_does_not_mutate_game_state() -> void:
	# Cancel must leave the user's prior config untouched. Pin
	# negatively: the cancel body must NOT contain any
	# `GameState.llm_custom_*` assignment.
	var body := _body_of(PANEL, "_on_cancel_pressed")
	assert_false(body.contains("GameState.llm_custom_base_url ="),
		"cancel must NOT mutate llm_custom_base_url")
	assert_false(body.contains("GameState.llm_custom_api_key ="),
		"cancel must NOT mutate llm_custom_api_key")


func test_load_from_game_state_populates_all_fields() -> void:
	# Opening the panel must show the current config so the user can
	# EDIT (not just replace). Pin all four field reads.
	var body := _body_of(PANEL, "_load_from_game_state")
	for field in ["llm_custom_base_url",
				  "llm_custom_api_format",
				  "llm_custom_model",
				  "llm_custom_api_key"]:
		assert_true(body.contains(field),
			"load must read %s from GameState so the field pre-populates" % field)


func test_esc_during_text_edit_does_not_close() -> void:
	# Common pitfall: Esc inside a LineEdit would close the panel
	# mid-edit and lose the user's work. The input handler must check
	# focus before closing.
	var body := _body_of(PANEL, "_input")
	assert_true(body.contains("gui_get_focus_owner"),
		"_input must check the focus owner before closing on ui_cancel")
	assert_true(body.contains("LineEdit"),
		"_input must specifically guard against closing while a LineEdit has focus")


func test_settings_menu_gates_action_on_non_web() -> void:
	var src := _read(SETTINGS)
	# Look for the action row registration; it must be inside a
	# `not OS.has_feature("web")` guard.
	var idx := src.find("\"Configure BYOK\"")
	assert_gt(idx, -1, "Configure BYOK action label must appear")
	var window_start: int = max(0, idx - 200)
	var window: String = src.substr(window_start, 400)
	assert_true(window.contains("not OS.has_feature(\"web\")"),
		"Configure BYOK action row must be gated behind `not OS.has_feature('web')`")


func test_open_helper_belt_and_suspenders_web_check() -> void:
	# Defensive: even if some other path calls _open_byok_config on
	# web (shouldn't happen, but), the helper must early-return.
	var body := _body_of(SETTINGS, "_open_byok_config")
	assert_true(body.contains("OS.has_feature(\"web\")"),
		"_open_byok_config must check OS.has_feature('web') and early-return — belt-and-suspenders")


func test_settings_menu_has_byok_open_state() -> void:
	# Without the flag in the submenu gate, OverworldMenu would still
	# process input while the panel is up.
	var src := _read(SETTINGS)
	assert_true(src.contains("_byok_config_open"),
		"SettingsMenu must declare _byok_config_open and include it in the submenu gate")


func test_dispatcher_routes_byok_action_id() -> void:
	var src := _read(SETTINGS)
	assert_true(src.contains("item[\"id\"] == \"byok_config\""),
		"dispatcher must handle the byok_config action id")
	assert_true(src.contains("_open_byok_config()"),
		"dispatcher must call _open_byok_config")
