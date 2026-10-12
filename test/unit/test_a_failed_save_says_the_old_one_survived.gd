extends GutTest

## `_write_save_file` has three `return false` exits — the file would not open, the write came up
## short, the rename into place failed — and all three diagnose precisely, hand the diagnosis to
## `push_warning`, and return `false`. `save_game` then emitted the fixed string
##
##     save_failed.emit("Failed to write save file")
##
## to a toast that IS already wired (`GameLoop._on_any_save_failed`, tick 76). So the player who
## just pressed Save got a real notification carrying none of the diagnosis.
##
## 🔑 AND THE HALF BEING THROWN AWAY IS THE ONE THAT MATTERS MOST. Two of those push_warnings end
## "the previous save in slot %d is intact and this save did not happen." A player whose save has
## just failed needs to know their OLD save survived — that is the difference between "retry
## somewhere with space" and "my game is gone" — and that sentence never left the log.
##
## This is the write-side mirror of `last_import_reason()` / `last_export_reason()` on the share
## surface, and the same shape the load path has queued.
##
## ⚠️ REACHABILITY, forced rather than assumed, and NOT with a full disk. `SAVE_DIR` is a `const`
## so it cannot be redirected, but the failures do not need a redirect:
##   open   — a DIRECTORY at `<slot>.json.new`, so FileAccess.open(staged, WRITE) cannot open it
##   rename — a DIRECTORY at `<slot>.json`, so rename_absolute cannot replace it
## Both measured on this tree before this file was written. The SHORT-WRITE exit needs a genuinely
## full disk and is covered by shape only; this file does not pretend otherwise.
##
## Scratch slot 93 with cleanup both ways, the idiom
## `test_a_failed_save_leaves_the_last_one_standing` established at slot 94.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SAVE_SRC := "res://src/save/SaveSystem.gd"
const SLOT := 93
const SENTINEL := '{"sentinel":"PREVIOUS","keep":true}'


func _ss() -> Node:
	return get_node_or_null("/root/SaveSystem")


func _path() -> String:
	var ss := _ss()
	return ss._get_save_path(SLOT) if ss else ""


func _clear() -> void:
	var p := _path()
	if p == "":
		return
	for f in [p + ".new", p]:
		if DirAccess.dir_exists_absolute(f):
			DirAccess.remove_absolute(f)
		elif FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func before_each() -> void:
	_clear()
	var ss := _ss()
	if ss != null:
		ss._last_save_reason = ""


func after_each() -> void:
	## Both the slot and any staging litter, so a failed arm cannot seed the next one.
	_clear()
	var ss := _ss()
	if ss != null:
		ss._last_save_reason = ""


func _require_reason_api(ss) -> bool:
	## The absence of the API has to be an ASSERTION, not a call that explodes: a GDScript runtime
	## error ABORTS the arm and GUT scores it Passing (measured on the load branch — two arms
	## reported green having never reached their assertions).
	if ss.has_method("last_save_reason"):
		return true
	assert_true(false, "SaveSystem must expose last_save_reason() — this arm cannot run without it")
	return false


func _block_staged() -> bool:
	var staged := _path() + ".new"
	DirAccess.make_dir_recursive_absolute(staged)
	return DirAccess.dir_exists_absolute(staged)


func _block_destination() -> bool:
	DirAccess.make_dir_recursive_absolute(_path())
	return DirAccess.dir_exists_absolute(_path())


func test_control_a_normal_write_succeeds_and_records_no_reason() -> void:
	## Without this, every failure arm below could pass on a writer that refuses everything.
	var ss := _ss()
	assert_not_null(ss, "CONTROL: SaveSystem autoload must exist, or nothing here is a test")
	if ss == null:
		return
	if not _require_reason_api(ss):
		return
	var ok: bool = ss._write_save_file(SLOT, {"sentinel": "NEW", "n": 7})
	assert_true(ok, "CONTROL: a normal staged write must report success")
	assert_true(FileAccess.file_exists(_path()), "CONTROL: and the file must land at the slot path")
	assert_eq(str(ss.last_save_reason()), "", "CONTROL: a successful write must record no reason")


