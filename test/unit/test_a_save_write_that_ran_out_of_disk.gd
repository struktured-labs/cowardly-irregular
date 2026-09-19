extends GutTest

## Regression: @cowir-adhoc 2026-09-19 — `SaveSystem` STAGED its writes, guarded the open, guarded
## the rename, and still moved a TRUNCATED save over the previous good one, returning true.
##
## ⛔ THE STAGING DOES NOT COVER A SHORT WRITE. `rename` is a METADATA operation and SUCCEEDS on a
## full disk, so a partial payload is renamed into the slot and the caller shows "Saved!". The
## open-guard names "disk full" in its own comment and cannot see it: creating an empty file costs
## no blocks. The failure lands at `store_string`, whose return was never checked, and `close()`
## carried no `get_error()`.
##
## Found while the box sat at 1.7 GB falling, with auto-save on a 5-minute timer.
##
## 📌 NOT AN ORPHAN IDIOM — seven other staged writers in src/ already check it (GameLoop,
## AutobattleSystem, ScriptShareManager, AutogrindSystem, InputProfileManager, ControlsMenu,
## AutogrindUI), and AutogrindSystem's own comment names this exact hazard: "staging does NOT cover
## it: a rename moves a partial file into place just as happily". SaveSystem had TWO rename sites
## and zero get_error calls — the save slot and settings.json, which holds the BYOK API key.
##
## ⚠️ WHY THIS IS SOURCE-ANCHORED AND NOT BEHAVIOURAL, STATED SO NOBODY READS IT AS STRONGER THAN
## IT IS: making `store_string` fail needs a genuinely full filesystem or a quota, and neither is
## available to a headless test run. So this pins the ORDERING — the only property that makes the
## guard load-bearing — rather than observing a real short write.
## It asserts a RELATIONSHIP (the check precedes the rename), never a coincidental token, because a
## pin on the mere presence of "get_error" would pass with the check sitting AFTER the rename,
## where it cannot protect anything.

const SAVE_PATH := "res://src/save/SaveSystem.gd"


func _body_of(src: String, fn: String) -> String:
	var idx: int = src.find("func %s(" % fn)
	assert_gt(idx, -1, "FLOOR: %s must exist, or every assertion below is about nothing" % fn)
	var next: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, (next - idx) if next > -1 else 4000)


func _src() -> String:
	var s: String = FileAccess.get_file_as_string(SAVE_PATH)
	assert_ne(s, "", "PRECONDITION: SaveSystem.gd must be readable")
	return s


func test_the_save_write_is_checked_before_the_rename() -> void:
	# THE regression. Both indices are inside ONE function body, so a get_error() elsewhere in the
	# file cannot satisfy it — the defect was file-wide absence, and the fix must be in THIS frame.
	var body := _body_of(_src(), "_write_save_file")
	var chk: int = body.find("get_error()")
	var mv: int = body.find("rename_absolute")
	assert_gt(chk, -1,
		"_write_save_file must check the WRITE error — store_string's failure is the disk-full case, and the open-guard above it cannot see one")
	assert_gt(mv, -1, "FLOOR: the rename must still be there, or this arm compares against nothing")
	assert_lt(chk, mv,
		"the write check must come BEFORE the rename (check at %d, rename at %d) — rename is metadata and succeeds on a full disk, so a check after it has already destroyed the previous save" % [chk, mv])


func test_settings_are_checked_before_their_rename_too() -> void:
	# The sibling, and the more expensive one: settings.json holds the BYOK API key, and
	# load_settings' own docstring records a half-written one already seen in the wild.
	var body := _body_of(_src(), "save_settings")
	var chk: int = body.find("get_error()")
	var mv: int = body.find("rename_absolute")
	assert_gt(chk, -1, "save_settings must check the write error — same short-write hole as the save slot")
	assert_gt(mv, -1, "FLOOR: the settings rename must still be there")
	assert_lt(chk, mv,
		"the settings write check must precede its rename (check at %d, rename at %d)" % [chk, mv])


func test_a_failed_write_removes_the_staged_file() -> void:
	# The staged file must not survive a refused save: the next save truncates a same-named stage,
	# but settings.json's stage can hold an API key indefinitely if the player never saves again —
	# which is the asymmetry SaveSystem's own rename-failure comment already records.
	## ⛔ BOUNDED TO THE WINDOW [check, rename). Both functions ALREADY had a remove_absolute in
	## their RENAME-failure branch, so an unbounded search finds that one and passes however the
	## write-failure branch is written. Caught by mutation: deleting the write-side cleanup left
	## this arm green against the sibling occurrence.
	for fn in ["_write_save_file", "save_settings"]:
		var body := _body_of(_src(), fn)
		var chk: int = body.find("get_error()")
		var mv: int = body.find("rename_absolute")
		assert_gt(chk, -1, "FLOOR: %s must check the write error" % fn)
		assert_gt(mv, chk, "FLOOR: %s's rename must follow the check, or the window below is empty" % fn)
		var rm: int = body.find("remove_absolute", chk)
		assert_true(rm > -1 and rm < mv,
			"%s must remove the staged file ON THE WRITE FAILURE PATH (found at %d, window is %d..%d) — the rename-failure branch's own cleanup does not cover this case" % [fn, rm, chk, mv])


func test_the_guard_reports_rather_than_returning_success() -> void:
	# A silent refusal is the defect this replaces: the caller showed "Saved!" off a `true` return.
	# Pinned per-function so one loud site cannot cover for a silent sibling.
	## Same bounding as above, and for the same measured reason: both functions carry a
	## push_warning in their RENAME-failure branch, which satisfied an unbounded search while the
	## write-failure branch said nothing at all. The mutation that removed the write-side warning
	## left this arm GREEN until it was bounded.
	for fn in ["_write_save_file", "save_settings"]:
		var body := _body_of(_src(), fn)
		var chk: int = body.find("get_error()")
		var mv: int = body.find("rename_absolute")
		assert_gt(chk, -1, "FLOOR: %s must check the write error" % fn)
		assert_gt(mv, chk, "FLOOR: %s's rename must follow the check" % fn)
		var warn: int = body.find("push_warning", chk)
		assert_true(warn > -1 and warn < mv,
			"%s must SURFACE the failed write (found at %d, window is %d..%d) — the pre-fix path returned success and the UI said Saved!" % [fn, warn, chk, mv])
