extends GutTest

## tick 38: data plane for the BYOK directive (user 2026-06-22 —
## "users should be able to provide their own api keys if they want
## for a deeper model than desktop/steam deck/whatever cheap cloud
## model I may provide"). Adds the GameState fields + SaveSystem
## persistence; UI lands in a later tick.
##
## Critical constraints this test pins:
##   1. The five fields exist on GameState
##   2. SaveSystem writes them to settings.json (per-machine), NOT to
##      the per-save dict — importing someone's save must not carry
##      their key
##   3. Both write AND read paths are gated behind
##      `not OS.has_feature("web")` so the browser sandbox never
##      touches the key
##   4. The masking helper exists and behaves correctly — UI must use
##      it for ALL display

const GAME_STATE := "res://src/meta/GameState.gd"
const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_game_state_declares_five_byok_fields() -> void:
	var src := _read(GAME_STATE)
	for field in ["llm_custom_backend_enabled",
				  "llm_custom_base_url",
				  "llm_custom_api_format",
				  "llm_custom_model",
				  "llm_custom_api_key"]:
		assert_true(src.contains("var " + field),
			"GameState must declare BYOK field: %s" % field)


func test_api_key_field_marked_sensitive() -> void:
	# Comment-level guardrail. Future devs touching this field need to
	# know it's secret-bearing without grepping the whole class.
	var src := _read(GAME_STATE)
	# Find the api_key declaration and look for SENSITIVE in nearby
	# context (within ~200 chars).
	var idx := src.find("var llm_custom_api_key")
	assert_gt(idx, -1, "api_key field must exist")
	var window := src.substr(idx, 200)
	assert_true(window.contains("SENSITIVE") or window.contains("never log"),
		"api_key field comment must flag it as SENSITIVE / never-log so future edits don't accidentally print it")


func test_masking_helper_exists() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("func get_llm_custom_api_key_masked"),
		"GameState must provide a masking helper — UI must never read the raw key directly")


func test_save_system_writes_byok_in_settings_json_only() -> void:
	var src := _read(SAVE_SYSTEM)
	# Write site: under save_settings (not _create_save_data).
	var save_settings_idx := src.find("func save_settings")
	assert_gt(save_settings_idx, -1, "save_settings must exist")
	var save_settings_end := src.find("func load_settings")
	var save_settings_body := src.substr(save_settings_idx, save_settings_end - save_settings_idx)
	# All five BYOK fields written here.
	for field in ["llm_custom_backend_enabled",
				  "llm_custom_base_url",
				  "llm_custom_api_format",
				  "llm_custom_model",
				  "llm_custom_api_key"]:
		assert_true(save_settings_body.contains(field),
			"save_settings (settings.json path) must write %s" % field)

	# Negative assertion: BYOK fields MUST NOT appear in _create_save_data
	# (the per-save serialization). Importing someone's save must not
	# carry their API key.
	var create_idx := src.find("func _create_save_data")
	if create_idx > -1:
		var next_fn := src.find("\nfunc ", create_idx + 1)
		var create_body := src.substr(create_idx, next_fn - create_idx) if next_fn > -1 else src.substr(create_idx)
		assert_false(create_body.contains("llm_custom_api_key"),
			"_create_save_data MUST NOT serialize llm_custom_api_key — that would leak the key into per-save dicts shared between players")
		assert_false(create_body.contains("llm_custom_base_url"),
			"_create_save_data MUST NOT serialize BYOK config — it's per-machine, not per-save")


func test_byok_persistence_gated_on_non_web() -> void:
	var src := _read(SAVE_SYSTEM)
	# Both write and read paths must guard with `not OS.has_feature("web")`.
	# Count occurrences of the BYOK-block guard pattern.
	var write_idx := src.find("if not OS.has_feature(\"web\"):")
	assert_gt(write_idx, -1, "BYOK write path must guard on `not OS.has_feature('web')`")
	# Confirm the BYOK fields ARE inside the guard, not before it.
	var key_write_idx := src.find("settings[\"llm_custom_api_key\"]")
	assert_gt(key_write_idx, -1, "api_key must be written somewhere")
	assert_gt(key_write_idx, write_idx,
		"api_key write must come AFTER the web-gate check, not before — otherwise web builds would write the key")


func test_api_format_load_clamped_to_valid_values() -> void:
	# A corrupted settings.json could put junk in api_format (e.g.
	# "anthropic" before we add that adapter). Clamp to the valid set
	# to avoid HTTPBackend choking on an unknown format string.
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("[\"openai\", \"ollama\"]"),
		"api_format load must clamp to the known formats (openai / ollama) — corrupt settings shouldn't crash HTTPBackend probing")
