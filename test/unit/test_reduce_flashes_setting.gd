extends GutTest

## Feature 2026-07-05: "Reduce Flashes" accessibility setting (photosensitivity).
## When GameState.reduce_flashes is true, BattleScene suppresses its full-screen
## flashes (crits, group-attack combos, the corruption visual_glitch stutter,
## level-up) via the static _flashes_suppressed gate at both flash chokepoints.
## Plumbing mirrors color_blind_mode across GameState / SaveSystem / SettingsMenu.

const BS := preload("res://src/battle/BattleScene.gd")

var _saved: bool = false


func before_each() -> void:
	_saved = GameState.reduce_flashes


func after_each() -> void:
	GameState.reduce_flashes = _saved


func test_gate_off_by_default_value() -> void:
	GameState.reduce_flashes = false
	assert_false(BS._flashes_suppressed(), "flashes play when the setting is off")


func test_gate_suppresses_when_on() -> void:
	GameState.reduce_flashes = true
	assert_true(BS._flashes_suppressed(), "flashes are suppressed when the setting is on")


func test_both_flash_chokepoints_are_gated() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	for fn in ["func _flash_screen", "func _spawn_screen_flash"]:
		var i: int = src.find(fn)
		assert_gt(i, -1, "%s must exist" % fn)
		var body: String = src.substr(i, src.find("\nfunc ", i + 1) - i)
		assert_string_contains(body, "_flashes_suppressed()",
			"%s must gate on _flashes_suppressed()" % fn)


func test_settings_menu_registers_and_persists_toggle() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_string_contains(src, "\"id\": \"reduce_flashes\"", "the toggle must be a settings item")
	assert_string_contains(src, "func _save_reduce_flashes_setting", "the toggle must have a save fn")


func test_savesystem_roundtrips_setting() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_string_contains(src, "settings[\"reduce_flashes\"]", "SaveSystem must write the setting")
	assert_string_contains(src, "settings.has(\"reduce_flashes\")", "SaveSystem must read the setting")
