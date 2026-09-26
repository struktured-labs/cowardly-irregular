extends GutTest

## Continue used to copy the save's Dynamic Dialogue bit onto the menu and leave
## LLMService on the Settings value. The toggle and the NPCs disagreed, and the
## next settings write stored the menu's lie.

const SETTINGS_PATH := "user://settings.json"
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")

var _backup: PackedByteArray = PackedByteArray()
var _had_file: bool = false
var _orig_llm: bool = true
var _orig_svc: bool = true
var _orig_dash: bool = false
var _orig_index: int = 0
var _orig_speed: float = 0.25


func before_each() -> void:
	_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	_had_file = not _backup.is_empty()
	_orig_llm = GameState.llm_enabled
	var svc := _llm()
	_orig_svc = bool(svc.llm_enabled) if svc != null else true
	_orig_dash = GameState.dash_always_on
	_orig_index = BattleSceneScript._battle_speed_index
	_orig_speed = GameState.default_battle_speed


func after_each() -> void:
	if _had_file:
		if FileAccess.get_file_as_bytes(SETTINGS_PATH) != _backup:
			var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(_backup)
				f.close()
		SaveSystem.load_settings()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	GameState.llm_enabled = _orig_llm
	GameState.dash_always_on = _orig_dash
	GameState.default_battle_speed = _orig_speed
	BattleSceneScript._battle_speed_index = _orig_index
	var svc := _llm()
	if svc != null:
		svc.llm_enabled = _orig_svc


func _llm() -> Node:
	return get_node_or_null("/root/LLMService")


func _write_settings_off() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(f, "fixture settings.json must be writable")
	if f == null:
		return
	f.store_string(JSON.stringify({
		"speed_scale_v3": true,
		"battle_speed_index": _orig_index,
		"default_battle_speed": _orig_speed,
		"llm_enabled": false,
	}))
	f.close()


## A save made while dialogue was on must not undo Settings, and must not leave the switch lying.
func test_continue_does_not_turn_dynamic_dialogue_back_on() -> void:
	var svc := _llm()
	assert_not_null(svc, "LLMService autoload must exist — it is the switch NPCs actually read")
	_write_settings_off()
	SaveSystem.load_settings()
	assert_false(GameState.llm_enabled, "the settings file's off must land on the menu value")
	assert_false(bool(svc.llm_enabled), "the settings file's off must land on the language model")
	var data: Dictionary = GameState._create_save_data()
	data["llm_enabled"] = true
	data["dash_always_on"] = not _orig_dash
	GameState._apply_save_data(data)
	assert_ne(GameState.dash_always_on, _orig_dash,
		"control: the load reached the settings block, so a green here is not an abort before it")
	assert_false(GameState.llm_enabled,
		"Continue must leave Dynamic Dialogue off after the player turned it off in Settings")
	assert_false(bool(svc.llm_enabled),
		"the language model must stay off with the menu — Continue was turning only the menu back on")


## A machine with no settings file yet still adopts the save, on the menu and on the model.
func test_a_save_with_no_settings_file_reaches_the_language_model() -> void:
	var svc := _llm()
	assert_not_null(svc, "LLMService autoload must exist")
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	GameState.llm_enabled = false
	svc.llm_enabled = false
	var data: Dictionary = GameState._create_save_data()
	data["llm_enabled"] = true
	data["dash_always_on"] = not GameState.dash_always_on
	var dash_at_apply: bool = GameState.dash_always_on
	GameState._apply_save_data(data)
	assert_ne(GameState.dash_always_on, dash_at_apply,
		"control: the load reached the settings block")
	assert_true(GameState.llm_enabled,
		"with no settings.json, Continue adopts the save's Dynamic Dialogue choice")
	assert_true(bool(svc.llm_enabled),
		"that choice has to reach the language model, not only the menu")
