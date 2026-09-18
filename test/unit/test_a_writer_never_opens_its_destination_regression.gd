extends GutTest

## `FileAccess.open(path, WRITE)` TRUNCATES on open. Every AutogrindSystem writer used to open the
## player's own file and THEN serialize, so a crash inside that window left a 0-byte file and no
## previous copy — a race against this process dying, not against another writer. Six writers had
## it (permadead species, profiles, learned patterns, CSI data, resume snapshot, session history),
## four of them silent on failure. All six now stage a sibling and rename it into place.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SYSTEM_PATH := "res://src/autogrind/AutogrindSystem.gd"


## ⛔ PROSE CAN SATISFY A DECLARATION PIN. A `"""` region keeps its lines' indentation where a `#`
## occupies column 0, so `func _write_json_atomic(` surviving only inside a docstring satisfies a
## `find("func …")` pin while the real declaration is gone (@cowir-music, 2026-09-18). MEASURED
## here: the pin stayed SILENT under exactly that plant and a SIBLING arm red for its own reason —
## the file looked red, the pin was blind, and only the message said which arm spoke.
## ⚠️ NOT `code_of`: it rejoins on `"""` and destroys line numbers. strip_comments IS line-
## preserving, so strip `#` with the shared helper and blank `"""` regions per line.
## ⚠️ AND NO ARM KEEPS ITS OWN `#` CHECK. A residual private strip beside a delegated one is
## invisible to a grep for the HELPER'S NAME (@cowir-ai found their 16th one function from
## their 15th that way). Mine were dead — stripped source has no `#` — but dead comment
## handling reads as the file's policy, and anyone removing this routing would silently fall
## back to line-start-only, which is the exact defect this replaced.
func _code_of(path: String) -> String:
	var out: PackedStringArray = []
	var in_doc := false
	for line in GdSource.strip_comments(FileAccess.get_file_as_string(path)).split("\n"):
		var l: String = str(line)
		var fences: int = l.count("\"\"\"")
		if in_doc:
			out.append("")
			if fences % 2 == 1:
				in_doc = false
		else:
			out.append("" if fences > 0 else l)
			if fences % 2 == 1:
				in_doc = true
	return "\n".join(out)
const PROBE := "user://autogrind_atomic_probe.json"


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	for p in [PROBE, PROBE + ".new"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write_open_lines() -> Array:
	## DERIVED. A per-function ratchet is what let a second writer sit 170 lines below a fixed one
	## with the identical shape (@cowir-music, src/save) — so this walks every WRITE open there is.
	var src: String = _code_of(SYSTEM_PATH)
	assert_ne(src, "", "CONTROL: could not read AutogrindSystem — every arm below would be vacuous")
	var out: Array = []
	var n := 0
	for line in src.split("\n"):
		n += 1
		if line.contains("FileAccess.open(") and line.contains("WRITE"):
			out.append([n, line.strip_edges()])
	return out


func test_the_write_scan_can_actually_fire() -> void:
	# Control: "0 offenders" and "the scan matched nothing" are the same green.
	var lines := _write_open_lines()
	assert_gt(lines.size(), 0, "derived ZERO WRITE opens — the scan is broken, not the code")


func test_no_writer_opens_its_destination() -> void:
	var offenders: Array = []
	for entry in _write_open_lines():
		## The one legal WRITE opens the STAGED sibling; anything else is opening a real file.
		if not str(entry[1]).contains("FileAccess.open(staged,"):
			offenders.append("line %d: %s" % [entry[0], entry[1]])
	assert_eq(offenders, [],
		"These open a destination with WRITE, truncating the player's file before anything is serialized — stage a sibling and rename it into place: %s" % str(offenders))


func test_the_payload_is_serialized_before_anything_is_opened() -> void:
	## The ordering IS the fix: serializing after the open is what puts the whole payload inside
	## the truncation window. A staged write with the stringify below the open is no better.
	var src: String = _code_of(SYSTEM_PATH)
	var i_fn: int = src.find("func _write_json_atomic(")
	assert_gt(i_fn, -1, "CONTROL: the atomic helper must exist, or this arm measures nothing")
	var i_str: int = src.find("JSON.stringify(", i_fn)
	var i_open: int = src.find("FileAccess.open(", i_fn)
	assert_gt(i_str, -1, "CONTROL: the helper must serialize")
	assert_gt(i_open, -1, "CONTROL: the helper must open a file")
	assert_lt(i_str, i_open,
		"JSON.stringify must run BEFORE the open — serializing inside the window is the defect")


func test_a_real_write_lands_and_leaves_no_staging_file() -> void:
	var ok: bool = AutogrindSystem._write_json_atomic(PROBE, {"probe": 42}, "test")
	assert_true(ok, "the helper must report success on a writable path")
	assert_true(FileAccess.file_exists(PROBE), "the destination must hold the payload")
	assert_false(FileAccess.file_exists(PROBE + ".new"),
		"the staged sibling must be renamed away, not left as litter")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROBE))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the destination must parse")
	assert_eq(int((parsed as Dictionary).get("probe", -1)), 42, "and hold what was written")


func test_the_gate_still_marks_every_writer() -> void:
	## The persistence ratchet derives its saver set from `if _test_disable_persistence: return`.
	## Moving that gate into the shared helper would collapse the derived set to one and silently
	## widen what tests may write — so each writer keeps its own gate.
	var src: String = _code_of(SYSTEM_PATH)
	var savers: Array = []
	var current := ""
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("func ") or t.begins_with("static func "):
			var h: int = t.find("func ") + 5
			current = t.substr(h, t.find("(") - h)
		elif current != "" and t.contains("_test_disable_persistence") and t.begins_with("if "):
			if not (current in savers):
				savers.append(current)
	assert_gt(savers.size(), 3,
		"the gate must still mark each writer individually — the ratchet's saver set derives from it: %s" % str(savers))
	assert_false("_write_json_atomic" in savers,
		"the shared helper must NOT carry the gate, or every writer collapses into one derived saver")


func test_the_writer_verifies_its_bytes_before_renaming() -> void:
	## `store_string` returns nothing, so a short write is invisible, and staging does NOT cover it
	## — a rename moves a partial file into place just as happily. Verified before the rename so a
	## truncated payload never reaches the destination. get_error() is used 0x elsewhere in src/.
	var src: String = _code_of(SYSTEM_PATH)
	var i_fn: int = src.find("func _write_json_atomic(")
	assert_gt(i_fn, -1, "CONTROL: the atomic helper must exist")
	var i_end: int = src.find("\nfunc ", i_fn + 20)
	var body: String = src.substr(i_fn, i_end - i_fn)
	var i_check: int = body.find("get_length()")
	var i_rename: int = body.find("rename_absolute")
	assert_gt(i_check, -1, "the writer must read back what it wrote — store_string cannot report a short write")
	assert_gt(i_rename, -1, "CONTROL: the writer must rename")
	assert_lt(i_check, i_rename,
		"the byte check must run BEFORE the rename, else a partial file is renamed into place")
	assert_true(body.contains("get_error()"),
		"the writer must consult get_error() — it is the only signal store_string leaves behind")
