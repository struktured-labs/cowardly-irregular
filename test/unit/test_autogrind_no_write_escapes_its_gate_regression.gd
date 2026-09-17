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

## Write sites that deliberately reach the disk under test, keyed by function -> WHY.
## You cannot silence this green, only explain it green: the value is the deliverable.
const DECLARED_UNGATED := {}

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
		if t.contains("FileAccess.open(") and t.contains("FileAccess.WRITE"):
			out.append({"func": fn, "gated": gated})
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
