extends GutTest

## All FIVE `return {}` exits in `ScriptShareManager.import_file` recorded no reason, and both
## callers ask for one.
##
## `AutobattleGridEditor._apply_share_selection` reads `last_import_reason()` and falls back to
## "Could not apply <file> to <character>" when it is empty — so a malformed or non-export file
## was reported as a character/script mismatch, and the character is not involved at any of these
## exits. `AutogrindUI._import_scripts` asserted the cause outright: "<file> could not be read —
## not valid export JSON", which is wrong for two of the five (a file that vanished between
## `list_exports()` and the accept keypress, and a well-formed .json with no 'type'/'version'
## header).
##
## The parser's own message AND the line it gave up on were computed here and handed only to
## `push_warning` — the log the player never reads. For a hand-edited share file that line number
## is the entire repair.
##
## This is the third sibling on the same channel: `a-partial-bundle-says-who-was-skipped` (the
## bundle applier) and `an-autogrind-import-refusal-says-why` (the autogrind applier) fixed the
## same shape one and two layers down. This one is the FILE READER, which is upstream of both —
## it is the exit a player hits before any rule is ever validated.
##
## ⚠️ NOT WIDENED INTO `test_share_import_failure_names_the_reason_regression`. That file's
## `test_every_APPLY_path_can_say_why_it_refused` deliberately scopes itself to
## `apply_character_script(` and records in its own comment that it considered and declined
## `AutogrindUI::_import_scripts`. Its arms are untouched.
##
## ⚠️ `get_export_summary` still answers the flat string "Invalid file" for all five. It is pinned
## exactly (`assert_eq`) by `test_script_share.test_get_export_summary_invalid_file`, so changing
## what the picker ROW says is somebody's deliberate contract and a separate review.
##
## EXPORT_DIR is redirected per process, as the two sibling share tests do: user:// keys by app
## name, so all worktrees share one directory and the player's own exports live in it.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")
const MANAGER_SRC := "res://src/autobattle/ScriptShareManager.gd"
const AUTOGRIND_UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

var _prior_export_dir: String = ""


func before_all() -> void:
	_prior_export_dir = SSM.EXPORT_DIR
	SSM.EXPORT_DIR = "user://script_exports_unreadable_test_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(SSM.EXPORT_DIR)


func after_all() -> void:
	## Restore FIRST, so a failure below cannot leak the override into test_script_share, which
	## pins the production default.
	var mine := SSM.EXPORT_DIR
	if _prior_export_dir != "":
		SSM.EXPORT_DIR = _prior_export_dir
	if DirAccess.dir_exists_absolute(mine):
		for fname in DirAccess.get_files_at(mine):
			DirAccess.remove_absolute(mine + str(fname))
		DirAccess.remove_absolute(mine)


func before_each() -> void:
	SSM.last_import_errors = []


func after_each() -> void:
	SSM.last_import_errors = []


func _write(fname: String, text: String) -> bool:
	## Never clobber: a name that already exists means the redirect did not take and we are about
	## to overwrite somebody's export.
	var path: String = SSM.EXPORT_DIR + fname
	assert_false(FileAccess.file_exists(path),
		"CONTROL: %s must not already exist — the EXPORT_DIR redirect did not take" % path)
	if FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "CONTROL: must be able to write the probe file %s" % path)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func _drop(fname: String) -> void:
	var path: String = SSM.EXPORT_DIR + fname
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_control_a_well_formed_export_reads_clean_and_records_no_reason() -> void:
	## Without this, every refusal arm below could pass on a reader that refuses everything.
	var fname := "probe_good.json"
	if not _write(fname, '{"version": 1, "type": "autobattle_script", "character_id": "probe", "script": {"rules": []}}'):
		return
	var data: Dictionary = SSM.import_file(fname)
	assert_false(data.is_empty(), "CONTROL: a well-formed export must be read")
	assert_eq(data.get("type", ""), "autobattle_script", "CONTROL: and must come back intact")
	assert_eq(SSM.last_import_reason(), "", "CONTROL: a clean read must record no reason")
	_drop(fname)


func test_a_file_that_is_gone_names_the_file_rather_than_the_character() -> void:
	## Reachable from the picker: the rows come from list_exports(), and the file can be deleted
	## before the player presses accept. The old fallback blamed the current character.
	var data: Dictionary = SSM.import_file("probe_never_existed.json")
	assert_true(data.is_empty(), "precondition: a missing file must be refused")
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "a missing file must record a reason, not leave 'Could not apply X to <character>'")
	assert_true(why.find("probe_never_existed.json") != -1,
		"and the reason must name the FILE, which is the thing that is wrong: '%s'" % [why])


