extends GutTest

## `ControlsMenu._append_user_mapping` reads the captured-mappings file, drops any entry with the
## same GUID, appends the new one, and writes the whole array back. The read-back is the load-bearing
## half: everything it fails to read is everything it is about to overwrite.
##
## ⛔ IT COLLAPSES THREE DISTINCT FAILURES INTO ONE SILENT EMPTY LIST, and then writes:
##     if rf:                        open failed        -> entries stays []   silent
##       parsed = JSON.parse_string  not valid JSON     -> entries stays []   silent
##       if parsed is Array:         root not an Array  -> entries stays []   silent
##     ... kept.append(mapping); wf.store_string(JSON.stringify(kept))
## `kept` is then ONLY the new mapping, so every other pad the player ever captured is gone.
##
## 📌 THE SAME FILE HAS A CAREFUL READER 20 LINES AWAY, WHICH IS WHAT MAKES THIS AN INCONSISTENCY
## RATHER THAN AN OVERSIGHT. `ControllerMappings.register_user_mappings` separates all four cases and
## warns on each (:95 open, :99 JSON, :103 non-Array, :108 per-entry). The difference is the cost of
## being wrong: when the READER fails nothing is lost and the player is told; when this read-back
## fails the file is overwritten and the loss is permanent. The silent handler is the destructive one.
##
## ⚠️ The corruption is self-inflicted and needs no bad luck: the write is NOT atomic — `FileAccess.
## open(path, WRITE)` truncates immediately and `store_string` follows, so a crash or a full disk in
## between leaves exactly the truncated/empty JSON the arms below plant.

const CM := preload("res://src/input/ControllerMappings.gd")
const CMENU := preload("res://src/ui/ControlsMenu.gd")

const A := "030000005e040000e002000000000000,Pad A,a:b0,b:b1,platform:Linux,"
const B := "030000004c050000c405000000000000,Pad B,a:b0,b:b1,platform:Linux,"
const C := "0300000058620000cb02000000000000,Pad C,a:b0,b:b1,platform:Linux,"

var _had_file: bool = false
var _saved: String = ""


## ⛔ THIS TEST WRITES A PRODUCTION PATH — the same `user://input/controller_mappings.json` a player's
## captured pads live in. run_tests.sh's snapshot net covers `user://script_exports/`, NOT this, so
## the restore has to be here. Snapshot the BYTES, and remember whether the file existed at all: a
## tree with no captured pads must end with no file, not with an empty one.
func before_all() -> void:
	_had_file = FileAccess.file_exists(CM.USER_MAPPINGS_PATH)
	if _had_file:
		_saved = FileAccess.open(CM.USER_MAPPINGS_PATH, FileAccess.READ).get_as_text()


func after_all() -> void:
	_remove(CM.USER_MAPPINGS_PATH + ".unreadable")
	_remove(CM.USER_MAPPINGS_PATH + ".new")
	if _had_file:
		_write_raw(_saved)
	elif FileAccess.file_exists(CM.USER_MAPPINGS_PATH):
		DirAccess.open("user://input").remove(CM.USER_MAPPINGS_PATH.get_file())


func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.open("user://input").remove(p.get_file())


func _sidecar_text() -> String:
	var p: String = CM.USER_MAPPINGS_PATH + ".unreadable"
	return FileAccess.open(p, FileAccess.READ).get_as_text() if FileAccess.file_exists(p) else ""


func before_each() -> void:
	_remove(CM.USER_MAPPINGS_PATH + ".unreadable")
	_remove(CM.USER_MAPPINGS_PATH + ".new")


