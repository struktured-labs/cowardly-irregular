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

## ⛔ FOLLOW-UP, 2026-10-12: THIS GUARD'S SOURCE ARMS USED A PRIVATE `#`-ONLY STRIPPER.
## `test/unit/helpers/gd_source.gd` is the shared one, and its own header records why a private
## one is not enough: **a presence assert over raw source is satisfied by PROSE ABOUT the code**,
## a `#`-only pass cannot touch a `"""` docstring, and it names THIS LANE as somewhere a
## hand-rolled toggle lost five verdicts. Measured before switching: 0 of the five files my
## reason-channel guards scan currently carry a multiline docstring with a column-0 `func `, so
## nothing was mis-cut — the exposure was by construction, not yet realised. Switched anyway,
## because "not yet" is the whole of the difference.
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
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
	## Delegated to the SHARED stripper. See the follow-up note in the header: a private
	## `#`-only pass leaves `"""` docstrings in the "code", and every arm below is a presence
	## assert, which prose about the code satisfies.
	return str(GdSource.split(FileAccess.get_file_as_string(path))["code"])

func test_control_the_shared_stripper_keeps_code_and_removes_prose() -> void:
	## The helper's header REQUIRES every caller to prove a known code site survived, because
	## over-stripping and a correct strip are the same green. It also requires flooring the DOC
	## half, because an empty doc side satisfies "the prose is gone" by construction.
	var raw: String = FileAccess.get_file_as_string(MANAGER_SRC)
	var halves: Dictionary = GdSource.split(raw)
	var code: String = str(halves["code"])
	var doc: String = str(halves["doc"])
	assert_gt(code.length(), 2000, "CONTROL: the strip must leave a code half behind")
	assert_eq(code.count("\"\"\""), 0,
		"CONTROL: a docstring delimiter survived in the code half — parity desynced")
	## ⚠ THE DOC HALF IS ONLY FLOORABLE WHEN THE FILE HAS DOCSTRINGS, and my first version of
	## this control floored it unconditionally. It RED on the first run and it was right to:
	## ScriptShareManager.gd contains ZERO `"""` regions, so an empty doc half is the correct
	## answer and the helper's own contract says so ("a file with NO `"""` also qualifies: one
	## part, even index, passes through whole"). I was measuring the helper's INPUT, not its
	## behaviour. Both regimes are asserted now, so neither is a free pass.
	if raw.count("\"\"\"") > 0:
		assert_gt(doc.length(), 200,
			"CONTROL: a file WITH docstrings must leave a non-empty doc half, or 'the prose was removed' is vacuous")
	else:
		assert_eq(doc.length(), 0,
			"CONTROL: a file with no docstrings must leave an EMPTY doc half — anything else means parity invented a region")
		## With no docstrings, the only work the strip can do is the `#` pass. Prove it did it.
		assert_gt(raw.count("\n\t##"), 20, "CONTROL: the file must have comments to strip, found %d" % [raw.count("\n\t##")])
		assert_lt(code.length(), raw.length() - 1000,
			"CONTROL: the strip removed almost nothing (%d of %d bytes) — the comment pass is not running"
			% [raw.length() - code.length(), raw.length()])
	assert_true(code.find("static func _write_export(") != -1, "CONTROL: a known code site must survive the strip")

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