func test_malformed_json_carries_the_parsers_own_message_and_line() -> void:
	## The assertion that cannot pass on a constant string: two DIFFERENT syntax errors must give
	## two DIFFERENT reasons. A hard-coded "not valid JSON" would satisfy every other check here.
	var a := "probe_bad_a.json"
	var b := "probe_bad_b.json"
	if not _write(a, "{\n\t\"type\": \"autobattle_script\",\n\t\"version\": 1,\n"):
		return
	if not _write(b, "{{{ this is not json at all }}}"):
		return

	assert_true(SSM.import_file(a).is_empty(), "precondition: a truncated object must be refused")
	var why_a: String = SSM.last_import_reason()
	assert_ne(why_a, "", "a JSON syntax error must record a reason")

	assert_true(SSM.import_file(b).is_empty(), "precondition: garbage must be refused")
	var why_b: String = SSM.last_import_reason()
	assert_ne(why_b, "", "the second syntax error must record a reason too")

	assert_ne(why_a, why_b,
		"both reasons are the same string, so the parser's own message is not reaching the player: '%s'" % [why_a])
	assert_true(why_a.to_lower().find("line") != -1,
		"a hand-edited file is repaired BY LINE, so the reason must carry one: '%s'" % [why_a])
	## ⚠ JSON.get_error_line() IS 0-BASED. Measured: this one-line file reports line 0, and the
	## player is going to open it in an editor that counts from 1. A "line 0" in a status flash is
	## worse than no line at all — it is a number that cannot be found.
	assert_true(why_b.find("line 1)") != -1,
		"a break on the FIRST line must read 'line 1', not the parser's 0: '%s'" % [why_b])
	assert_false(why_b.find("line 0)") != -1,
		"no editor numbers lines from zero: '%s'" % [why_b])
	_drop(a)
	_drop(b)


func test_a_bare_list_is_not_reported_as_a_syntax_error() -> void:
	## Someone copying the "rules" array out of the middle of an export produces exactly this, and
	## it is valid JSON — so "not valid export JSON" sent them looking for a typo that is not there.
	var fname := "probe_bare_list.json"
	if not _write(fname, '[{"conditions": [], "actions": []}]'):
		return
	assert_true(SSM.import_file(fname).is_empty(), "precondition: a non-object root must be refused")
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "a non-object root must record a reason")
	assert_true(why.to_lower().find("list") != -1,
		"the reason must say the top level is a LIST, which is what the player has to change: '%s'" % [why])
	assert_false(why.to_lower().find("not valid json") != -1,
		"and must NOT call valid JSON invalid — that is the sentence this fix deletes: '%s'" % [why])
	_drop(fname)


func test_a_json_without_the_export_header_says_so_instead_of_blaming_the_syntax() -> void:
	## A save file, or any stray .json a player drops in the export folder. list_exports() offers
	## it by extension alone, so this exit is one keypress away for anyone who looks in the folder.
	var fname := "probe_no_header.json"
	if not _write(fname, '{"party": ["brannon"], "gold": 400}'):
		return
	assert_true(SSM.import_file(fname).is_empty(), "precondition: a headerless object must be refused")
	var why: String = SSM.last_import_reason()
	assert_ne(why, "", "a headerless .json must record a reason")
	assert_true(why.find("type") != -1,
		"the reason must name the missing header field: '%s'" % [why])
	assert_false(why.to_lower().find("not valid json") != -1,
		"and must not report well-formed JSON as a syntax error: '%s'" % [why])
	_drop(fname)


func test_a_successful_read_does_not_leave_the_previous_refusals_reason() -> void:
	## The clear sits at entry for this reason, and get_export_summary() runs import_file over
	## EVERY row when the picker is built — so a bad file in the list must not caption a later
	## good one. Pins that the clear works through THIS path.
	var fname := "probe_clear_good.json"
	if not _write(fname, '{"version": 1, "type": "autogrind_rules", "rules": []}'):
		return
	SSM.import_file("probe_never_existed.json")
	assert_ne(SSM.last_import_reason(), "", "precondition: the first read failed and set a reason")
	assert_false(SSM.import_file(fname).is_empty(), "precondition: the second read succeeds")
	assert_eq(SSM.last_import_reason(), "",
		"a successful read must clear the earlier refusal's reason, got: '%s'" % [SSM.last_import_reason()])
	_drop(fname)


