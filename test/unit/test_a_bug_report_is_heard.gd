extends GutTest

## F8 wrote a bug report, or failed to, with only a toast; it now clicks the screenshot shutter when the bundle lands and plays menu_error when it cannot be written.
## Both outcomes are driven through the real handler on a bare GameLoop, each into its own sandboxed directory, never the live user://feedback.

const GL := preload("res://src/GameLoop.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const SHUTTER := "screenshot_taken"
const REFUSAL := "menu_error"

var _root := ""


func before_each() -> void:
	_clear()
	_root = "user://__bugcue_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func after_each() -> void:
	_clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()
	_rm(_root)


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		DirAccess.remove_absolute(path)
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path + "/" + f)
	for sub in d.get_directories():
		_rm(path + "/" + sub)
	DirAccess.remove_absolute(path)


func _clear() -> void:
	SoundManager._ui_player.stream = null
	SoundManager._sfx_cooldowns.erase(SHUTTER)
	SoundManager._sfx_cooldowns.erase(REFUSAL)


func _file(key: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(key, {}) as Dictionary).get("file", ""))


func _heard() -> String:
	var s: AudioStream = SoundManager._ui_player.stream
	return s.resource_path.trim_prefix("res://") if s != null else ""


func _zips(dir: String) -> int:
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	return Array(d.get_files()).filter(func(f): return str(f).ends_with(".zip")).size()


func test_a_bug_report_that_lands_clicks_the_shutter() -> void:
	var out := _root + "/ok"
	var gl: Node = autofree(GL.new())
	gl._write_feedback_bundle(out)
	assert_eq(_zips(out), 1, "CONTROL: the bug report must actually land in the sandbox")
	assert_ne(_file(SHUTTER), "", "CONTROL: screenshot_taken is registered")
	assert_eq(_heard(), _file(SHUTTER), "F8 wrote a bug report and the shutter was not heard")


func test_a_bug_report_that_cannot_be_written_is_refused_out_loud() -> void:
	var blocker := _root + "/a_file"
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("not a directory")
	f.close()
	var out := blocker + "/feedback"
	var gl: Node = autofree(GL.new())
	gl._write_feedback_bundle(out)
	assert_eq(_zips(out), 0, "CONTROL: a directory under a FILE cannot hold the bundle, so the write must fail")
	assert_eq(_heard(), _file(REFUSAL), "F8 failed to write a bug report and menu_error was not heard")


func test_wiring_the_f8_key_still_writes_to_the_live_folder() -> void:
	var gl: Node = autofree(GL.new())
	var found: Dictionary = {}
	for m in gl.get_method_list():
		if m["name"] == "_write_feedback_bundle":
			found = m
	assert_eq((found.get("args", []) as Array).size(), 1, "CONTROL: _write_feedback_bundle takes the out_dir this test injects")
	assert_eq(found.get("default_args", []), [FeedbackBundle.DEFAULT_DIR], "the F8 key must still write to FeedbackBundle.DEFAULT_DIR")
