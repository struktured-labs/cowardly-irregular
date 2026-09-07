extends GutTest

## Regression: SettingsMenu has shipped a Text Speed toggle (slow/normal/
## fast/instant) since the v2 settings overhaul, but CutsceneDialogue
## never read the setting — the typewriter always typed at the hard-coded
## 0.03s default. This test pins:
##   1. CutsceneDialogue declares a TYPING_SPEED_PRESETS table whose keys
##      match SettingsMenu.TEXT_SPEED_PRESETS so the two stay in lockstep.
##   2. _resolve_typing_speed() picks the right value for each preset.
##   3. The "instant" preset triggers the typewriter-bypass path (not just
##      a tiny tick interval — fully skipped reveal).

const DIALOGUE_PATH := "res://src/cutscene/CutsceneDialogue.gd"
const SETTINGS_MENU_PATH := "res://src/ui/SettingsMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_typing_speed_keys_match_settings_text_speed_presets() -> void:
	# Cross-file consistency: the dialogue lookup must accept every key the
	# settings menu can produce. Otherwise the user picks "fast" and the
	# resolver silently falls back to "normal".
	var dialogue_text = _read(DIALOGUE_PATH)
	var settings_text = _read(SETTINGS_MENU_PATH)
	for key in ["slow", "normal", "fast", "instant"]:
		assert_true(dialogue_text.find("\"" + key + "\":") > -1,
			"CutsceneDialogue.TYPING_SPEED_PRESETS must include key: %s" % key)
		assert_true(settings_text.find("\"" + key + "\"") > -1,
			"SettingsMenu.TEXT_SPEED_PRESETS must include key: %s" % key)


func test_resolve_typing_speed_honors_each_preset() -> void:
	var script = load(DIALOGUE_PATH)
	var d = script.new()
	add_child_autofree(d)

	# Save / restore the live setting so we don't leak into other tests.
	var prev = "normal"
	if GameState and "text_speed" in GameState:
		prev = GameState.text_speed

	GameState.text_speed = "slow"
	assert_almost_eq(d._resolve_typing_speed(), 0.06, 0.001,
		"slow should resolve to ~0.06s per char (~16 cps)")

	GameState.text_speed = "normal"
	assert_almost_eq(d._resolve_typing_speed(), 0.03, 0.001,
		"normal should resolve to ~0.03s per char (~33 cps)")

	GameState.text_speed = "fast"
	assert_almost_eq(d._resolve_typing_speed(), 0.015, 0.001,
		"fast should resolve to ~0.015s per char (~67 cps)")

	GameState.text_speed = "instant"
	assert_eq(d._resolve_typing_speed(), 0.0,
		"instant must resolve to exactly 0.0 so the start path takes the bypass branch")

	# Unknown / corrupt setting must fall back to normal cadence, not 0.0
	# (which would silently turn into instant mode and confuse the player).
	GameState.text_speed = "xyz_corrupt_value"
	assert_almost_eq(d._resolve_typing_speed(), 0.03, 0.001,
		"unknown text_speed key must fall back to normal cadence, not bypass")

	GameState.text_speed = prev


func test_dialogue_start_path_uses_resolved_speed() -> void:
	# Source-level: confirm the start-of-line block actually calls
	# _resolve_typing_speed() and feeds the result to the timer / bypass.
	var text = _read(DIALOGUE_PATH)
	var idx = text.find("_typing_speed = _resolve_typing_speed()")
	assert_true(idx > -1,
		"dialogue start path must assign _typing_speed from _resolve_typing_speed()")
	# Window after that assignment must contain the instant-mode bypass and
	# the regular `_typing_timer.start(_typing_speed)` call so both code
	# paths stay live.
	var window = text.substr(idx, 600)
	assert_true(window.find("_typing_speed <= 0.0") > -1,
		"start path must branch on `_typing_speed <= 0.0` for the instant bypass")
	assert_true(window.find("_typing_timer.start(_typing_speed)") > -1,
		"start path must still start the typing timer with the resolved speed for non-instant presets")