func _code_without_comments(path: String) -> String:
	## ⛔ BOTH SOURCE ARMS BELOW FAILED ON THEIR FIRST RUN BECAUSE OF THIS. The fix's own
	## comments quote the thing they replaced — the manager's says "EVERY `return {}` RECORDS A
	## REASON" and the UI's quotes the old "not valid export JSON" sentence — so a scan over raw
	## text counted a sixth `return {}` that is a comment, and read the old wording as still live.
	## A source scan must look at code or it is measuring its own documentation.
	var out: PackedStringArray = PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if str(line).strip_edges().begins_with("#"):
			continue
		out.append(str(line))
	return "\n".join(out)


func test_control_the_comment_stripper_keeps_code_and_drops_comments() -> void:
	## Without this the two source arms could both pass on an empty string, or on a stripper that
	## removed nothing. Counted rather than matched against a phrase: a marker taken from this
	## fix's own comment would stop proving anything the moment somebody reworded the comment.
	var code: String = _code_without_comments(MANAGER_SRC)
	assert_gt(code.length(), 2000, "CONTROL: stripping comments must leave the code behind")
	assert_true(code.find("static func import_file(") != -1, "CONTROL: code lines must survive")
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


func test_every_exit_in_import_file_records_a_reason() -> void:
	## The open-failure exit cannot be reached from a test — a file that FileAccess.file_exists
	## accepts and FileAccess.open rejects needs permissions a headless run cannot arrange — so it
	## is covered by shape instead of by behaviour. The floor below is what stops this arm going
	## quietly vacuous if the function is renamed or restructured.
	var src: String = _code_without_comments(MANAGER_SRC)
	assert_gt(src.length(), 2000, "CONTROL: %s must actually be read" % MANAGER_SRC)
	var start: int = src.find("static func import_file(")
	assert_gt(start, -1, "CONTROL: import_file must still be a static func of that name")
	if start < 0:
		return
	var stop: int = src.find("\nstatic func ", start + 1)
	var body: String = src.substr(start, stop - start) if stop > start else src.substr(start)
	assert_true(body.find("EXPORT_DIR + filename") != -1,
		"CONTROL: the extracted body must be import_file's, not a neighbour's")
	assert_lt(body.length(), 5000, "CONTROL: the extraction must not have swallowed the rest of the file")

	var chunks: PackedStringArray = body.split("return {}")
	var exits: int = chunks.size() - 1
	assert_gt(exits, 4, "CONTROL: import_file had five `return {}` exits; found %d, so this arm is not looking at them" % [exits])
	if exits < 1:
		return
	var mute: Array = []
	for i in range(exits):
		## `= ["` and not `= [`: the clear at entry is `last_import_errors = []`, which would
		## otherwise satisfy the first exit for free.
		if chunks[i].find("last_import_errors = [\"") == -1:
			mute.append(i)
	assert_eq(mute, [],
		"these `return {}` exits (0-based) refuse without recording why, so the caller shows "
		+ "'Could not apply <file> to <character>' or '(no reason recorded)': %s" % [str(mute)])


func test_the_bulk_import_loop_shows_the_recorded_reason() -> void:
	## The manager computing a reason and the UI SHOWING it are two claims. AutogrindUI's loop
	## already prints _refusal_suffix() on its four other refusals; the file-read one asserted
	## "not valid export JSON" instead, which it does not know.
	var src: String = _code_without_comments(AUTOGRIND_UI_SRC)
	assert_gt(src.length(), 2000, "CONTROL: %s must actually be read" % AUTOGRIND_UI_SRC)
	var start: int = src.find("var data = ScriptShareManager.import_file(filename)")
	assert_gt(start, -1, "CONTROL: the bulk loop must still read its files through import_file")
	if start < 0:
		return
	var stop: int = src.find("\t\t\tcontinue", start)
	assert_gt(stop, start, "CONTROL: the refusal branch must still end in a continue")
	if stop <= start:
		return
	var branch: String = src.substr(start, stop - start)
	assert_true(branch.find("_refusal_suffix()") != -1,
		"the bulk loop's file-read refusal must print the recorded reason, not assert a cause: %s" % [branch])
	assert_false(branch.find("not valid export JSON") != -1,
		"and must not keep claiming bad JSON for a file that vanished or lacks a header")
