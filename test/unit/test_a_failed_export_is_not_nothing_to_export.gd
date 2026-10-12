extends GutTest

## `_write_export` has three `return ""` exits — the file would not open, the write came up
## short, the rename into place failed — and each one computed a precise reason, pushed it to
## `push_warning`, and returned "". The three public export functions return "" too, for the
## OPPOSITE situation: there was nothing to write.
##
## So "" meant both "your disk is full" and "you have nothing to share", and both export UIs
## resolved it the same way:
##
##   AutogrindUI._export_scripts          "Nothing to export."
##   AutobattleGridEditor._export_script  "Nothing to export"
##
## In the grid editor that sentence is said about a script the player is looking at on screen,
## one keypress after they edited it. `_write_export`'s own comment already argued the point —
## "Export failures matter: the player triggered the export expecting a file to land. Silent
## failure breaks the share workflow (they hand a friend a path that doesn't exist)" — and the
## repair it got was a push_warning, which is the log the player never reads.
##
## This is the import channel's mirror image. `last_import_errors` exists because the same
## shape was fixed three times on the read side (the bundle applier in .655, the autogrind
## applier in .657, the file reader in .658); `last_export_errors` is the write side of it.
##
## ⚠️ REACHABILITY, checked rather than assumed, and one assumption of mine was WRONG. The
## open-failure exit is forced here by making the export directory unwritable in the way a
## player's really is — something else is sitting at that path. The short-write and failed-rename
## exits need a full disk and a hostile filesystem respectively, so they are covered by shape,
## behind a floor and a control.
##
## ⛔ AND `export_character_script`'s empty-script exit IS UNREACHABLE. I wrote an arm asserting
## an unknown character id exports nothing; it failed, because `get_character_script` calls
## `_ensure_character_profiles` and then falls back to `create_default_character_script`, so it
## NEVER returns {} — an unknown id gets a freshly minted default and the export succeeds. The
## arm is gone rather than weakened, the reason on that exit stays as defence with no behavioural
## cover claimed for it, and the shape arm is the only thing judging it. Calling that function
## from a test also mints a profile in `user://autobattle/profiles.json`, a second store this
## file has no net for, which is the other reason not to.
##
## No autoload state is written: the success and failure arms call `_write_export` directly,
## and the "nothing to write" arms use an unknown character id and an empty party. EXPORT_DIR
## is redirected per process as the three sibling share tests do.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")
const MANAGER_SRC := "res://src/autobattle/ScriptShareManager.gd"
const AUTOGRIND_UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"
const GRID_EDITOR_SRC := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _prior_export_dir: String = ""
var _good_dir: String = ""
var _blocked_dir: String = ""
var _blocker_file: String = ""


func before_all() -> void:
	_prior_export_dir = SSM.EXPORT_DIR
	_good_dir = "user://export_reason_test_%d/" % OS.get_process_id()
	_blocker_file = "user://export_reason_blocked_%d" % OS.get_process_id()
	_blocked_dir = _blocker_file + "/"
	DirAccess.make_dir_recursive_absolute(_good_dir)
	## A plain FILE standing where the export directory would go. make_dir fails, and so does
	## opening anything beneath it — which is what an unwritable export folder looks like from
	## inside _write_export.
	var f := FileAccess.open(_blocker_file, FileAccess.WRITE)
	if f != null:
		f.store_string("not a directory")
		f.close()


func after_all() -> void:
	## Restore FIRST, so a failure below cannot leak the override into test_script_share, which
	## pins the production default.
	SSM.EXPORT_DIR = _prior_export_dir
	SSM.last_export_errors = []
	if DirAccess.dir_exists_absolute(_good_dir):
		for fname in DirAccess.get_files_at(_good_dir):
			DirAccess.remove_absolute(_good_dir + str(fname))
		DirAccess.remove_absolute(_good_dir)
	if FileAccess.file_exists(_blocker_file):
		DirAccess.remove_absolute(_blocker_file)


func before_each() -> void:
	SSM.EXPORT_DIR = _good_dir
	SSM.last_export_errors = []


func after_each() -> void:
	SSM.EXPORT_DIR = _good_dir
	SSM.last_export_errors = []


func _payload() -> Dictionary:
	return {"version": 1, "type": "autogrind_rules", "rules": [{"conditions": [], "actions": []}]}


func test_control_a_writable_folder_writes_the_file_and_records_no_reason() -> void:
	## Without this, every refusal arm below could pass on a writer that refuses everything.
	assert_true(DirAccess.dir_exists_absolute(_good_dir), "CONTROL: the probe export dir must exist")
	var path: String = SSM._write_export("probe_control.json", _payload())
	assert_ne(path, "", "CONTROL: a writable folder must produce a path")
	assert_true(FileAccess.file_exists(path), "CONTROL: and a file must actually be there")
	assert_eq(SSM.last_export_reason(), "", "CONTROL: a successful write must record no reason")
	assert_false(FileAccess.file_exists(path + ".new"), "CONTROL: the staged file must not survive")


