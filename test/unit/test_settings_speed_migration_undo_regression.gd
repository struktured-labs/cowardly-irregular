extends GutTest

## Settings-smoke find 2026-07-03: the speed_scale_v2 migration reset
## GameState.default_battle_speed to 0.5, but 40 lines later the legacy
## `default_battle_speed` key restore ran unconditionally and wrote the
## pre-v2 file's stale engine value back — silently undoing the
## migration. Symptom: Settings row highlighted "0.5x" while battles
## ran at the migrated "1x". The restore is now v2-gated.

const SETTINGS_PATH := "user://settings.json"

var _backup: PackedByteArray = PackedByteArray()
var _had_file: bool = false


## ⛔ THIS TEARDOWN REWROTE THE PLAYER'S settings.json ON EVERY RUN WITH NOTHING TO RESTORE, and
## `FileAccess.open(…, WRITE)` TRUNCATES before store_buffer lands. Measured in a virgin sandbox with
## no runner net — the only cell where this teardown is the sole actor: seeded file, content
## identical, mtime 09-11 -> 09-17. Two ways the old shape loses data rather than just touching it:
## `_had_file` guarded on EXISTENCE while `get_file_as_bytes` returns EMPTY on a read error against a
## file that exists, so the restore wrote zero bytes; and a crash between the open and the store left
## it truncated with nothing to repair it. settings.json IS netted by run_tests.sh's root-json arm,
## which restores with `cp -a` — so through the wrapper this was invisible to BOTH a hash and an
## mtime, and a bare or raw-runner invocation has no net at all. (cowir-music 12742, same class.)
func before_each() -> void:
	_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	## CONTENT, not existence: an unreadable file and an absent one both yield an empty snapshot, and
	## neither may be written back over whatever is actually there.
	_had_file = not _backup.is_empty()


func after_each() -> void:
	if _had_file:
		## ⚠️ NOT A SAVING FOR THIS FILE — every arm here writes a fixture, so the compare always
		## differs and the restore always fires. Measured: seeded sandbox, mtime moves before AND
		## after this change, content identical both times. It is here so a future read-only arm
		## cannot silently start re-stamping his settings, and so the compare documents that the
		## restore is conditional on real divergence rather than on the file merely existing.
		if FileAccess.get_file_as_bytes(SETTINGS_PATH) != _backup:
			var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(_backup)
				f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		## We had nothing to restore, so anything here is this run's fixture.
		DirAccess.remove_absolute(SETTINGS_PATH)
	# rehydrate the real values so later tests don't inherit synthetic ones
	SaveSystem.load_settings()


func _write_settings(d: Dictionary) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(f, "the fixture write must succeed, or the arm below tests nothing")
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


func test_pre_v2_stale_speed_no_longer_undoes_migration() -> void:
	_write_settings({"battle_speed_index": 4, "default_battle_speed": 0.25})
	SaveSystem.load_settings()
	assert_eq(GameState.default_battle_speed, 0.25,
		"pre-v3 file: migration's 0.25 must stand — a stale engine value must not undo it")
	var scene_script = load("res://src/battle/BattleScene.gd")
	assert_eq(scene_script._battle_speed_index, 0,
		"pre-v3 file: battle-scene static resets to index 0 (label 1x)")


func test_v2_file_speed_restores_normally() -> void:
	_write_settings({"speed_scale_v2": true, "speed_scale_v3": true, "battle_speed_index": 2, "default_battle_speed": 1.0})
	SaveSystem.load_settings()
	assert_eq(GameState.default_battle_speed, 1.0)
	var scene_script = load("res://src/battle/BattleScene.gd")
	assert_eq(scene_script._battle_speed_index, 2)
