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
## FILE there is covered automatically; the four `src/ui/` files this lane owns are NAMED, because
## this lane does not own that whole directory. ⛔ A NEW `src/ui/` FILE added to this lane must be
## added to NAMED by hand — that is the one place this guard cannot notice its own corpus shrinking
## relative to the lane, and it is why the list is spelled out rather than globbed.

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

## ⛔ WHAT THIS GUARDS IS SHAPE, NEVER VALUE — AND FOR A NEW WRITER IT IS THE ONLY COVER.
## It asserts that a rename-into-place or a read-back APPEARS after the write. It cannot tell a
## correct `rename_absolute(staged, dest)` from one with its arguments swapped, and a value-only
## change (`var staged = CONFIG_PATH`, still renamed) is invisible to any source-text scan.
##
##     the two writers here TODAY     behavioural arms drive the real functions:
##       _append_user_mapping         test_a_capture_does_not_eat_the_other_pads_mappings   6 arms
##       save_config                  test_a_failed_config_save_keeps_the_last_good_one     3 arms
##     a writer added TOMORROW        this file, and nothing else
##
## 🔑 SO A GREEN HERE IS NOT EVIDENCE A WRITER WORKS; it is evidence nobody opened a destination.
## A new writer still needs its own arm that drives it. Stated because the failure it prevents is
## specific: a guard can watch exactly the right symbol and be checking only that it is SPELLED
## correctly, while the defect lives inside it (@cowir-battle, `_await_tween_safe` pinned by name
## while the bug sat in its while-condition).

const INPUT_DIR := "res://src/input"
## ⛔ EVERY `src/ui` FILE THIS LANE OWNS, NOT JUST THE ONE THAT WRITES TODAY. This listed
## `ControlsMenu.gd` alone — the only one with a write — so a guard named *no writer in THIS LANE*
## covered one quarter of the lane's UI. Three files had zero writes and were therefore invisible
## rather than clean, and nothing would have said so when the first one gained a write.
##
## 🔑 A CORPUS SCOPED TO WHERE THE SUBJECT IS FOUND TODAY CANNOT SEE IT ARRIVE SOMEWHERE NEW —
## and the name promised otherwise, which is the half that makes it a defect rather than a choice.
const NAMED := [
	"res://src/ui/ControlsMenu.gd",
	"res://src/ui/ControllerOverlay.gd",
	"res://src/ui/GamepadDiagnostic.gd",
	"res://src/ui/VirtualGamepad.gd",
]

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
## ⛔ ANCHORED TO THE EXPRESSION ACTUALLY WRITTEN. These were bare `rename_absolute(` and
## `get_as_text()`, satisfied by ANY such call after the write — so a writer that truncated its
## destination and then read an UNRELATED file was exempted. Measured: green, with a live
## truncating write in it. @cowir-sfx's shape — an exemption granted by a DIFFERENT subject's call.
##
## A safe writer must rename THE PATH IT STAGED, or read back THE PATH IT WROTE. Both are now
## keyed to the first argument of the write open, so another file's call cannot stand in for it.
const SAFE_FORMS := ["rename_absolute(%s", "open(%s, FileAccess.READ)"]


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


## ⛔ A COMMENT IS NOT EVIDENCE THAT A WRITE LANDED. Both scans below read raw source, so a
## `# TODO: use rename_absolute() here` under a direct write made the write read as SAFE — measured
## on a planted writer, which the ratchet passed. That is a FALSE NEGATIVE in the one direction a
## guard must never fail, and the sibling guard in this lane already stripped comments; I fixed it
## there and not here.
##
## ⚠️ Quote-aware, because a bare `find("#")` truncates any line whose MESSAGE contains one — and
## every refusal path in these writers pushes a warning.
func _strip_comment(line: String) -> String:
	var in_str: bool = false
	var quote: String = ""
	for i in line.length():
		var c: String = line[i]
		if in_str:
			if c == quote and (i == 0 or line[i - 1] != "\\"):
				in_str = false
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


## The FIRST ARGUMENT of a `FileAccess.open(...)` call — the path being opened, verbatim, so the
## safety check can demand that same expression rather than any call of the right shape.
func _opened_expr(line: String) -> String:
	var at: int = line.find("FileAccess.open(")
	if at < 0:
		return ""
	var rest: String = line.substr(at + "FileAccess.open(".length())
	var comma: int = rest.find(",")
	return rest.substr(0, comma).strip_edges() if comma > 0 else ""


