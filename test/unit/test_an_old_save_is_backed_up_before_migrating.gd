extends GutTest

## cowir-main 20754: the spectrum curve rewrites an existing save's stats, so the first load of an old save copies it aside byte-for-byte.
## Reverting the build plus restoring `<save>.pre-v757` must undo the migration completely.

const SLOT := 87


func _path() -> String:
	return SaveSystem._get_save_path(SLOT)


func _backup() -> String:
	return _path() + SaveSystem.PRE_SPECTRUM_BACKUP_SUFFIX


func _write(text: String) -> void:
	SaveSystem._ensure_save_directory()
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _old_save_text(hp: int) -> String:
	# Odd spacing on purpose: a re-serialised copy would not reproduce it, only a byte copy does.
	return '{ "game_state":{"player_party":[{"combatant_name":"Hero","max_hp": %d,"current_hp":%d,"attack":420,"stat_scale":10}]} }' % [hp, hp]


func _clean() -> void:
	for p in [_path(), _backup()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func before_each() -> void:
	_clean()


func after_each() -> void:
	_clean()


func test_the_first_load_backs_up_the_original_bytes() -> void:
	var original := _old_save_text(2080)
	_write(original)
	var data: Dictionary = SaveSystem._read_save_file(SLOT)
	assert_eq(int(data["game_state"]["player_party"][0]["max_hp"]), 208, "CONTROL: the load migrated the stats")
	assert_true(FileAccess.file_exists(_backup()), "an old save was migrated with no backup beside it")
	assert_eq(FileAccess.get_file_as_string(_backup()), original, "the backup is not the original bytes")
	assert_eq(FileAccess.get_file_as_string(_path()), original, "loading must not rewrite the save itself")


func test_a_second_load_never_touches_the_backup() -> void:
	var first := _old_save_text(2080)
	_write(first)
	SaveSystem._read_save_file(SLOT)
	_write(_old_save_text(3000))
	SaveSystem._read_save_file(SLOT)
	assert_eq(FileAccess.get_file_as_string(_backup()), first, "a later load overwrote the first backup")


func test_a_current_save_is_not_backed_up() -> void:
	_write('{"game_state":{"player_party":[{"combatant_name":"Hero","max_hp":66,"stat_scale":%d}]}}' % Combatant.STAT_SCALE)
	SaveSystem._read_save_file(SLOT)
	assert_false(FileAccess.file_exists(_backup()), "a save already at the current scale needs no backup")