func test_control_the_blocker_really_blocks() -> void:
	## The arm below is only a test of the REASON if the write genuinely fails. Pinned separately
	## so a blocker that stopped blocking shows up as its own red rather than as a silent pass.
	assert_true(FileAccess.file_exists(_blocker_file),
		"CONTROL: a plain file must be sitting where the export directory would go")
	assert_false(DirAccess.dir_exists_absolute(_blocked_dir),
		"CONTROL: and that path must not be a directory")


func test_an_unwritable_export_folder_says_so_instead_of_nothing_to_export() -> void:
	SSM.EXPORT_DIR = _blocked_dir
	var path: String = SSM._write_export("probe_blocked.json", _payload())
	assert_eq(path, "", "precondition: an unwritable folder must fail the export")
	var why: String = SSM.last_export_reason()
	assert_ne(why, "",
		"a failed WRITE must record a reason — '' is what both UIs render as 'Nothing to export'")
	assert_true(why.find("probe_blocked.json") != -1,
		"and it must name the file the player was trying to produce: '%s'" % [why])
	assert_false(why.to_lower().find("nothing") != -1,
		"a write failure is the opposite of having nothing to write: '%s'" % [why])


func test_an_empty_party_says_there_is_nothing_to_bundle() -> void:
	var out: String = SSM.export_all_scripts([])
	assert_eq(out, "", "precondition: an empty party produces no bundle")
	var why: String = SSM.last_export_reason()
	assert_ne(why, "", "the empty-bundle exit must record a reason")
	assert_true(why.to_lower().find("bundle") != -1,
		"and it must name what was not produced: '%s'" % [why])


func test_a_failed_write_and_an_empty_source_are_distinguishable() -> void:
	## THE WHOLE DEFECT IN ONE ARM. Both situations returned "" and both UIs printed the same
	## sentence, so a player could not tell "you have nothing to share" from "your disk is full".
	var out: String = SSM.export_all_scripts([])
	var empty_why: String = SSM.last_export_reason()

	SSM.EXPORT_DIR = _blocked_dir
	SSM._write_export("probe_distinguish.json", _payload())
	var failed_why: String = SSM.last_export_reason()

	assert_eq(out, "", "precondition: the empty-source path returned ''")
	assert_ne(empty_why, "", "precondition: the empty-source path recorded a reason")
	assert_ne(failed_why, "", "precondition: the failed-write path recorded a reason")
	assert_ne(empty_why, failed_why,
		"having nothing to export and failing to write it must not read the same: '%s'" % [empty_why])


func test_a_successful_export_clears_an_earlier_failures_reason() -> void:
	## The clear sits at the entry of _write_export AND of every public export function, so a
	## later success cannot be captioned by an earlier failure. Pinned through this path.
	SSM.EXPORT_DIR = _blocked_dir
	SSM._write_export("probe_stale.json", _payload())
	assert_ne(SSM.last_export_reason(), "", "precondition: the first export failed and set a reason")
	SSM.EXPORT_DIR = _good_dir
	assert_ne(SSM._write_export("probe_after.json", _payload()), "", "precondition: the second export succeeds")
	assert_eq(SSM.last_export_reason(), "",
		"a successful export must clear the earlier failure's reason, got: '%s'" % [SSM.last_export_reason()])


func _code_without_comments(path: String) -> String:
	## A source scan must look at CODE. This fix's comments quote the strings it retired —
	## "Nothing to export" appears in three of them — so a scan over raw text reads the old
	## wording as still live and the new assignments as absent. Measured on the import side of
	## this same channel: two arms failed on their first run for exactly this.
	var out: PackedStringArray = PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if str(line).strip_edges().begins_with("#"):
			continue
		out.append(str(line))
	return "\n".join(out)


func test_control_the_comment_stripper_keeps_code_and_drops_comments() -> void:
	## Without this the source arms below could pass on an empty string, or on a stripper that
	## removed nothing. Counted rather than matched against a phrase, which would stop proving
	## anything the moment somebody reworded a comment.
	var code: String = _code_without_comments(MANAGER_SRC)
	assert_gt(code.length(), 2000, "CONTROL: stripping comments must leave the code behind")
	assert_true(code.find("static func _write_export(") != -1, "CONTROL: code lines must survive")
	var raw_comments: int = 0
	for line in FileAccess.get_file_as_string(MANAGER_SRC).split("\n"):
		if str(line).strip_edges().begins_with("#"):
			raw_comments += 1
	var left: int = 0
	for line in code.split("\n"):
		if str(line).strip_edges().begins_with("#"):
			left += 1
	assert_gt(raw_comments, 20, "CONTROL: the manager must have comments to strip, found %d" % [raw_comments])
	assert_eq(left, 0, "CONTROL: %d comment line(s) survived, so the arms below measure the documentation" % [left])


