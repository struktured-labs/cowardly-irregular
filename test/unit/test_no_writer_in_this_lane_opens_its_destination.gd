extends GutTest

## Both of this lane's write fixes were pinned by arms that DRIVE ONE FUNCTION —
## `_append_user_mapping` and `save_config`. That is a measurement of today, not an invariant: a
## third writer added later with `FileAccess.open(dest, WRITE)` is covered by nothing.
##
## ⛔ THAT IS NOT HYPOTHETICAL. cowir-music found `save_settings` sitting 170 lines below
## `_write_save_file` in one file with the identical truncating shape, and their per-function
## ratchet passed the entire time the second writer was broken.
##
## 🔑 SO THIS ARM DERIVES ITS OFFENDERS FROM THE SOURCE rather than naming functions. `WRITE`
## truncates on open, so a writer that opens its DESTINATION has already destroyed the previous
## contents before it knows whether the new ones can be written — the window is a race against the
## process dying. Staging beside the target and renaming into place has no window at all.
##
## ⚠️ SCOPE, STATED BECAUSE A DERIVED CORPUS STILL HAS A BOUNDARY: `src/input/` is globbed, so a NEW
## FILE there is covered automatically; `ControlsMenu.gd` is named, because the mapping writer lives
## in `src/ui/` and this lane does not own that whole directory. A lane-mate adding a writer to some
## other `src/ui/` file is NOT covered here, and no arm in this file can honestly claim otherwise.

## 📌 THE READ SIDE WAS SWEPT TOO AND IS CLEAN — recorded here because it is a NULL, and a null is
## what gets re-derived with every step green. Derived from `FileAccess.open(…READ)` across the same
## corpus, 2026-09-18: THREE reader functions, all loud.
##
##     ControllerMappings.register_user_mappings   4 warnings: open · JSON · root type · per-entry
##     InputProfileManager.load_config             4 warnings, tick 167
##     ControlsMenu._append_user_mapping (read-back)  was the silent one — fixed in .432
##
## ⚠️ The local shape of the fleet's asymmetry, worth knowing before you go looking: BOTH standalone
## readers were hardened deliberately, while the writer that CREATES the file they defend against
## stayed non-atomic, and the one read-back living INSIDE a writer was the silent one. Loudness
## tracked the FUNCTION'S JOB, not the file — a reader only ever reports a loss, and the read-back
## was the only one that could cause one. So do not read "the readers are fine" as evidence about
## anything else in the file.

const INPUT_DIR := "res://src/input"
const NAMED := ["res://src/ui/ControlsMenu.gd"]

## ⛔ TWO SAFE SHAPES, NOT ONE, AND THE SECOND IS NOT A CONCESSION. The hazard is truncating a file
## whose contents someone still needs before knowing the new ones landed. A STAGED write avoids the
## truncate entirely. A VERIFIED write reads its own result back and refuses on a mismatch — which is
## what `_preserve_unreadable` needs, because it creates a rescue copy whose destination holds
## nothing worth keeping, and its real hazard is a SHORT write (`store_string` returns no error) that
## would let the caller go on to destroy the original.
##
## ⚠️ Staging cannot fix a short write — the rename moves the partial file into place just as
## happily — so accepting only the staged shape here would have forced the WRONG repair.
## ⛔ STRUCTURAL SIGNALS, NOT NAMING ONES. This was `["staged", ".new", …]` — which matched the WORD
## `staged` anywhere in the function, including inside a `push_warning` ARGUMENT. Measured: stripping
## the staging suffix AND deleting the rename left this arm green, because a diagnostic string still
## said "staged". A convention is not a property, and a ratchet keyed to one certifies spelling.
##
## `rename_absolute(` means the bytes were put somewhere else and moved into place; `get_as_text()`
## in the same function means the write was read back and judged. Both are things the code DOES.
const SAFE_MARKERS := ["rename_absolute(", "get_as_text()"]


func _lane_scripts() -> Array:
	var out: Array = []
	var d := DirAccess.open(INPUT_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append("%s/%s" % [INPUT_DIR, f])
	for n in NAMED:
		if FileAccess.file_exists(n):
			out.append(n)
	out.sort()
	return out


## The enclosing function's body FROM THE WRITE ONWARD — per-function rather than per-line, but
## forward-only.
##
## ⛔ THE DIRECTION IS THE WHOLE CHECK, AND WITHOUT IT THIS ARM IS VACUOUS. `_append_user_mapping`
## calls `get_as_text()` BEFORE its write — that is the read-back of the existing file, nothing to
## do with verifying what it is about to store. Scanning the whole body accepted it as evidence, so
## stripping the staging suffix AND deleting the rename still passed. Evidence that the write landed
## cannot precede the write.
func _body_after(lines: PackedStringArray, idx: int) -> String:
	var out: String = ""
	for i in range(idx, lines.size()):
		if i > idx and str(lines[i]).begins_with("func "):
			break
		out += str(lines[i]) + "\n"
	return out


## Every `FileAccess.open(X, …WRITE)` in the corpus, as [path, line_no, text, enclosing_body].
func _write_opens() -> Array:
	var found: Array = []
	for path in _lane_scripts():
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var all_lines: PackedStringArray = f.get_as_text().split("\n")
		var n: int = 0
		for line in all_lines:
			n += 1
			var fn_body: String = _body_after(all_lines, n - 1)
			var s: String = (line as String).strip_edges()
			if s.begins_with("#"):
				continue
			if "FileAccess.open" in s and "WRITE" in s:
				found.append([path, n, s, fn_body])
		f.close()
	return found


## ⛔ THE CONTROL, and it has to come first: if the corpus is empty or contains no write at all,
## "no writer opens its destination" is vacuously true and this file guards nothing.
func test_there_are_real_writers_in_this_lane_to_reason_about() -> void:
	var scripts: Array = _lane_scripts()
	assert_gt(scripts.size(), 3,
		"CONTROL: the lane corpus must resolve — globbed %d script(s) from %s" % [scripts.size(), INPUT_DIR])
	assert_true("res://src/ui/ControlsMenu.gd" in scripts, "CONTROL: the named mapping writer must be in scope")
	var opens: Array = _write_opens()
	assert_gt(opens.size(), 0,
		"CONTROL: the lane must contain at least one FileAccess.open(..., WRITE), or the arm below "
		+ "passes without looking at anything")


## ⛔ THE INVARIANT. Derived, so a writer added tomorrow is covered without anyone remembering this.
func test_no_writer_opens_its_destination_directly() -> void:
	var offenders: Array = []
	for row in _write_opens():
		var text: String = row[2]
		var body: String = row[3]
		var safe: bool = false
		for marker in SAFE_MARKERS:
			if marker in text or marker in body:
				safe = true
				break
		if not safe:
			offenders.append("%s:%d  %s" % [str(row[0]).replace("res://", ""), row[1], text])

	assert_true(offenders.is_empty(),
		"these writers open their DESTINATION with WRITE, which truncates it before anything is "
		+ "stored — a crash or a failed write in between leaves the player with an empty or partial "
		+ "file, and there is no previous version left:\n  %s\n"
			% "\n  ".join(offenders)
		+ "Stage beside the target (`path + \".new\"`) and `DirAccess.rename_absolute` into place.")
