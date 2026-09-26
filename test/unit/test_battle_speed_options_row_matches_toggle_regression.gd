extends GutTest

## The in-battle speed button and Settings → Battle Speed Default are one speed.
## Battle start applies BattleScene._battle_speed_index. The options row reads
## GameState.default_battle_speed. The button used to advance only the index, so
## after a few presses (or a save/load of that pair) the row still said "1x"
## while the next battle ran at 32x. 32x/64x were also missing from the row, so
## the closest chip was "16x".

const SETTINGS_PATH := "user://settings.json"
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const SettingsMenuScript := preload("res://src/ui/SettingsMenu.gd")
const BattleUIManagerScript := preload("res://src/battle/BattleUIManager.gd")

var _settings_backup: PackedByteArray = PackedByteArray()
var _had_settings: bool = false
var _orig_index: int = 0
var _orig_speed: float = 0.25
var _orig_time_scale: float = 1.0
var _had_speed_hint: bool = false


func before_each() -> void:
	_settings_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	_had_settings = not _settings_backup.is_empty()
	_orig_index = BattleSceneScript._battle_speed_index
	_orig_speed = GameState.default_battle_speed
	_orig_time_scale = Engine.time_scale
	_had_speed_hint = BattleSceneScript._hints_shown.has("speed_toggle")


func after_each() -> void:
	Engine.time_scale = _orig_time_scale
	if not _had_speed_hint:
		BattleSceneScript._hints_shown.erase("speed_toggle")
	if _had_settings:
		if FileAccess.get_file_as_bytes(SETTINGS_PATH) != _settings_backup:
			var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(_settings_backup)
				f.close()
		SaveSystem.load_settings()
	else:
		if FileAccess.file_exists(SETTINGS_PATH):
			DirAccess.remove_absolute(SETTINGS_PATH)
		BattleSceneScript._battle_speed_index = _orig_index
		GameState.default_battle_speed = _orig_speed


func _cycle_battle_speed(times: int) -> void:
	var scene: Node = BattleSceneScript.new()
	var ui := Node.new()
	ui.name = "UI"
	scene.add_child(ui)
	scene._ui_manager = BattleUIManagerScript.new(scene)
	for _i in times:
		scene._toggle_battle_speed()
	scene.free()


func _apply_battle_start_speed() -> void:
	var scene: Node = BattleSceneScript.new()
	scene._set_battle_time_scale(BattleSceneScript.BATTLE_SPEEDS[BattleSceneScript._battle_speed_index])
	scene.free()


func _speed_chip_text(menu: SettingsMenu) -> String:
	var control: Control = null
	for item in menu._settings_items:
		if str(item.get("id", "")) == "battle_speed":
			control = item["control"]
			break
	assert_not_null(control, "Battle Speed Default row must exist")
	if control == null:
		return ""
	var idx: int = menu.battle_speed_index
	var label := control.get_node_or_null("OptionsContainer/OptionBG_%d/OptionLabel_%d" % [idx, idx])
	assert_not_null(label, "options row has no chip for live speed index %d — the ladder is shorter than the button" % idx)
	if label == null:
		return ""
	return str(label.text)


func _open_settings() -> SettingsMenu:
	var menu: SettingsMenu = SettingsMenuScript.new()
	add_child_autofree(menu)
	return menu


func test_in_battle_speed_button_updates_the_options_row() -> void:
	BattleSceneScript._battle_speed_index = 0
	GameState.default_battle_speed = 0.25
	# 1x → 2x → 4x → 8x → 16x → 32x. 32x is past the old five-chip row.
	_cycle_battle_speed(5)
	_apply_battle_start_speed()
	var menu := _open_settings()
	assert_eq(BattleSceneScript._battle_speed_index, 5,
		"five presses land on 32x (index 5)")
	assert_eq(GameState.default_battle_speed, BattleSceneScript.BATTLE_SPEEDS[5],
		"the button must store the same engine speed the options row displays")
	assert_eq(Engine.time_scale, GameState.default_battle_speed,
		"the next battle must run at the speed the options row names")
	assert_eq(menu.battle_speed_index, BattleSceneScript._battle_speed_index,
		"opening Settings after the button must highlight that same step")
	assert_eq(_speed_chip_text(menu), "32x",
		"the highlighted chip must say 32x, not the old default and not a closest-match 16x")


func test_save_load_keeps_the_options_row_on_the_speed_battles_run() -> void:
	# The shape a save wrote when the button had reached 32x and the default was still 1x.
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(f, "fixture settings.json must be writable")
	if f == null:
		return
	f.store_string(JSON.stringify({
		"speed_scale_v2": true,
		"speed_scale_v3": true,
		"battle_speed_index": 5,
		"default_battle_speed": 0.25,
	}))
	f.close()
	SaveSystem.load_settings()
	_apply_battle_start_speed()
	var menu := _open_settings()
	assert_eq(BattleSceneScript._battle_speed_index, 5,
		"reload keeps the speed the battles were running at")
	assert_eq(GameState.default_battle_speed, BattleSceneScript.BATTLE_SPEEDS[5],
		"reload must not put the stale 1x default back on top of that speed")
	assert_eq(Engine.time_scale, GameState.default_battle_speed,
		"the battle after reload runs at the reloaded speed")
	assert_eq(_speed_chip_text(menu), BattleSceneScript.BATTLE_SPEED_LABELS[5],
		"after reload the options chip names the speed the next battle runs at")
