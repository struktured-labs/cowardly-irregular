extends GutTest

## `InputProfileManager.save_config` writes the player's profile, face convention and every custom
## binding. It opened the target directly:
##
##     var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
##
## ⛔ `WRITE` TRUNCATES ON OPEN. Between that call and `store_string` the file IS the 0-byte state,
## so the window is not a race against another writer — it is a race against this process dying, and
## the config is the thing that comes back empty. This lane fixed exactly that shape in
## `ControlsMenu._append_user_mapping`; this is its sibling, and the lane has only these two writes.
##
## ⚠️ THE CRASH ITSELF IS NOT ASSERTABLE — it needs the process to die mid-write, which a unit test
## cannot stage. What IS observable is the property staging buys: a save that cannot be written
## leaves the last good config untouched. Blocking the staging path makes the new code refuse; the
## direct form has no staging path to block, so it writes anyway and the old contents are gone.

## ⛔ READ THE PATH OFF THE SUBJECT, DO NOT RESTATE IT. This was a hardcoded
## "user://input/input_config.json" — the real constant is "user://input/controls.json", so every
## arm planted a sentinel in a file save_config never touches and measured an untouched decoy.
## The control caught it; without that arm "the old contents survived" would have been trivially,
## meaninglessly true.
var IPM_CONFIG: String = InputProfileManager.CONFIG_PATH

var _had: bool = false
var _saved: String = ""
var _saved_profile: String = ""
var _saved_nintendo: bool = false


## ⛔ THIS WRITES THE PLAYER'S REAL CONFIG PATH. run_tests.sh's net covers `user://script_exports/`,
## not this, so the bytes AND the in-memory fields are restored here.
func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	_saved_nintendo = InputProfileManager.nintendo_mode
	_had = FileAccess.file_exists(IPM_CONFIG)
	if _had:
		_saved = FileAccess.open(IPM_CONFIG, FileAccess.READ).get_as_text()


func after_all() -> void:
	_unblock()
	if _had:
		_write_raw(_saved)
	elif FileAccess.file_exists(IPM_CONFIG):
		DirAccess.open("user://input").remove(IPM_CONFIG.get_file())
	InputProfileManager.nintendo_mode = _saved_nintendo
	InputProfileManager.active_profile = _saved_profile


func _write_raw(text: String) -> void:
	DirAccess.open("user://").make_dir_recursive("input")
	var f := FileAccess.open(IPM_CONFIG, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _text() -> String:
	return FileAccess.open(IPM_CONFIG, FileAccess.READ).get_as_text() if FileAccess.file_exists(IPM_CONFIG) else ""


func _block() -> void:
	DirAccess.open("user://input").make_dir((IPM_CONFIG + ".new").get_file())


func _unblock() -> void:
	if DirAccess.dir_exists_absolute(IPM_CONFIG + ".new"):
		DirAccess.open("user://input").remove((IPM_CONFIG + ".new").get_file())


## ⛔ THE CONTROL, and the arm below is meaningless without it: an ordinary save must actually
## rewrite the file. If save_config never wrote at all, "the old contents survived" would be
## trivially true and would pin nothing.
func test_an_ordinary_save_really_does_rewrite_the_config() -> void:
	_write_raw('{"version": 2, "active_profile": "SENTINEL_NOT_A_PROFILE"}')
	InputProfileManager.save_config()
	var t: String = _text()
	assert_false("SENTINEL_NOT_A_PROFILE" in t,
		"CONTROL: save_config must replace the file's contents, or this file measures nothing")
	assert_true("active_profile" in t, "CONTROL: …and write a real config")
	assert_true(JSON.parse_string(t) is Dictionary, "CONTROL: …that parses as a Dictionary")


## ⛔ THE DEFECT. A save that cannot be completed must not be the thing that destroys the last good
## config — which is what opening the target directly guarantees, because the truncate happens first.
func test_a_save_that_cannot_be_written_leaves_the_last_good_config_intact() -> void:
	InputProfileManager.save_config()
	var good: String = _text()
	assert_true(JSON.parse_string(good) is Dictionary, "CONTROL: start from a real saved config")

	_block()
	InputProfileManager.nintendo_mode = not InputProfileManager.nintendo_mode
	InputProfileManager.save_config()
	var after: String = _text()
	_unblock()

	assert_eq(after, good,
		"the save could not be completed, and the config the player already had must survive that "
		+ "byte for byte. Opening the target with WRITE truncates it before anything is stored, so "
		+ "the failure path and the crash path both leave an empty or partial config — %d byte(s) left."
			% after.length())


## …and the ordinary path must leave no staging file for the next run to choose between.
func test_a_successful_save_leaves_no_staging_file() -> void:
	InputProfileManager.save_config()
	assert_false(FileAccess.file_exists(IPM_CONFIG + ".new"),
		"the staged file must be renamed into place, not left beside the real one")
	assert_true(JSON.parse_string(_text()) is Dictionary, "…and the real one must be complete")
