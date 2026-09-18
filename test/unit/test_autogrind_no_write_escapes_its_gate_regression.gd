extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## MEASURED 2026-09-17, not reasoned: a virgin XDG_DATA_HOME, the 74 test_autogrind*.gd files that
## never assign _test_disable_persistence, and an inventory of user:// afterwards. Three player-data
## files came back — autogrind/profiles.json, learned_patterns.json, csi_data.json — from ONE file,
## test_autogrind_editor_escape_backs_out_regression.gd, whose Escape arm calls _save_rules ->
## set_autogrind_rules -> _save_autogrind_profiles. The 8 files that DO assign the flag wrote nothing.
##
## ⛔ NO CHEAPER INSTRUMENT COULD HAVE SEEN IT. autogrind/ is in run_tests.sh's _NETTED_DIRS and the
## net restores with `cp -a`, which carries mtime — so in a reused sandbox a write is invisible to a
## content hash AND to mtime. Only a sandbox where the dir did not exist pre-run shows it, because
## the net's `[ -d ] || continue` never arms and its restore is additive, never a delete.
##
## ⚠️ AND THE NET CANNOT UNDO THIS ONE EVEN WHEN IT ARMS. It restores what it SNAPSHOTTED; a file it
## never saw is created and left. A player with no autogrind/ dir yet gets fixture content written
## into their real user:// by a bare suite run, permanently.
##
## 📌 THE CORPUS IS NAMED, BECAUSE A GREEN IS ONLY EVIDENCE ABOUT WHAT IT COULD HAVE CONTAINED: this
## pins DIRECT `FileAccess.open(…, FileAccess.WRITE)` calls under the two autogrind source dirs. A
## write reaching disk through SaveSystem.save_settings(), ResourceSaver, or another lane's autoload
## is OUTSIDE it and this file says nothing about those. `_cycle_safety` is the known example — it
## gates correctly, in a condition rather than an early return, and holds no FileAccess call at all.

const GRIND_SRC_DIRS := ["res://src/autogrind", "res://src/ui/autogrind"]

## ⛔ A WRITE SITE IS WHERE THE DISK IS REACHED, NOT WHERE FileAccess APPEARS. On 2026-09-18 the six
## AutogrindSystem savers and AutogrindUI._persist_custom_presets moved their open into a shared
## staging helper. Every one still carries its own gate — but the open left, so this file stopped
## seeing them AT ALL: the ungated arm named the helpers and the floor below fired, correctly
## reporting that a clean result meant nothing. A call to a helper is scored as a write site so the
## saver set stays derived from the gates rather than from where FileAccess happens to sit.
const WRITE_HELPERS := ["_write_json_atomic", "_write_presets_atomic"]

## ⛔ AN OPEN MUST PROVE IT IS READ-ONLY. Every arm here used to require FileAccess.WRITE on the
## SAME LINE as the open, so cowir-autogrind's planted `var mode := FileAccess.WRITE` followed by
## `FileAccess.open(path, mode)` was a live, ungated, truncating write to player data that this file
## and its sibling both scored green. A mode the scan cannot read is now a write CANDIDATE — the
## opposite default from every other arm, deliberately, because the two errors do not cost the same:
## a false offender is explained in DECLARED_UNGATED, a missed one eats a save.
## ⚠️ ORDER IS LOAD-BEARING: READ_WRITE contains READ, so the write forms must be ruled out FIRST or
## the widest mode reads as the safest one.
const WRITE_MODES := ["FileAccess.READ_WRITE", "FileAccess.WRITE_READ", "FileAccess.WRITE"]
const READ_ONLY_PROOF := "FileAccess.READ"

## Write sites that deliberately reach the disk under test, keyed by function -> WHY.
## You cannot silence this green, only explain it green: the value is the deliverable.
const DECLARED_UNGATED := {
	"_write_json_atomic": "Staging helper, reached only through the six savers above, each carrying its own gate. WRITE_HELPERS scores a CALL to it as a write site, so a new UNGATED caller still reds here — the cover moved up a level, it did not go away. Gating the helper itself is refused by test_a_writer_never_opens_its_destination_regression:95: it would collapse every derived saver into one and silently widen what a test may write.",
	"_write_presets_atomic": "AutogrindUI's copy of the same helper, same reason. Its one caller, _persist_custom_presets, gates.",
}

## ⛔ FLOOR BY REASON, NOT BY COUNT. A count reds on a legitimate new writer and stays green on the
## drop it exists to catch. These two are known write sites; if the derivation stops finding them,
## the regex or the strip broke and every "0 ungated" below is vacuous. This is also GdSource's
## caller contract — over-stripping and a correct strip are the same green without it.
const MUST_BE_FOUND := ["_save_permadead_characters", "_persist_custom_presets"]


