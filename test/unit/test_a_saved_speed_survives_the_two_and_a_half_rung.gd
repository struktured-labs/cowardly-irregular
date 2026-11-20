extends GutTest

## struktured 2026-11-15: "add the rung for now" -- a 2.5x rung went in between 2x and 4x (speed_scale_v5).
## battle_speed_index is persisted, and every rung from 4x up moved one index, so a v4 file read against
## the new ladder would play 4x and faster one rung SLOWER (a picked 4x becomes 2.5x), silently.
## The default did not move. Never override a speed someone chose.

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


func _load_v4(index: int, default_speed: float) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(f, "the fixture write must succeed, or the arm below tests nothing")
	if f == null:
		return
	f.store_string(JSON.stringify({"speed_scale_v2": true, "speed_scale_v3": true, "speed_scale_v4": true,
		"battle_speed_index": index, "default_battle_speed": default_speed}))
	f.close()
	SaveSystem.load_settings()


func test_the_ladder_carries_two_and_a_half() -> void:
	var i: int = BS.BATTLE_SPEED_LABELS.find("2.5x")
	assert_gt(i, -1, "the 2.5x rung is on the ladder")
	if i < 0:
		return
	assert_almost_eq(BS.BATTLE_SPEEDS[i], 0.625, 0.0001, "labels are engine*4, so 2.5x is engine 0.625")
	assert_eq(BS.BATTLE_SPEED_LABELS[i - 1], "2x", "it sits directly above 2x")
	assert_eq(BS.BATTLE_SPEED_LABELS[i + 1], "4x", "and directly below 4x")
	assert_eq(BS.BATTLE_SPEEDS.size(), BS.BATTLE_SPEED_LABELS.size(), "every rung names itself")


func test_every_chosen_v4_speed_keeps_its_engine_value() -> void:
	## Derived from the old ladder, so a rung added later reds here instead of shifting silently.
	var legacy: Array = Array(BS.LEGACY_V4_BATTLE_SPEEDS)
	assert_eq(legacy.size(), 8, "CONTROL: the v4 ladder had eight rungs")
	for v4 in legacy.size():
		_load_v4(v4, legacy[v4])
		assert_eq(BS.BATTLE_SPEEDS[BS._battle_speed_index], legacy[v4],
			"a v4 file on rung %d (engine %s) must still run at engine %s" % [v4, legacy[v4], legacy[v4]])
		assert_eq(GameState.default_battle_speed, legacy[v4], "and the options row must name that same speed")


func test_a_v4_four_x_does_not_become_two_and_a_half() -> void:
	## The CONTROL for the arm above: without the v5 migration, v4 index 3 reads as today's index 3.
	assert_ne(BS.BATTLE_SPEEDS[3], BS.LEGACY_V4_BATTLE_SPEEDS[3], "CONTROL: index 3 changed meaning, so the migration is load-bearing")
	_load_v4(3, 1.0)
	assert_eq(BS.BATTLE_SPEED_LABELS[BS._battle_speed_index], "4x", "a v4 player on 4x stays on 4x")


func test_a_v5_file_is_read_as_written() -> void:
	## The marker is what stops a v5 index being re-migrated on the next boot.
	for i in BS.BATTLE_SPEEDS.size():
		BS._battle_speed_index = i
		GameState.default_battle_speed = BS.BATTLE_SPEEDS[i]
		SaveSystem.save_settings()
		BS._battle_speed_index = -1
		SaveSystem.load_settings()
		assert_eq(BS._battle_speed_index, i, "rung %d (%s) must round-trip unchanged" % [i, BS.BATTLE_SPEED_LABELS[i]])


func test_an_index_the_v4_ladder_lacked_is_refused() -> void:
	assert_eq(SaveSystem.migrate_v4_speed_index(-1), -1)
	assert_eq(SaveSystem.migrate_v4_speed_index(BS.LEGACY_V4_BATTLE_SPEEDS.size()), -1)
