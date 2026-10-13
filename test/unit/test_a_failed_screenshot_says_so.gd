extends GutTest

## F12 ignored `save_png`'s return and fired the white flash regardless, so a screenshot that
## never landed looked exactly like one that did — and `print("[SCREENSHOT] Saved: %s")` named an
## absolute path that held no file, which is the line a player would go looking with.
##
## The sibling four lines below it in `_input` already got this right: F8's bundle says
## "Bug report FAILED — see the log" when `write_bundle` returns "". F12 is the asymmetric one.
##
## ⚠️ WHY THE WRITE IS A SEPARATE STATIC AND NOT TESTED THROUGH `_take_screenshot`: a headless run
## has no viewport texture, so `get_viewport().get_texture()` is null, `img` is null, and the
## function returns before it writes ANYTHING. An arm driving `_take_screenshot` would pass on
## every tree including the broken one. Taking the Image as an argument is the shape
## `FeedbackBundle.write_bundle` already uses, and `test_feedback_bundle_regression` drives it
## exactly this way.

const GL := preload("res://src/GameLoop.gd")
const GdSrc := preload("res://test/unit/helpers/gd_source.gd")

var _dir: String = "user://screenshot_arms"
var _blocker: String = "user://screenshot_arms_blocker"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	## A FILE where a parent directory would have to go. Nothing can be created beneath it, which
	## is a deterministic write failure that needs no permissions games.
	var f := FileAccess.open(_blocker, FileAccess.WRITE)
	if f != null:
		f.store_string("not a directory")
		f.close()


func after_all() -> void:
	var d := DirAccess.open(_dir)
	if d != null:
		for name in d.get_files():
			d.remove(name)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(_blocker)


func _shot(w: int = 8, h: int = 8) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


## Every way the writer can refuse, so the derived arm below cannot miss one.
func _refusals() -> Array:
	return [
		{"what": "a null image", "img": null, "dir": _dir},
		{"what": "an image with no pixels", "img": Image.new(), "dir": _dir},
		{"what": "a write that cannot land", "img": _shot(), "dir": _blocker + "/nested"},
	]


func test_control_a_real_image_is_written_and_reports_no_reason() -> void:
	## Without this every refusal arm below could pass on a writer that refuses everything.
	var got: Dictionary = GL.write_screenshot(_shot(), _dir)
	assert_ne(String(got.get("path", "")), "",
		"CONTROL: a valid image must be written, got reason '%s'" % [got.get("reason", "")])
	assert_eq(String(got.get("reason", "")), "",
		"CONTROL: and a successful write records no reason")
	assert_true(FileAccess.file_exists(String(got.get("path", ""))),
		"CONTROL: and the path it returns must actually hold a file: '%s'" % [got.get("path", "")])


func test_a_write_that_fails_reports_no_path() -> void:
	## THE ORIGINAL DEFECT. The old code called save_png, dropped the Error, and carried on to the
	## flash and the "Saved:" line.
	var got: Dictionary = GL.write_screenshot(_shot(), _blocker + "/nested")
	assert_eq(String(got.get("path", "")), "",
		"a screenshot that could not be written must NOT come back with a path")


func test_every_refusal_records_a_reason() -> void:
	## Derived over all three exits rather than pinning one, so a later exit added without a
	## reason reds here instead of reaching the player as a blank "Screenshot failed — ".
	for case in _refusals():
		var got: Dictionary = GL.write_screenshot(case["img"], case["dir"])
		assert_eq(String(got.get("path", "")), "",
			"%s must be refused" % [case["what"]])
		assert_ne(String(got.get("reason", "")), "",
			"%s must record a reason, not leave the player a blank failure" % [case["what"]])


func test_an_unwritable_folder_says_that_rather_than_blaming_the_picture() -> void:
	## The two failures are not interchangeable to a player: one is "your disk", the other is
	## "there was nothing to capture". Reds if a future refactor collapses them into one message.
	var disk: String = String(GL.write_screenshot(_shot(), _blocker + "/nested").get("reason", ""))
	var empty: String = String(GL.write_screenshot(null, _dir).get("reason", ""))
	## ⚠️ An EMPTY-but-non-null image needs its own case, and it is the one that caught a real gap.
	## `save_png` refuses a 0x0 image on its own (err=1, measured), so dropping the `is_empty()`
	## check still leaves the frame REFUSED — just explained as a disk problem. An arm that only
	## passes `null` sees nothing wrong with that; mutating `is_empty()` away red 0 arms until this
	## line existed.
	var blank: String = String(GL.write_screenshot(Image.new(), _dir).get("reason", ""))
	assert_ne(disk, empty, "a write failure and an empty frame must not give the same reason")
	assert_ne(disk, blank,
		"a 0x0 frame must not be explained as a disk failure, got '%s'" % [blank])
	assert_true(blank.to_lower().find("nothing on screen") != -1,
		"a 0x0 frame must say there was nothing to capture: '%s'" % [blank])
	## Specific on purpose, and it names the exit: this reaches `save_png`'s error return — the
	## check whose absence was the defect — rather than a nicer-worded branch above it.
	assert_true(disk.to_lower().find("could not be written") != -1,
		"a blocked write must say the FILE could not be written: '%s'" % [disk])
	assert_true(empty.to_lower().find("nothing on screen") != -1,
		"an empty frame must say there was nothing to capture: '%s'" % [empty])


func test_a_successful_write_lands_in_the_folder_it_was_given() -> void:
	## Pins that out_dir is honoured — without it the arms above could all be passing against the
	## player's real user://screenshots while claiming to use a scratch folder.
	var got: Dictionary = GL.write_screenshot(_shot(), _dir)
	var want: String = ProjectSettings.globalize_path(_dir)
	assert_true(String(got.get("path", "")).begins_with(want),
		"the file must be written under the folder passed in: '%s' is not under '%s'" % [
			got.get("path", ""), want])


func test_wiring_the_f12_handler_refuses_before_it_flashes() -> void:
	## ⚠️ A WIRING PIN, NOT A BEHAVIOURAL ONE. `_take_screenshot` cannot be driven headless (no
	## viewport texture), so this reads the source rather than claiming to observe the flash. It
	## defends the one thing the arms above cannot: that the handler ACTS on the refusal instead of
	## discarding it, which is exactly the shape the bug had.
	var code: String = GdSrc.code_of("res://src/GameLoop.gd")
	assert_ne(code, "", "CONTROL: GameLoop source must be readable with comments stripped")
	var start: int = code.find("func _take_screenshot(")
	assert_gt(start, -1, "CONTROL: _take_screenshot must exist")
	if start < 0:
		return
	var end: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, end - start) if end > start else code.substr(start)

	var call_at: int = body.find("write_screenshot(")
	var flash_at: int = body.find("ColorRect.new()")
	assert_gt(call_at, -1, "the handler must go through write_screenshot, not call save_png itself")
	assert_eq(body.find("save_png"), -1,
		"and must not write the PNG itself — that is the half that dropped the Error")
	assert_gt(flash_at, -1, "CONTROL: the success flash must still be there")

	## ⚠️ Searched from the write call, NOT from the start of the body. `_take_screenshot` toasts
	## in TWO branches — the no-viewport one above the write, and the failed-write one below it —
	## so a search from 0 finds the first and reports the second as wired no matter what. Measured:
	## replacing the write-failure toast with a bare push_warning left a from-0 search GREEN.
	var toast_at: int = body.find("Toast.show_warning", call_at)
	assert_gt(toast_at, -1,
		"a failed WRITE must tell the player — the no-viewport branch above does not count")
	assert_lt(toast_at, flash_at,
		"and it must be reported before the success flash is built")