func _write_raw(text: String) -> void:
	DirAccess.open("user://").make_dir_recursive("input")
	var f := FileAccess.open(CM.USER_MAPPINGS_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _entries() -> Array:
	if not FileAccess.file_exists(CM.USER_MAPPINGS_PATH):
		return []
	var d = JSON.parse_string(FileAccess.open(CM.USER_MAPPINGS_PATH, FileAccess.READ).get_as_text())
	return d if d is Array else []


## Drives the REAL method on a real instance. `_append_user_mapping` touches no UI node, so the menu
## never needs to enter the tree — and not entering it keeps `_ready`'s pad enumeration out of this.
func _capture(new_mapping: String) -> bool:
	var m = CMENU.new()
	var ok: bool = m._append_user_mapping(new_mapping)
	m.free()
	return ok


## ⛔ THE CONTROL, and every arm below is meaningless without it: against a HEALTHY file the function
## must keep the other pads. If it dropped them always, the corruption arms would be measuring
## nothing but the function's ordinary behaviour.
func test_a_healthy_file_keeps_the_pads_already_captured() -> void:
	_write_raw(JSON.stringify([A, B], "\t"))
	_capture(C)
	var e: Array = _entries()
	assert_true(A in e, "CONTROL: capturing a third pad must keep Pad A — got %d entr(ies)" % e.size())
	assert_true(B in e, "CONTROL: …and Pad B")
	assert_true(C in e, "CONTROL: …and must actually record the new pad")


## ⛔ THE DEFECT. A crash between the truncate and the store leaves partial JSON; the next capture
## read nothing, and wrote that nothing back over everything.
##
## 📌 THE CONTRACT IS PRESERVE, NOT PARSE. Salvaging Pad A out of `[\n\t"A",\n\t"B` would need a
## recovery parser this file has no business inventing — so the bytes are copied aside intact and
## the player is told where. What must never happen is that they cease to exist.
func test_a_truncated_file_does_not_cost_the_player_every_other_pad() -> void:
	_write_raw("[\n\t\"" + A + "\",\n\t\"" + B)
	_capture(C)
	assert_true(A in _sidecar_text(),
		"the mappings file was truncated mid-write. Capturing a new pad could not parse it, so the "
		+ "whole file was overwritten with just the new mapping and Pad A ceased to exist. Bytes we "
		+ "cannot read are still the player's pads: preserve them. Sidecar held %d byte(s)."
			% _sidecar_text().length())
	assert_true(C in _entries(), "…and the new pad must still be recorded, or the player cannot capture at all")


## ⛔ THIS ARM ASSERTED AN IMPOSSIBLE CONTRACT AND IS KEPT, INVERTED, RATHER THAN DELETED. It read
## "a 0-byte file must not cost the player their other pads" — but 0 bytes HOLD no pads. Whatever
## truncated the file destroyed them; the capture that follows is not the culprit and cannot recover
## them. It failed fail-first alongside the two real arms and looked like the same defect.
##
## 🔑 What is worth pinning here is the opposite: the fix must NOT treat empty as precious. A sidecar
## for 0 bytes is litter in the player's config directory on every capture after a crash.
func test_an_empty_file_is_replaced_cleanly_and_leaves_no_sidecar() -> void:
	_write_raw("")
	_capture(C)
	assert_true(C in _entries(), "an empty file must simply be replaced — the new pad is recorded")
	assert_false(FileAccess.file_exists(CM.USER_MAPPINGS_PATH + ".unreadable"),
		"0 bytes hold no mappings, so there is nothing to preserve; writing a sidecar anyway litters "
		+ "the config directory every time a capture follows an interrupted save. "
		+ "⛔ ASSERT THE FILE IS ABSENT, NOT THAT ITS TEXT IS EMPTY — preserving \"\" creates a file "
		+ "whose text is \"\", so the content form passed the mutation that caused exactly this litter.")


## Root-not-an-Array is the third silent branch, and the reader at :103 treats it as its own case.
func test_a_non_array_root_does_not_cost_the_player_every_other_pad() -> void:
	_write_raw('{"pads": ["' + A + '"]}')
	_capture(C)
	assert_true(A in _sidecar_text(),
		"`parsed is Array` is false, so entries stayed empty and the file was overwritten. The READER "
		+ "distinguishes this exact case and warns (ControllerMappings:103); the writer's read-back "
		+ "silently discarded it — and only the writer's version is destructive.")


## ⛔ A FAILED SAVE MUST LEAVE THE PREVIOUS MAPPINGS INTACT — the observable half of writing through
## a staged file. `FileAccess.open(path, WRITE)` truncates the target the moment it succeeds, so the
## direct form destroys the old list before it knows whether the new one can be written. Staging
## beside the target means a failure costs the player nothing.
##
## 📌 THE OTHER HALF — that the file is never partial ACROSS A CRASH — is deliberately not asserted.
## It needs the process to die between the truncate and the store, which a unit test cannot stage, and
## an arm that merely checks the staging file is gone afterwards passes without the rename ever
## happening (measured: mutating the staged path to the target left all five arms green). An absence
## has no loud direction; this arm pins a presence instead.
func test_a_save_that_cannot_be_written_does_not_destroy_the_old_list() -> void:
	_write_raw(JSON.stringify([A, B], "\t"))
	var blocker: String = CM.USER_MAPPINGS_PATH + ".new"
	DirAccess.open("user://input").make_dir(blocker.get_file())
	assert_true(DirAccess.dir_exists_absolute(blocker), "CONTROL: the staging path must be blocked, or this arm proves nothing")

	var ok: bool = _capture(C)

	var e: Array = _entries()
	DirAccess.open("user://input").remove(blocker.get_file())
	assert_false(ok,
		"⛔ ASSERT THE REFUSAL, NOT ONLY THE SURVIVAL. `A in e and B in e` alone is satisfied by a "
		+ "build that ignores the staging path entirely and writes the target directly — measured: "
		+ "that mutation left this arm green. The caller shows \"NOT saved\" off this bool, so a save "
		+ "that silently reports success is its own defect.")
	assert_true(A in e and B in e,
		"the new mapping could not be staged, and the pads captured before it must survive that "
		+ "untouched — %d entr(ies) left" % e.size())


## …and the ordinary path must still land the complete list.
func test_a_capture_records_every_pad_and_leaves_no_litter() -> void:
	_write_raw(JSON.stringify([A, B], "\t"))
	_capture(C)
	var e: Array = _entries()
	assert_true(A in e and B in e and C in e, "all three pads must be in the file: %d entr(ies)" % e.size())
	assert_false(FileAccess.file_exists(CM.USER_MAPPINGS_PATH + ".new"),
		"the staged file must not be left beside the real one, where the next run has to guess which is current")