func _gd_files_under(root: String) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if str(f).ends_with(".gd"):
				out.append("%s/%s" % [d, f])
	out.sort()
	return out


## One entry per write site: which function holds it, and whether a _test_disable_persistence
## statement precedes it INSIDE that function. Reports the SYMBOL, never a line number — the
## stripped source does not share line numbers with the file, and a symbol cannot drift.
## An open is read-only only if it SAYS so. A hoisted mode variable, a computed flag, or a mode this
## cannot parse is a write candidate. See WRITE_MODES for why the order of those checks matters.
func _opens_read_only(line: String) -> bool:
	for m in WRITE_MODES:
		if line.contains(m):
			return false
	return line.contains(READ_ONLY_PROOF)


func _classify(code: String) -> Array:
	var out: Array = []
	var fn: String = "<file scope>"
	var gated: bool = false
	for raw in code.split("\n"):
		var t: String = str(raw).strip_edges()
		if t.begins_with("func ") or t.begins_with("static func "):
			var after: String = t.substr(t.find("func ") + 5)
			var paren: int = after.find("(")
			fn = after.substr(0, paren) if paren > 0 else after
			gated = false
			continue
		if t.contains("_test_disable_persistence") and (t.begins_with("if ") or t.begins_with("elif ")):
			gated = true
			continue
		if t.contains("FileAccess.open("):
			if not _opens_read_only(t):
				out.append({"func": fn, "gated": gated})
			continue
		for helper in WRITE_HELPERS:
			## The helper's own body is not a call site; `fn == helper` keeps it out of its own count.
			if fn != helper and t.contains(helper + "("):
				out.append({"func": fn, "gated": gated})
				break
	return out


func _all_sites() -> Array:
	var out: Array = []
	for d in GRIND_SRC_DIRS:
		for path in _gd_files_under(d):
			for site in _classify(GdSource.code_of(path)):
				site["file"] = path
				out.append(site)
	return out


## The whole point of the file. Every bucket is exclusive and they must SUM — a bare `continue`
## inside the loop would hide a site from all three totals and read as clean.
func test_no_write_site_escapes_its_gate() -> void:
	var sites: Array = _all_sites()
	var gated: Array = []
	var declared: Array = []
	var ungated: Array = []
	for s in sites:
		var fn: String = str(s["func"])
		if bool(s["gated"]):
			gated.append(fn)
		elif DECLARED_UNGATED.has(fn):
			declared.append(fn)
		else:
			ungated.append("%s in %s" % [fn, str(s["file"]).get_file()])

	assert_eq(gated.size() + declared.size() + ungated.size(), sites.size(),
		"buckets must sum — a site landing in none of them is invisible to this guard")
	assert_eq(ungated, [],
		"an autogrind write reaches user:// during a test run: %s — add `if _test_disable_persistence: return` above it, or declare it in DECLARED_UNGATED with a reason" % str(ungated))


## Without this the arm above is unfalsifiable: "0 ungated" and "the classifier never says ungated"
## are the same green. Same synthetic source, one gated function and one bare.
func test_the_classifier_can_say_ungated() -> void:
	var synthetic: String = "\n".join([
		"func _gated() -> void:",
		"\tif _test_disable_persistence: return",
		"\tvar f = FileAccess.open(\"user://a.json\", FileAccess.WRITE)",
		"",
		"func _bare() -> void:",
		"\tvar f = FileAccess.open(\"user://b.json\", FileAccess.WRITE)",
	])
	var got: Array = _classify(synthetic)
	assert_eq(got.size(), 2, "the classifier must see both synthetic write sites")
	assert_eq(str(got[0]["func"]), "_gated", "first site is the gated one")
	assert_true(bool(got[0]["gated"]), "a preceding _test_disable_persistence guard must read as gated")
	assert_eq(str(got[1]["func"]), "_bare", "second site is the bare one")
	assert_false(bool(got[1]["gated"]), "a bare write must read as UNGATED — this is the arm the guard rests on")


## Without this, "0 ungated" and "the helper rule never matched" are the same green — the same
## unfalsifiability the arm above defends against, one mechanism over. A saver that reaches the disk
## ONLY through a helper must still be classified, and its gate must still count.
func test_a_helper_call_is_itself_a_write_site() -> void:
	var synthetic: String = "\n".join([
		"func _gated_saver() -> void:",
		"\tif _test_disable_persistence: return",
		"\t_write_json_atomic(\"user://a.json\", {}, \"a\")",
		"",
		"func _bare_saver() -> void:",
		"\t_write_presets_atomic(\"user://b.json\", {}, \"b\")",
	])
	var got: Array = _classify(synthetic)
	assert_eq(got.size(), 2, "a saver reaching the disk through a helper must still be a write site")
	assert_eq(str(got[0]["func"]), "_gated_saver", "the gated saver must be seen by name")
	assert_true(bool(got[0]["gated"]), "its own gate still counts when the open lives one level down")
	assert_false(bool(got[1]["gated"]),
		"an UNGATED helper caller is the widening this rule exists to catch — if this passes, the refactor bought silence")


