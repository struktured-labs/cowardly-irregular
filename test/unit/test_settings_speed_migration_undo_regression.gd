extends GutTest

## Settings-smoke find 2026-07-03: the speed_scale_v2 migration reset
## GameState.default_battle_speed to 0.5, but 40 lines later the legacy
## `default_battle_speed` key restore ran unconditionally and wrote the
## pre-v2 file's stale engine value back — silently undoing the
## migration. Symptom: Settings row highlighted "0.5x" while battles
## ran at the migrated "1x". The restore is now v2-gated.

var _backup: PackedByteArray = PackedByteArray()
var _had_file: bool = false


func before_each() -> void:
	_had_file = FileAccess.file_exists("user://settings.json")
	if _had_file:
		_backup = FileAccess.get_file_as_bytes("user://settings.json")


func after_each() -> void:
	if _had_file:
		var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	else:
		DirAccess.remove_absolute("user://settings.json")
	# rehydrate the real values so later tests don't inherit synthetic ones
	SaveSystem.load_settings()


func _write_settings(d: Dictionary) -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func test_pre_v2_stale_speed_no_longer_undoes_migration() -> void:
	_write_settings({"battle_speed_index": 4, "default_battle_speed": 0.25})
	SaveSystem.load_settings()
	assert_eq(GameState.default_battle_speed, 0.5,
		"pre-v2 file: migration's 0.5 must stand — the stale 0.25 restore was the bug")
	var scene_script = load("res://src/battle/BattleScene.gd")
	assert_eq(scene_script._battle_speed_index, 1,
		"pre-v2 file: battle-scene static resets to index 1 (label 1x)")


func test_v2_file_speed_restores_normally() -> void:
	_write_settings({"speed_scale_v2": true, "battle_speed_index": 2, "default_battle_speed": 1.0})
	SaveSystem.load_settings()
	assert_eq(GameState.default_battle_speed, 1.0)
	var scene_script = load("res://src/battle/BattleScene.gd")
	assert_eq(scene_script._battle_speed_index, 2)