## The name of the function containing `idx`, for the membership floor above.
func _enclosing_name(lines: PackedStringArray, idx: int) -> String:
	for i in range(idx, -1, -1):
		var l: String = str(lines[i])
		if l.begins_with("func "):
			return l.substr(5, l.find("(") - 5)
	return ""


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
		out += _strip_comment(str(lines[i])) + "\n"
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
			var s: String = _strip_comment(line as String).strip_edges()
			if s.is_empty():
				continue
			## ⛔ `FileAccess.WRITE`, NOT a bare "WRITE" — Godot has FOUR modes and only two truncate.
			## `READ_WRITE` does NOT truncate (the file must already exist) and contains the substring
			## "WRITE", so a bare test flagged a correct in-place patch and told its author the file was
			## being truncated. A wrong "this is broken" makes someone ACT: the fix it invites is
			## converting a safe open into a staged write for no reason.
			##
			## 🔑 The `FileAccess.` prefix anchors it and dissolves the ordering trap another lane hit
			## (`READ_WRITE` contains `READ`, so a mode list must test the write forms first):
			##     "FileAccess.READ_WRITE".contains("FileAccess.WRITE")  ->  false   ✅ not flagged
			##     "FileAccess.WRITE_READ".contains("FileAccess.WRITE")  ->  true    ✅ truncates
			if "FileAccess.open" in s and "FileAccess.WRITE" in s:
				found.append([path, n, s, fn_body, _enclosing_name(all_lines, n - 1)])
		f.close()
	return found


## ⛔ THE PERSISTERS THIS LANE HAS, PINNED BY NAME — the ONE hand-list here, and it is deliberate.
## Everything else in this file is derived; this exists so a DISAPPEARANCE is loud.
##
## Measured 2026-09-18, after `.434` went red for exactly this: cowir-autogrind moved their opens
## into shared staging helpers, and a ratchet deriving write sites from `FileAccess.open` stopped
## seeing those writers AT ALL and reported green. I planted the same refactor here — both writers
## calling an out-of-corpus `AtomicWriter.begin()` — and this file stayed **2 passing**. The
## `opens.size() > 0` control did not save it: `_preserve_unreadable`'s sidecar write survived and
## satisfied the floor while both real subjects had vanished.
##
## 🔑 A COUNT FLOOR IS SATISFIED BY A SURVIVOR; A MEMBERSHIP FLOOR IS NOT.
const MUST_BE_FOUND := ["save_config", "_append_user_mapping"]


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

	var seen: Array = []
	for row in opens:
		if not (row[4] in seen):
			seen.append(row[4])
	var missing: Array = []
	for fname in MUST_BE_FOUND:
		if not (fname in seen):
			missing.append(fname)
	assert_true(missing.is_empty(),
		"%s no longer contain a FileAccess.open(..., WRITE) that this scan can see — found %s. " % [missing, seen]
		+ "If their write moved into a shared helper, THIS GUARD IS NOW BLIND TO THEM and its green "
		+ "means nothing: a call to a write helper is itself a write site. Either teach the scan to "
		+ "follow the helper, or declare it here with the reason. Do NOT simply drop the name.")


## ⛔ THE INVARIANT. Derived, so a writer added tomorrow is covered without anyone remembering this.
func test_no_writer_opens_its_destination_directly() -> void:
	var offenders: Array = []
	for row in _write_opens():
		var text: String = row[2]
		var body: String = row[3]
		var target: String = _opened_expr(text)
		var safe: bool = false
		if target != "":
			for form in SAFE_FORMS:
				if (form % target) in body:
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


## ⛔ A NEW WRITE FORM ARRIVING IS INVISIBLE TO EVERY ARM ABOVE, and that is a third mutation class
## none of my mutations could reach (@cowir-sfx). The arms above answer *did a writer stop being
## seen* and *did a safe shape leave*. Neither answers **did a writer arrive in a form the detector
## does not match** — it shrinks no member of MUST_BE_FOUND and adds no row, so everything stays
## green while the write is audited by nobody.
##
##     FileAccess.open(p, FileAccess.WRITE)     matched — the only form the scan knows
##     var m := FileAccess.WRITE ; open(p, m)   NOT matched: "WRITE" is not on the open line
##     ResourceSaver.save(res, path)            NOT matched: no open at all
##
## 🔑 SO THIS ARM DERIVES FROM WHAT REACHES DISK, NOT FROM THE PATTERN THAT FINDS IT: every function
## in the corpus that STORES bytes must also be a function the main scan flagged. A store with no
## matched open is a write arriving by a route this file cannot see.
const STORES := ["store_string", "store_var", "store_buffer", "store_line", "store_8",
	"ResourceSaver.save", "save_png", "copy_absolute"]

