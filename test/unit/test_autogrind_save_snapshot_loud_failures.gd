extends GutTest

## Cadence #14 — save_grind_snapshot must push_warning on every failure mode,
## symmetric with load_grind_snapshot's tick-344 hardening. Pre-fix: `print`
## for FileAccess error (no editor warnings panel, no CI signal) and silent
## `return false` when not is_grinding (caller bug hidden).

const AutogrindSystemScript := preload("res://src/autogrind/AutogrindSystem.gd")


var _system: Node
var _pre_existed: bool = false
var _pre_bytes: PackedByteArray = PackedByteArray()


func before_each() -> void:
	_system = AutogrindSystemScript.new()
	add_child_autofree(_system)
	# Byte-snapshot the real user snapshot BEFORE mutating (cadence #3 pattern):
	# test_writes_when_grinding exercises the actual write path, so any
	# pre-existing user snapshot must be restored — the "test isolation from
	# user save" rule forbids after_each simply deleting a file that may hold
	# real player state (msg 2586 PSA + the TestChar0 incident before it).
	_pre_existed = FileAccess.file_exists(AutogrindSystemScript.SNAPSHOT_PATH)
	if _pre_existed:
		_pre_bytes = FileAccess.get_file_as_bytes(AutogrindSystemScript.SNAPSHOT_PATH)
	_system._test_disable_persistence = false  # explicit — we want the real code path


func after_each() -> void:
	# Restore the user's original snapshot bytes so the test is bit-transparent.
	if _pre_existed:
		var f := FileAccess.open(AutogrindSystemScript.SNAPSHOT_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_pre_bytes)
			f.close()
	else:
		# Only delete if the file didn't exist pre-test — otherwise we'd nuke
		# the just-restored real data.
		if FileAccess.file_exists(AutogrindSystemScript.SNAPSHOT_PATH):
			DirAccess.remove_absolute(AutogrindSystemScript.SNAPSHOT_PATH)


func test_returns_false_when_not_grinding() -> void:
	_system.is_grinding = false
	assert_false(_system.save_grind_snapshot({}),
		"pre-cadence-#14 contract preserved: not-grinding path returns false without writing")


func test_writes_when_grinding() -> void:
	# Sanity: happy path still writes (regression guard for the successful case).
	_system.is_grinding = true
	assert_true(_system.save_grind_snapshot({"config": {}}),
		"grinding + writable path must still succeed after cadence #14 (only failure paths were hardened)")
	assert_true(FileAccess.file_exists(AutogrindSystemScript.SNAPSHOT_PATH),
		"successful save must actually put bytes on disk")


func test_source_ratchet_not_grinding_uses_push_warning() -> void:
	# Ratchet the diagnostic surface: the not-grinding branch must call
	# push_warning so a caller-bug (save invoked outside a session) shows
	# up in the editor warnings panel + CI test output. Same-shape guard
	# as tick 344 does for load_grind_snapshot.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func save_grind_snapshot")
	assert_true(fn_start >= 0, "save_grind_snapshot must exist")
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	# Isolate the not-grinding block: everything up to the first FileAccess call.
	var pre_file: int = body.find("FileAccess.open")
	assert_true(pre_file > 0)
	var head: String = body.substr(0, pre_file)
	assert_true(head.contains("push_warning") and head.contains("not grinding"),
		"save_grind_snapshot's not-grinding path must push_warning so silent caller-bugs surface (cadence #14, mirrors tick 344 on the load path)")


func test_source_ratchet_file_open_failure_uses_push_warning_with_error_code() -> void:
	# Ratchet the FileAccess-open failure: must be push_warning (not print)
	# AND must include get_open_error() so an interrupted disk / permission /
	# quota error is diagnosable. Matches load_grind_snapshot's shape.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func save_grind_snapshot")
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	# Find the "if not file:" branch — must be within a few lines after FileAccess.open.
	var file_pos: int = body.find("FileAccess.open")
	assert_true(file_pos > 0)
	var post_file: String = body.substr(file_pos, 400)
	assert_true(post_file.contains("push_warning") and post_file.contains("get_open_error"),
		"FileAccess.open failure must push_warning + include get_open_error() code (parity with load_grind_snapshot line 2361) — else 'save silently didn't happen' is un-debuggable (cadence #14)")


func test_not_grinding_return_false_still_the_contract() -> void:
	# Belt-and-suspenders: cadence #14 added the push_warning but must NOT have
	# converted return-false into return-true. Test guards against the class of
	# regression where hardening a diagnostic accidentally flips a return.
	_system.is_grinding = false
	var result = _system.save_grind_snapshot({})
	assert_typeof(result, TYPE_BOOL, "return type unchanged — still bool")
	assert_eq(result, false, "not-grinding still returns false")
