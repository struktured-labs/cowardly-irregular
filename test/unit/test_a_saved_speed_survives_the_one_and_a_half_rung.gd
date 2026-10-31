extends GutTest

## struktured 2026-10-30: "2x I find a bit hard to see animations but 1x feels too slow", so a 1.5x
## rung went in at index 1 and became the default. battle_speed_index is persisted, and every rung
## from 1 up moved one index — so a v3 file read against the new ladder would play every chosen
## speed one rung SLOWER (a picked 2x becomes 1.5x), silently. The rule he set: move a player off
## 0.25 only if they were on the old default; never override a speed someone chose.

const SETTINGS_PATH := "user://settings.json"
const BS := preload("res://src/battle/BattleScene.gd")

var _backup: PackedByteArray = PackedByteArray()
var _had_file := false
var _saved_index := 0
var _saved_default: float = 0.0


func before_each() -> void:
	_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	_had_file = not _backup.is_empty()
	_saved_index = BS._battle_speed_index
	_saved_default = GameState.default_battle_speed


func after_each() -> void:
	if _had_file:
		if FileAccess.get_file_as_bytes(SETTINGS_PATH) != _backup:
			var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(_backup)
				f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	BS._battle_speed_index = _saved_index
	GameState.default_battle_speed = _saved_default


func _load_v3(index: int, default_speed: float) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(f, "the fixture write must succeed, or the arm below tests nothing")
	if f == null:
		return
	f.store_string(JSON.stringify({"speed_scale_v2": true, "speed_scale_v3": true,
		"battle_speed_index": index, "default_battle_speed": default_speed}))
	f.close()
	SaveSystem.load_settings()


func test_every_chosen_v3_speed_keeps_its_engine_value() -> void:
	## Derived from the old ladder, so a rung added later reds here instead of shifting silently.
	var legacy: Array = Array(BS.LEGACY_V3_BATTLE_SPEEDS)
	assert_eq(legacy.size(), 7, "CONTROL: the v3 ladder had seven rungs")
	for v3 in range(1, legacy.size()):
		_load_v3(v3, legacy[v3])
		assert_eq(BS.BATTLE_SPEEDS[BS._battle_speed_index], legacy[v3],
			"a v3 file on rung %d (engine %s) must still run at engine %s" % [v3, legacy[v3], legacy[v3]])
		assert_eq(GameState.default_battle_speed, legacy[v3],
			"and the options row must name that same speed")


func test_the_old_default_moves_to_the_new_default() -> void:
	_load_v3(0, 0.25)
	assert_eq(BS._battle_speed_index, BS.DEFAULT_BATTLE_SPEED_INDEX, "v3 index 0 was the old default")
	assert_eq(GameState.default_battle_speed, 0.375, "so it moves to 1.5x")
	assert_eq(BS.BATTLE_SPEED_LABELS[BS._battle_speed_index], "1.5x", "and the readout says so")


func test_a_v4_file_is_read_as_written() -> void:
	## The marker is what stops a v4 index being re-migrated on the next boot.
	for i in BS.BATTLE_SPEEDS.size():
		BS._battle_speed_index = i
		GameState.default_battle_speed = BS.BATTLE_SPEEDS[i]
		SaveSystem.save_settings()
		BS._battle_speed_index = -1
		SaveSystem.load_settings()
		assert_eq(BS._battle_speed_index, i, "rung %d (%s) must round-trip unchanged" % [i, BS.BATTLE_SPEED_LABELS[i]])


func test_an_index_the_old_ladder_lacked_is_refused() -> void:
	assert_eq(SaveSystem.migrate_v3_speed_index(-1), -1)
	assert_eq(SaveSystem.migrate_v3_speed_index(7), -1, "v3 had no rung 7")
	assert_eq(SaveSystem.migrate_v3_speed_index(0), BS.DEFAULT_BATTLE_SPEED_INDEX)