## The arm the inversion rests on. A hoisted mode puts NOTHING on the open line, which is exactly
## what the old rule required, so this synthetic scored ZERO write sites before today — measured, on
## a real plant in AutogrindAchievements: old rule offenders [], new rule names the function.
func test_an_open_must_prove_it_is_read_only() -> void:
	var synthetic: String = "\n".join([
		"func _reads() -> void:",
		"\tvar f = FileAccess.open(\"user://a.json\", FileAccess.READ)",
		"",
		"func _hoists_its_mode() -> void:",
		"\tvar mode = FileAccess.WRITE",
		"\tvar f = FileAccess.open(\"user://b.json\", mode)",
	])
	var got: Array = _classify(synthetic)
	assert_eq(got.size(), 1,
		"exactly one write site: the declared READ open is not one, the hoisted-mode open is — got %s" % str(got))
	assert_eq(str(got[0]["func"]), "_hoists_its_mode",
		"the hoisted-mode open is the write site; naming the reader instead means the modes are read backwards")
	assert_false(bool(got[0]["gated"]), "and it is UNGATED — the live defect shape this inversion exists to catch")


## ⚠️ READ_WRITE CONTAINS READ. Rule the write forms out first or the widest mode reads as the
## safest. NOTE the claim is "writable", not "truncating" — READ_WRITE does not truncate, and this
## guard's subject is a write escaping the gate, not truncation (cowir-controller, 2026-09-18).
func test_a_writable_mode_is_a_write_even_though_it_contains_read() -> void:
	for mode in ["FileAccess.READ_WRITE", "FileAccess.WRITE_READ"]:
		var got: Array = _classify("func _rw() -> void:\n\tvar f = FileAccess.open(\"user://a\", %s)\n" % mode)
		assert_eq(got.size(), 1, "%s opens a writable handle and must be a write site" % mode)


## CONTROL. An inverted-burden rule fails SAFE by design — anything unreadable becomes a candidate —
## so the way it breaks is by calling EVERYTHING read-only, and then "0 ungated" is silence, not
## health (cowir-music's MUT B). Both directions are exercised on CONSTRUCTED input, because the
## corpus holds no open with an unreadable mode and therefore cannot test the over-match direction
## from inside itself (cowir-controller).
func test_the_scan_still_recognises_a_read_only_open() -> void:
	assert_true(_opens_read_only("var f = FileAccess.open(\"user://a\", FileAccess.READ)"),
		"a declared READ open must read as read-only, or every reader in the corpus becomes a false offender")
	assert_false(_opens_read_only("var f = FileAccess.open(\"user://a\", mode)"),
		"an unreadable mode must NOT read as read-only — this is the over-match direction that makes the guard silent")
	var reads: int = 0
	for d in GRIND_SRC_DIRS:
		for path in _gd_files_under(d):
			for raw in GdSource.code_of(path).split("\n"):
				var t: String = str(raw).strip_edges()
				if t.contains("FileAccess.open(") and _opens_read_only(t):
					reads += 1
	assert_gt(reads, 0,
		"the corpus has read-only opens and the scan found none — it is classifying everything as a write, or reading no source at all")


## A gate belonging to a LATER function must not cover an earlier one, or the classifier reports
## safety it cannot see. Order is the only thing separating these two cases.
func test_a_gate_does_not_leak_across_a_function_boundary() -> void:
	var synthetic: String = "\n".join([
		"func _bare() -> void:",
		"\tvar f = FileAccess.open(\"user://a.json\", FileAccess.WRITE)",
		"",
		"func _gated() -> void:",
		"\tif _test_disable_persistence: return",
		"\tvar f = FileAccess.open(\"user://b.json\", FileAccess.WRITE)",
	])
	var got: Array = _classify(synthetic)
	assert_eq(got.size(), 2, "both synthetic sites must be seen")
	assert_false(bool(got[0]["gated"]), "the gate below must not reach back up into _bare")
	assert_true(bool(got[1]["gated"]), "_gated's own guard still counts")


## GdSource's caller contract, and this file's corpus floor. If these stop resolving, the
## derivation broke and every count above is about an empty set.
func test_the_derivation_still_finds_the_writers_it_is_named_for() -> void:
	var found: Array = []
	for s in _all_sites():
		found.append(str(s["func"]))
	for expected in MUST_BE_FOUND:
		assert_true(found.has(expected),
			"%s is a known autogrind write site and the derivation no longer finds it — the regex, the source layout or GdSource's strip changed, and a clean result here means nothing" % expected)