## Reasons, not exemptions — a name here must say why it stores without an open the scan matches.
const UNMATCHED_BY_DESIGN := {}

## Every mode this scan can READ. An open carrying one of these is ACCOUNTED FOR — either it
## truncates and the ratchet above judges it, or it does not and there is nothing to judge.
##
## ⛔ AN OPEN WHOSE MODE THIS CANNOT READ IS A WRITE CANDIDATE, NOT A PASS (@cowir-autogrind's
## inversion). `FileAccess.open(p, mode)` with the mode in a variable proves nothing, so it must
## fall through to the arm below rather than count as a visible write.
const READABLE_MODES := ["FileAccess.READ_WRITE", "FileAccess.WRITE_READ",
	"FileAccess.WRITE", "FileAccess.READ"]


## Functions holding an open whose mode this scan can read — truncating or not.
func _accounted() -> Array:
	var out: Array = []
	for path in _lane_scripts():
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var lines: PackedStringArray = f.get_as_text().split("\n")
		f.close()
		for i in lines.size():
			var s: String = _strip_comment(str(lines[i]))
			if not ("FileAccess.open" in s):
				continue
			for m in READABLE_MODES:
				if m in s:
					var fname: String = _enclosing_name(lines, i)
					if not (fname in out):
						out.append(fname)
					break
	return out


func test_no_write_arrives_in_a_form_this_scan_cannot_see() -> void:
	var flagged: Array = _accounted()

	## ⛔ THE CONTROL FOR AN INVERTED-BURDEN ARM, AND IT IS THE ONE DIRECTION THE ARM CANNOT FAIL IN
	## BY ITSELF (@cowir-music). This arm fails SAFE: anything unreadable becomes a candidate, so if
	## the mode-reading breaks the arm gets LOUDER. The way it goes vacuous is the opposite — if
	## READABLE_MODES matched too broadly, every function would be "accounted" and this arm would
	## never fire again, silently. These two always hold a read-only open, so they drop out of
	## `_accounted()` the moment mode-reading stops working.
	assert_true("load_config" in flagged,
		"CONTROL: load_config holds a FileAccess.READ open and must be accounted — if it is not, "
		+ "READABLE_MODES has stopped matching and this arm is about to call everything a candidate")
	assert_true("register_user_mappings" in flagged,
		"CONTROL: …and so does ControllerMappings.register_user_mappings")

	## ⛔ AND THE OTHER DIRECTION, WHICH THE CORPUS CANNOT TEST BECAUSE IT HOLDS NO UNREADABLE OPEN.
	## The two asserts above prove mode-reading works AT ALL; they pass happily when it matches
	## EVERYTHING, which is the vacuous failure. Measured: widening READABLE_MODES to ["FileAccess."]
	## left all three arms green with every function accounted and this arm permanently silent.
	## So the matcher is exercised on CONSTRUCTED input, where both answers exist.
	var readable_hits: int = 0
	var opaque_hits: int = 0
	for m in READABLE_MODES:
		if m in 'var f := FileAccess.open(p, FileAccess.READ)':
			readable_hits += 1
		if m in 'var f := FileAccess.open(p, mode)':
			opaque_hits += 1
	assert_gt(readable_hits, 0, "CONTROL: a literal FileAccess.READ must read as a known mode")
	assert_eq(opaque_hits, 0,
		"CONTROL: an open whose mode is a VARIABLE must read as unknown. READABLE_MODES matched it, "
		+ "so every open now counts as accounted and the arm below can never fire again — the one "
		+ "way an inverted-burden check goes vacuous, and it fails SILENTLY.")

	var storers: Array = []
	for path in _lane_scripts():
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var lines: PackedStringArray = f.get_as_text().split("\n")
		f.close()
		for i in lines.size():
			var s: String = _strip_comment(str(lines[i])).strip_edges()
			if s.is_empty():
				continue
			for tok in STORES:
				if tok in s:
					var fname: String = _enclosing_name(lines, i)
					var entry: String = "%s.%s" % [str(path).get_file(), fname]
					if not (fname in flagged) and not (fname in UNMATCHED_BY_DESIGN) \
							and not (entry in storers):
						storers.append("%s  ->  %s" % [entry, s.substr(0, 46)])
					break

	assert_true(storers.is_empty(),
		"%s store bytes but contain no FileAccess.open(..., WRITE) this scan matches. " % [storers]
		+ "Either the write arrived in a form the detector cannot see — a hoisted mode variable, "
		+ "ResourceSaver, a copy — in which case the arms above are green about nothing for that "
		+ "writer, or it is deliberate and belongs in UNMATCHED_BY_DESIGN with the reason.")

