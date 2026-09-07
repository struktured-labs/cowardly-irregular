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


## tick 52: Test Connection button


func test_panel_has_test_button_and_status_label() -> void:
	var src := _read(PANEL)
	assert_true(src.contains("var _test_btn"),
		"panel must declare _test_btn — the Test Connection button")
	assert_true(src.contains("var _status_label"),
		"panel must declare _status_label — shows the test result")
	assert_true(src.contains("\"Test Connection\""),
		"button label must read 'Test Connection' so users know what it does")


func test_test_handler_uses_real_llm_call() -> void:
	# INTENT (unchanged): only a real round-trip is an honest test — an
	# availability check passes against a misconfigured endpoint that hangs.
	# CONTRACT CHANGED 2026-09-07: the round-trip must go to the TYPED fields,
	# not LLMService.complete(). complete() uses the last-APPLIED backend, so a
	# blank form probed local Ollama and printed OK — struktured ran weeks on
	# llama3 believing his OpenAI key was validated.
	var body := _body_of(PANEL, "_on_test_pressed")
	assert_true(body.contains("HTTPBackend.new()"),
		"_on_test_pressed must build a throwaway backend from the typed fields — a real round-trip, to the config under test")
	assert_true(body.contains("probe.submit("),
		"it must actually submit a request; an availability check is not a test")
	assert_true(body.contains("await"),
		"_on_test_pressed must await the probe — it is async")
	assert_false(body.contains("svc.complete("),
		"it must NOT route through the applied backend — that is the defect this pin now guards")

func test_test_handler_detects_fallback_vs_success() -> void:
	# INTENT (unchanged): distinguish "the backend answered" from "it timed out
	# or errored" — without it every probe reports success.
	# CONTRACT CHANGED: the sentinel comparison is gone because request_finished
	# reports ok/error directly, which is a stronger discrimination than
	# string-matching a fallback constant.
	var body := _body_of(PANEL, "_on_test_pressed")
	assert_true(body.contains("res.is_empty()"),
		"a probe that never answered must be distinguishable from one that did — the timeout arm")
	assert_true(body.contains("not bool(res[0])"),
		"an error reply must be distinguishable from a success — the failure arm")
	assert_true(body.contains("Status: OK"),
		"and a genuine answer must still report success")

func test_test_handler_short_circuits_on_unavailable() -> void:
	# INTENT (unchanged): never send a doomed probe — show an instant reason
	# instead of making the user wait out an HTTP timeout.
	# CONTRACT CHANGED: is_available() described the APPLIED backend, which is
	# the wrong subject once the test probes typed fields. The guard now refuses
	# on the typed config itself: BYOK toggled off, or empty base_url/model.
	var body := _body_of(PANEL, "_on_test_pressed")
	assert_true(body.contains("_config_problem("),
		"the handler must consult the typed-config validator before probing")
	assert_true(body.contains("Status: not tested"),
		"a refused test must say it was NOT tested — silence would read as a pass")
	var problem := _body_of(PANEL, "_config_problem")
	assert_true(problem.contains("toggled OFF"),
		"BYOK switched off must refuse — the typed fields are not in use, so there is nothing to test")
	assert_true(problem.contains("Base URL is empty") and problem.contains("Model is empty"),
		"an unfillable config must refuse instantly rather than time out at the HTTP layer")

func test_test_handler_guards_concurrent_clicks() -> void:
	# Without a guard, mashing Test would fire multiple in-flight
	# probes and the responses could land out of order.
	var body := _body_of(PANEL, "_on_test_pressed")
	assert_true(body.contains("_testing"),
		"test handler must guard against concurrent clicks via _testing flag")
	assert_true(body.contains("_test_btn.disabled"),
		"test handler must also disable the button during the probe — visual confirmation that a test is in flight")


func test_test_handler_never_logs_or_displays_api_key() -> void:
	# The Test status message must NOT include the raw api_key. Pin
	# negatively that GameState.llm_custom_api_key isn't referenced
	# in the handler body.
	var body := _body_of(PANEL, "_on_test_pressed")
	assert_false(body.contains("GameState.llm_custom_api_key"),
		"_on_test_pressed must NEVER reference the raw api_key — the LLM call uses the already-applied config")
	assert_false(body.contains("_api_key_field.text"),
		"_on_test_pressed must NEVER read the raw key field — the LLM call uses the already-applied config")