func _body_of(code: String, signature: String) -> String:
	var start: int = code.find(signature)
	if start < 0:
		return ""
	var stop: int = code.find("\nstatic func ", start + 1)
	var stop2: int = code.find("\nfunc ", start + 1)
	if stop < 0 or (stop2 >= 0 and stop2 < stop):
		stop = stop2
	return code.substr(start, stop - start) if stop > start else code.substr(start)


func test_every_exit_in_write_export_records_a_reason() -> void:
	## The short-write and failed-rename exits need a full disk and a hostile filesystem, so
	## shape is the only cover available for them. The floor is what stops this arm going
	## quietly vacuous if the function is renamed or restructured.
	var code: String = _code_without_comments(MANAGER_SRC)
	var body: String = _body_of(code, "static func _write_export(")
	assert_ne(body, "", "CONTROL: _write_export must still be a static func of that name")
	if body == "":
		return
	assert_true(body.find("rename_absolute") != -1, "CONTROL: the extracted body must be _write_export's")
	assert_lt(body.length(), 5000, "CONTROL: the extraction must not have swallowed the rest of the file")

	var chunks: PackedStringArray = body.split("return \"\"")
	var exits: int = chunks.size() - 1
	assert_gt(exits, 2, "CONTROL: _write_export had three `return \"\"` exits; found %d" % [exits])
	if exits < 1:
		return
	var mute: Array = []
	for i in range(exits):
		## `= ["` and not `= [`: the clear at entry is `last_export_errors = []`, which would
		## otherwise satisfy the first exit for free.
		if chunks[i].find("last_export_errors = [\"") == -1:
			mute.append(i)
	assert_eq(mute, [],
		"these `return \"\"` exits (0-based) fail without recording why, so both UIs say "
		+ "'Nothing to export' about a write that failed: %s" % [str(mute)])


func test_every_public_export_refusal_records_a_reason() -> void:
	## The other half: the three public functions each have a nothing-to-write exit, and the UIs
	## cannot distinguish them from a write failure unless both say which they are. Derived from
	## the function list so a fourth export path is judged without editing this arm.
	var code: String = _code_without_comments(MANAGER_SRC)
	var checked: int = 0
	var mute: Array = []
	for sig in ["static func export_character_script(", "static func export_all_scripts(",
			"static func export_autogrind_rules("]:
		var body: String = _body_of(code, sig)
		assert_ne(body, "", "CONTROL: %s must still exist" % sig)
		if body == "":
			continue
		checked += 1
		var chunks: PackedStringArray = body.split("return \"\"")
		for i in range(chunks.size() - 1):
			if chunks[i].find("last_export_errors = [\"") == -1:
				mute.append("%s exit %d" % [sig.replace("static func ", ""), i])
	assert_eq(checked, 3, "CONTROL: expected three public export functions, judged %d" % [checked])
	assert_eq(mute, [], "these export refusals record no reason: %s" % [str(mute)])


func test_both_export_uis_read_the_recorded_reason() -> void:
	## The manager computing a reason and the UI SHOWING it are two claims. Per function, because
	## both export paths are a single function that both calls and reports.
	var mute: Array = []
	var checked: int = 0
	for pair in [[AUTOGRIND_UI_SRC, "func _export_scripts("], [GRID_EDITOR_SRC, "func _export_script("]]:
		var code: String = _code_without_comments(str(pair[0]))
		assert_gt(code.length(), 2000, "CONTROL: %s must actually be read" % [pair[0]])
		var body: String = _body_of(code, str(pair[1]))
		assert_ne(body, "", "CONTROL: %s must still contain %s" % [pair[0], pair[1]])
		if body == "":
			continue
		checked += 1
		## Either directly, or through the one-line helper that wraps it.
		var reads: bool = body.find("last_export_reason()") != -1 \
			or body.find("_export_refusal_suffix()") != -1 \
			or body.find("_first_export_reason(") != -1
		if not reads:
			mute.append("%s::%s" % [str(pair[0]).get_file(), str(pair[1])])
		if body.find("\"Nothing to export") != -1:
			mute.append("%s still asserts 'Nothing to export'" % [str(pair[0]).get_file()])
	assert_eq(checked, 2, "CONTROL: expected both export paths, judged %d" % [checked])
	assert_eq(mute, [], "these export a file and cannot tell the player why one did not land: %s" % [str(mute)])