func test_control_the_blockers_really_block() -> void:
	## The two failure arms are only tests of the REASON if the write genuinely fails, and it must
	## fail for the reason this file thinks. Pinned separately so a blocker that stopped blocking
	## shows up as its own red rather than as a silent pass.
	var ss := _ss()
	if ss == null:
		return
	assert_true(_block_staged(), "CONTROL: a directory must be able to sit at the staged path")
	assert_false(ss._write_save_file(SLOT, {"x": 1}), "CONTROL: that must make the write fail")
	_clear()
	assert_true(_block_destination(), "CONTROL: a directory must be able to sit at the destination")
	assert_false(ss._write_save_file(SLOT, {"x": 2}), "CONTROL: that must make the write fail too")


func test_an_uncreatable_save_file_says_the_previous_one_survived() -> void:
	var ss := _ss()
	if ss == null:
		return
	if not _require_reason_api(ss):
		return
	if not _block_staged():
		return
	assert_false(ss._write_save_file(SLOT, {"sentinel": "NEW"}), "precondition: the write must fail")
	var why: String = str(ss.last_save_reason())
	assert_ne(why, "",
		"a failed write must record a reason — '' is what became the flat 'Failed to write save file'")
	assert_true(why.to_lower().find("intact") != -1,
		"and it MUST say the previous save survived, which is the half that never left the log: '%s'" % [why])
	assert_true(why.find(str(SLOT)) != -1,
		"and name the slot, since the player chose it by number: '%s'" % [why])


func test_a_save_that_cannot_be_moved_into_place_says_so_differently() -> void:
	## Three exits, three diagnoses. If they collapse to one sentence the fix has only moved the
	## flattening from save_game into _write_save_file.
	var ss := _ss()
	if ss == null:
		return
	if not _require_reason_api(ss):
		return
	if not _block_staged():
		return
	ss._write_save_file(SLOT, {"a": 1})
	var open_why: String = str(ss.last_save_reason())
	_clear()
	if not _block_destination():
		return
	assert_false(ss._write_save_file(SLOT, {"a": 2}), "precondition: the rename must fail")
	var rename_why: String = str(ss.last_save_reason())
	assert_ne(rename_why, "", "the rename exit must record a reason")
	assert_ne(open_why, rename_why,
		"two different failures must not read the same — that is the defect, one layer down: '%s'" % [open_why])
	assert_true(rename_why.to_lower().find("intact") != -1,
		"the rename exit must also say the previous save survived: '%s'" % [rename_why])


func test_the_sentence_is_TRUE_and_not_merely_present() -> void:
	## THE ARM THAT MAKES THE REST WORTH HAVING. Claiming "your previous save is intact" is only
	## an improvement if it is a fact. Plant a known save, force the failure that leaves the
	## destination alone, and require BOTH the message and the bytes.
	var ss := _ss()
	if ss == null:
		return
	if not _require_reason_api(ss):
		return
	var pre := FileAccess.open(_path(), FileAccess.WRITE)
	assert_not_null(pre, "CONTROL: could not plant a baseline save")
	if pre == null:
		return
	pre.store_string(SENTINEL)
	pre.close()
	assert_eq(FileAccess.get_file_as_string(_path()), SENTINEL,
		"CONTROL: the baseline must be on disk in full before the failed overwrite")

	if not _block_staged():
		return
	assert_false(ss._write_save_file(SLOT, {"sentinel": "NEW"}), "precondition: the write must fail")
	var why: String = str(ss.last_save_reason())
	assert_true(why.to_lower().find("intact") != -1, "precondition: the reason claims the old save is intact")
	assert_eq(FileAccess.get_file_as_string(_path()), SENTINEL,
		"the reason SAYS the previous save is intact and it is not — the message is now a lie, "
		+ "which is worse than the flat string it replaced")


func test_a_successful_save_clears_an_earlier_failures_reason() -> void:
	var ss := _ss()
	if ss == null:
		return
	if not _require_reason_api(ss):
		return
	if not _block_staged():
		return
	ss._write_save_file(SLOT, {"a": 1})
	assert_ne(str(ss.last_save_reason()), "", "precondition: the first write failed and set a reason")
	_clear()
	assert_true(ss._write_save_file(SLOT, {"a": 2}), "precondition: the second write succeeds")
	assert_eq(str(ss.last_save_reason()), "",
		"a successful save must clear the earlier failure's reason, got: '%s'" % [str(ss.last_save_reason())])


