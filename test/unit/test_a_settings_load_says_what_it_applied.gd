extends GutTest

## A loaded settings file printed only "[SAVE] Settings loaded", so no play log could say what Text Size,
## colour-blind mode or battle speed the player was actually on: those values printed only when CHANGED
## (cowir-story, 2026-10-14). The load line now carries the applied values — and must never carry BYOK,
## because every print persists to user://logs on disk.

const SaveSystemScript := preload("res://src/save/SaveSystem.gd")
const SECRET := "sk-THIS-MUST-NEVER-REACH-A-LOG"

var _saved := {}


func before_each() -> void:
	for k in ["text_size_scale", "color_blind_mode", "llm_custom_api_key", "llm_custom_base_url", "llm_custom_model"]:
		if k in GameState:
			_saved[k] = GameState.get(k)


func after_each() -> void:
	for k in _saved:
		GameState.set(k, _saved[k])
	## Spelled out as well: test_zz_text_size_scale_not_leaked_by_tests reads this form, not a loop.
	GameState.text_size_scale = float(_saved.get("text_size_scale", 1.0))
	_saved.clear()


func test_the_summary_carries_the_applied_values() -> void:
	GameState.text_size_scale = 1.5
	GameState.color_blind_mode = true
	var line: String = SaveSystemScript.applied_settings_summary()
	assert_true(line.contains("text_size_scale=1.5"), "the applied Text Size must be in the load line, got: %s" % line)
	assert_true(line.contains("color_blind_mode=true"), "colour-blind mode must be in the load line, got: %s" % line)


func test_every_logged_key_exists_on_game_state() -> void:
	for key in SaveSystemScript.LOGGED_SETTINGS:
		assert_true(key in GameState, "LOGGED_SETTINGS names '%s', which GameState does not have, so it silently logs nothing" % key)


func test_byok_never_reaches_the_load_line() -> void:
	GameState.llm_custom_api_key = SECRET
	GameState.llm_custom_base_url = "http://10.0.0.9:9999/v1"
	GameState.llm_custom_model = "secret-model-name"
	var line: String = SaveSystemScript.applied_settings_summary()
	assert_false(line.contains(SECRET), "the API key reached the load line, which persists to disk: %s" % line)
	assert_false(line.contains("10.0.0.9"), "the BYOK base URL reached the load line: %s" % line)
	assert_false(line.contains("secret-model-name"), "the BYOK model reached the load line: %s" % line)
	for key in SaveSystemScript.LOGGED_SETTINGS:
		assert_false(str(key).begins_with("llm_custom"), "LOGGED_SETTINGS must never name a BYOK field, found '%s'" % key)
