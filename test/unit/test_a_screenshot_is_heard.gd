extends GutTest

## F12 saved a screenshot with only a white flash and failed with only a toast; a shot that landed now clicks a shutter, one that did not plays menu_error.
## The no-viewport refusal is driven on a bare GameLoop kept off the tree; the write-failure and success sites are pinned in source, since no headless run has pixels to capture.

const GL := preload("res://src/GameLoop.gd")
const GdSrc := preload("res://test/unit/helpers/gd_source.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const SHUTTER := "screenshot_taken"
const REFUSAL := "menu_error"


func before_each() -> void:
	_clear()


func after_each() -> void:
	_clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


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


func _body() -> String:
	var code: String = GdSrc.code_of("res://src/GameLoop.gd")
	var start: int = code.find("func _take_screenshot(")
	if start < 0:
		return ""
	var end: int = code.find("\nfunc ", start + 1)
	return code.substr(start, end - start) if end > start else code.substr(start)


func test_the_shutter_is_authored_and_is_not_the_refusal() -> void:
	var f := _file(SHUTTER)
	assert_ne(f, "", "screenshot_taken is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "screenshot_taken names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.15,
		"screenshot_taken does not load as a real stream")
	assert_ne(f, _file(REFUSAL), "the shutter and the refusal must be different sounds")


func test_a_screenshot_with_nothing_to_capture_is_refused_out_loud() -> void:
	var gl: Node = autofree(GL.new())
	assert_null(gl.get_viewport(), "CONTROL: the bare GameLoop must be off the tree, so there is nothing to capture")
	gl._take_screenshot()
	assert_eq(_heard(), _file(REFUSAL), "F12 with nothing on screen failed and was not heard as menu_error")


func test_the_cue_says_landed_or_refused() -> void:
	var gl: Node = autofree(GL.new())
	gl._screenshot_cue(true)
	assert_eq(_heard(), _file(SHUTTER), "a screenshot that landed did not click the shutter")
	_clear()
	gl._screenshot_cue(false)
	assert_eq(_heard(), _file(REFUSAL), "a screenshot that failed did not play menu_error")


## A WIRING PIN: headless has no viewport texture, so the write-failure and success branches are read, not run.
func test_wiring_each_branch_of_f12_calls_its_cue() -> void:
	var body := _body()
	assert_ne(body, "", "CONTROL: _take_screenshot must exist")
	if body == "":
		return
	var write_at: int = body.find("write_screenshot(")
	var saved_at: int = body.find("[SCREENSHOT] Saved")
	var flash_at: int = body.find("ColorRect.new()")
	assert_true(write_at > -1 and saved_at > write_at and flash_at > saved_at,
		"CONTROL: the write, the Saved line and the flash must appear in that order")
	var refused_after_write: int = body.find("_screenshot_cue(false)", write_at)
	assert_true(refused_after_write > write_at and refused_after_write < saved_at,
		"a screenshot that could not be WRITTEN must play the refusal before the Saved line")
	var landed_at: int = body.find("_screenshot_cue(true)")
	assert_true(landed_at > saved_at and landed_at < flash_at,
		"a screenshot that landed must click the shutter after it is saved, beside the flash")
	assert_eq(body.count("_screenshot_cue(true)"), 1, "the shutter must have exactly one call site, on the success path")