func _code() -> String:
	## The SHARED stripper. A presence assert over raw source is satisfied by prose about the
	## code, and this file's own comments quote the string it retired.
	return str(GdSource.split(FileAccess.get_file_as_string(SAVE_SRC))["code"])


func test_control_the_shared_stripper_keeps_code_and_removes_prose() -> void:
	## The helper requires its callers to prove a known code site survived (over-stripping and a
	## correct strip are the same green) and to floor the doc half (an empty doc side satisfies
	## "the prose is gone" by construction). SaveSystem.gd has docstrings, so both apply here.
	var raw: String = FileAccess.get_file_as_string(SAVE_SRC)
	var halves: Dictionary = GdSource.split(raw)
	var code: String = str(halves["code"])
	assert_gt(code.length(), 2000, "CONTROL: the strip must leave a code half behind")
	assert_gt(str(halves["doc"]).length(), 200,
		"CONTROL: SaveSystem.gd carries docstrings, so the doc half must be non-empty")
	assert_eq(code.count("\"\"\""), 0, "CONTROL: a docstring delimiter survived — parity desynced")
	assert_true(code.find("func _write_save_file(") != -1, "CONTROL: a known code site must survive")


func _body_of(code: String, signature: String) -> String:
	var start: int = code.find(signature)
	if start < 0:
		return ""
	var stop: int = code.find("\nfunc ", start + 1)
	return code.substr(start, stop - start) if stop > start else code.substr(start)


func test_every_write_failure_records_which_failure_it_was() -> void:
	## Shape, because the short-write exit needs a genuinely full disk. The floor is what stops
	## this arm going quietly vacuous if the function is renamed or restructured.
	var body: String = _body_of(_code(), "func _write_save_file(")
	assert_ne(body, "", "CONTROL: _write_save_file must still be a func of that name")
	if body == "":
		return
	assert_true(body.find("rename_absolute") != -1, "CONTROL: the extracted body must be _write_save_file's")
	assert_lt(body.length(), 4000, "CONTROL: the extraction must not have swallowed the rest of the file")

	var chunks: PackedStringArray = body.split("return false")
	var exits: int = chunks.size() - 1
	assert_gt(exits, 2, "CONTROL: _write_save_file had three `return false` exits; found %d" % [exits])
	if exits < 1:
		return
	var mute: Array = []
	for i in range(exits):
		## ⛔ COUNTED, NOT PREFIX-MATCHED. My first version looked for `= "the`, which is the
		## wording of two of the three reasons and not the third ("only part of the save...") — so
		## the arm red on correct code and named exit [1]. The clear at entry is
		## `_last_save_reason = ""`, so subtracting the empty assignment is what separates
		## "records a reason" from "clears the field", without caring how the sentence starts.
		var sets: int = chunks[i].count("_last_save_reason = \"") - chunks[i].count("_last_save_reason = \"\"")
		if sets <= 0:
			mute.append(i)
	assert_eq(mute, [],
		"these `return false` exits (0-based) diagnose a failure and drop it, so the player's "
		+ "toast can only say 'Failed to write save file': %s" % [str(mute)])


func test_the_save_failure_toast_carries_the_recorded_reason() -> void:
	## The manager recording it and the SIGNAL carrying it are two claims, and save_failed is the
	## one with a listener. Also pins the block path, which must not leave a stale disk reason
	## standing in for a refusal the player can act on differently.
	var body: String = _body_of(_code(), "func save_game(")
	assert_ne(body, "", "CONTROL: save_game must still be a func of that name")
	if body == "":
		return
	assert_true(body.find("_write_save_file(") != -1, "CONTROL: the extracted body must be save_game's")
	assert_false(body.find("save_failed.emit(\"Failed to write save file\")") != -1,
		"save_game still emits the flat string — the diagnosis _write_save_file computed is dropped")
	assert_true(body.find("save_failed.emit(_last_save_reason)") != -1,
		"the write-failure branch must emit the recorded reason")
	assert_true(body.find("_last_save_reason = \"\"") != -1,
		"save_game must clear the reason on entry, or an attempt inherits an older one")
	assert_true(body.find("_last_save_reason = reason") != -1,
		"the BLOCK path must record its reason too, or last_save_reason() describes the wrong attempt")
