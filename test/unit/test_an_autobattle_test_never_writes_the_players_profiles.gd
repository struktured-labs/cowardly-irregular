extends GutTest

## The autobattle twin of test_autogrind_tests_never_write_player_data. That guard is 301 lines
## and every path in it is scoped to AutogrindSystem; the autobattle side had NO guard at all,
## while carrying the identical defect: `AutobattleSystem._save_character_profiles()` writes
## user://autobattle/profiles.json unless `_test_disable_persistence` is set, and user:// resolves
## per PROJECT NAME, so every lane's checkout writes the same directory.
##
## The class is live, not theoretical — seven test files in this repo were writing that file on
## every full-suite run and were gated on 2026-09-17.
##
## ⚠️ run_tests.sh's PLAYER-DATA NET does list `autobattle` in _NETTED_DIRS, and it is a backstop
## rather than a fix: `[ -d ] || continue` never arms for a directory that does not exist yet, and
## the restore is additive and never deletes — so on the disk of a player who has never opened the
## editor, a test's fixture is created and LEFT. The net also restores with `cp -a`, which carries
## mtime, so a write is invisible to both a content hash and an mtime check. Only a sandbox where
## the directory did not pre-exist reveals one.

const SYSTEM_PATH: String = "res://src/autobattle/AutobattleSystem.gd"
const TEST_DIR: String = "res://test/unit"
const SRC_ROOT: String = "res://src"


## ⛔ SPLITS ON `static func` AS WELL AS `func`, AND THAT IS NOT A STYLE CHOICE — it is the hole
## that hid this file's entire finding. A splitter keying on `func ` (begins_with, or find("\nfunc "))
## silently drops every static function, and BOTH of the autobattle reachers that matter are static:
## AutobattleRuleTemplates has 7 static funcs and ScriptShareManager 18. Derived without them the
## exposed set measured 0; derived with them it measured 2. A hole in the splitter reports a clean
## tree, which is the direction that costs a defect rather than a deletion.
func _funcs(src: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fname: String = ""
	var body: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		var is_static: bool = t.begins_with("static func ")
		if is_static or t.begins_with("func "):
			if fname != "":
				out.append({"name": fname, "body": "\n".join(body)})
			var after: String = t.substr(12) if is_static else t.substr(5)
			var paren: int = after.find("(")
			fname = after.substr(0, paren).strip_edges() if paren > 0 else after.strip_edges()
			body = PackedStringArray()
		elif fname != "":
			body.append(line)
	if fname != "":
		out.append({"name": fname, "body": "\n".join(body)})
	return out


## The gate IS the marker: a function carrying `if _test_disable_persistence: return` is by
## definition one that writes, so this cannot drift behind the code it watches.
func _savers() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SYSTEM_PATH)
	assert_ne(src, "", "CONTROL: could not read AutobattleSystem — a derived-empty saver set makes every arm below vacuous")
	var out: Array[String] = []
	for f in _funcs(src):
		for line in str(f["body"]).split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("if ") and t.contains("_test_disable_persistence"):
				if not (str(f["name"]) in out):
					out.append(str(f["name"]))
				break
	return out


## Savers, plus every AutobattleSystem function whose body reaches one. Savers are seeded in
## because a PUBLIC saver is itself an entry point — the autogrind twin missed save_grind_snapshot
## for exactly that reason.
func _persisting_functions() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SYSTEM_PATH)
	var savers: Array[String] = _savers()
	assert_gt(savers.size(), 1,
		"CONTROL: derived only %d gated writers from AutobattleSystem — the real count is 2 (_save_character_profiles, _save_character_scripts), so anything below that means the parser broke" % savers.size())
	var out: Array[String] = savers.duplicate()
	for f in _funcs(src):
		var fname: String = str(f["name"])
		if fname in out or fname.begins_with("_save"):
			continue
		for s in savers:
			if str(f["body"]).contains(s + "("):
				out.append(fname)
				break
	return out


func _test_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(f)
	return out


func _src_files() -> Array[String]:
	var out: Array[String] = []
	var stack: Array = [SRC_ROOT]
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out.append("%s/%s" % [d, f])
	out.sort()
	return out


## ⛔ RECEIVER-AGNOSTIC (`.fn(`), never `AutobattleSystem.fn(`. Three of the eight real reachers
## call through a LOCAL or a PARAMETER — AutobattleRuleTemplates takes the system as an argument
## (`autobattle_system.create_new_profile(...)`), AutogrindSystem uses a local (`autobattle.
## set_active_profile(...)`) — and an instance writes the same user:// path the autoload does, so
## the receiver never mattered. The leading dot is what keeps `func set_character_script(` from
## satisfying a search for a CALL to it.
func _reacher_entries() -> Dictionary:
	var persisting: Array[String] = _persisting_functions()
	var out: Dictionary = {}
	for path in _src_files():
		if path.ends_with("AutobattleSystem.gd"):
			continue
		var src: String = FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var hit := false
		for fn in persisting:
			if src.contains("." + fn + "("):
				hit = true
				break
		if not hit:
			continue
		var blocks: Array[Dictionary] = _funcs(src)
		var entries: Array[String] = []
		for f in blocks:
			for fn in persisting:
				if str(f["body"]).contains("." + fn + "("):
					if not (str(f["name"]) in entries):
						entries.append(str(f["name"]))
					break
		## ⛔ DELIBERATELY STOPS AT THE DIRECT CALLER — NO TRANSITIVE CLOSURE, AND THIS WAS MEASURED
		## RATHER THAN ASSUMED. The tempting improvement is a fixed point: a test does not call
		## `_save_script()`, it presses a key, and AutobattleGridEditor._input does reach both
		## _cycle_profile and _save_script. That is the shape that wrote three player-data files on
		## 2026-09-17. I implemented the closure and then probed what it caught, one process and one
		## VIRGIN sandbox per file (a reused sandbox cannot see it — run_tests.sh's net restores with
		## `cp -a`, which carries mtime, so the write is invisible to a content hash AND to mtime):
		##
		##     9 files newly flagged by the closure   ->   0 wrote anything.  9 false, 0 true.
		##
		## Static reachability is not runtime reachability here: `_save_script` sits behind specific
		## confirm/edit keys, and these tests drive navigation. Restoring the closure costs nine
		## declarations for no defect caught, and CLAUDE.md is explicit that a check whose correct
		## case needs a suppression list is not a check. The direct-caller form flags exactly one
		## file, which is declared below with its measurement.
		##
		## ⚠️ SO THE KEY-PRESS SHAPE IS A KNOWN GAP, NOT AN OVERSIGHT. What covers it instead is the
		## one-hop arm plus the fact that an editor test reaching a saver for real has always also
		## named AutobattleSystem: both files that actually wrote (escape_backs_out, grid_share) did.
		## If one ever writes without naming it, this is the arm that needs the closure back — and
		## the number to beat is 9 false positives.
		if not entries.is_empty():
			out[path] = entries
	return out


## ⛔ NARROWED BY ENTRY FUNCTION, NOT BY DIRECTORY, and the measurement is the whole argument.
## Scoping "which tests are exposed" to files that merely INSTANTIATE a reacher gives 181 files —
## 146 of them from Combatant alone, because every battle test builds one. A guard needing 146
## declarations is not a guard (CLAUDE.md). But Combatant only reaches a saver inside load_profile;
## save_current_profile is a pure read. Asking which ENTRY FUNCTION a test drives takes the same
## corpus from 181 to 2, and it is derived rather than tuned.
func _two_hop_offenders() -> Array[String]:
	var reachers: Dictionary = _reacher_entries()
	var out: Array[String] = []
	for fname in _test_files():
		var src: String = FileAccess.get_file_as_string(TEST_DIR + "/" + fname)
		if src == "" or src.contains("_test_disable_persistence"):
			continue
		for path in reachers:
			var cls: String = str(path).get_file().get_basename()
			# Bind the entry call to ITS OWN reacher: a bare `.confirm(` would otherwise match any
			# object in any test. The test must name the script AND drive one of its entries.
			if not (src.contains(str(path)) or src.contains(cls + ".new(")):
				continue
			for e in reachers[path]:
				if src.contains("." + str(e) + "("):
					out.append("%s (drives %s.%s)" % [fname, cls, str(e)])
					break
			if out.size() > 0 and str(out[out.size() - 1]).begins_with(fname):
				break
	return out


## ⛔ A DECLARATION, NOT AN EXEMPTION. This file passes a locally-defined `FakeAutobattleSystem`
## into the static install_as_new_profile, so the autoload is never touched and the write cannot
## happen — STRUCTURAL isolation, where setting the flag would be cargo-cult. Measured in a virgin
## XDG_DATA_HOME on 2026-09-17: user://autobattle/ created empty, zero files.
##
## ⚠️ Contrast with test_script_import_validation, which is GATED rather than declared: it reaches
## the real autoload and is isolated only because every arm feeds INVALID data. That isolation is
## contingent on inputs and dies the first time someone adds a valid-input arm; a test double does
## not have that failure mode.
const ISOLATED_BY_A_DOUBLE := {
	"test_autobattle_rule_templates_regression.gd": "passes a local FakeAutobattleSystem into install_as_new_profile; the autoload is never reached. Measured: no file written.",
}


func test_the_derived_sets_are_not_empty() -> void:
	# Control. Every verdict below is vacuously clean if either side derives to nothing — which is
	# exactly what a broken parser looks like from the outside.
	var savers: Array[String] = _savers()
	assert_true("_save_character_profiles" in savers,
		"control: _save_character_profiles is the writer that caused the incident and must appear in the derived saver set")
	var persisting: Array[String] = _persisting_functions()
	assert_true("set_character_script" in persisting,
		"control: set_character_script reaches a saver and is the function every reacher goes through")
	assert_gt(_test_files().size(), 100, "derived implausibly few test files — the directory scan is broken")


## ⛔ A FILE THAT LISTS BUT READS EMPTY DROPS OUT OF THE *OFFENDER LIST*, NOT JUST THE CENSUS.
## Three scans below open every test file and `continue` on `src == ""` — correct, and it means an
## unreadable file can never be reported as an offender. It takes its own violation with it, in
## silence. cowir-controller measured this on two of their guards with a three-way control: same
## violation, same guard, one `chmod` apart — readable EC=1, unreadable EC=0 Passing 7.
##
## ⚠️ AND THE FLOOR ABOVE CANNOT SEE IT: `_test_files().size()` counts DIRECTORY ENTRIES, so a file
## that lists and reads empty still counts toward the 100. That is cowir-sfx's aggregate floor and
## cowir-ai's indentation point — a floor OUTSIDE the loop answers "is the corpus there", never "did
## every member arrive". This arm asserts the READ, which is what the scans actually depend on.
func test_every_listed_file_actually_read() -> void:
	var dark: Array[String] = []
	for fname in _test_files():
		if FileAccess.get_file_as_string(TEST_DIR + "/" + fname) == "":
			dark.append(fname)
	assert_eq(dark, [],
		"these files are in the directory listing but read as empty, so all three scans below skip them "
		+ "on `src == \"\"` and they can never be reported as offenders — a violation in one of them is "
		+ "invisible, not absent. Fix the read or drop the file: %s" % str(dark))


## ⛔ THE CONTROL THAT WOULD HAVE CAUGHT MY OWN FIRST DERIVATION. A splitter keying on `func `
## drops static functions, reports zero exposed files, and reads as a clean tree. Pin a STATIC
## reacher by name so the hole cannot come back silently.
func test_the_splitter_sees_static_functions() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/autobattle/AutobattleRuleTemplates.gd")
	assert_ne(src, "", "control: AutobattleRuleTemplates must be readable")
	var names: Array[String] = []
	for f in _funcs(src):
		names.append(str(f["name"]))
	assert_true("install_as_new_profile" in names,
		"the function splitter must see `static func` — install_as_new_profile is static, reaches create_new_profile, and is invisible to a `func `-only split")
	var reachers: Dictionary = _reacher_entries()
	assert_true(reachers.has("res://src/autobattle/AutobattleRuleTemplates.gd"),
		"control: the static reacher must survive into the derived reacher set, not just the splitter")


func test_no_autobattle_test_persists_to_the_players_user_dir() -> void:
	var persisting: Array[String] = _persisting_functions()
	var offenders: Array[String] = []
	for fname in _test_files():
		var src: String = FileAccess.get_file_as_string(TEST_DIR + "/" + fname)
		if src == "" or not src.contains("AutobattleSystem"):
			continue
		if src.contains("_test_disable_persistence"):
			continue
		for fn in persisting:
			if src.contains("." + fn + "("):
				offenders.append("%s (calls %s)" % [fname, fn])
				break
	assert_eq(offenders, [],
		"These tests call a persisting AutobattleSystem function without setting `_test_disable_persistence`, so a full-suite run OVERWRITES the player's live user://autobattle/profiles.json — from every lane's checkout at once, since user:// resolves per project name. Add `AutobattleSystem._test_disable_persistence = true` in before_each and restore the PRIOR value in after_each: %s" % str(offenders))


func test_the_one_hop_scan_can_actually_fire() -> void:
	# "0 offenders" and "the scan never matched anything" are the same green without this.
	var persisting: Array[String] = _persisting_functions()
	var fake: String = "extends GutTest\nfunc t():\n\tAutobattleSystem.set_character_script(\"hero\", {})\n"
	var matched := false
	for fn in persisting:
		if fake.contains("." + fn + "("):
			matched = true
			break
	assert_true(matched, "control: a fabricated ungated caller must match the predicate, else the scan cannot detect a real one")
	assert_false(fake.contains("_test_disable_persistence"),
		"control: the fabricated offender must lack the flag, else the exclusion path is untested")


func test_no_autobattle_test_reaches_a_saver_through_another_script() -> void:
	var offenders: Array[String] = []
	for entry in _two_hop_offenders():
		var fname: String = str(entry).split(" ")[0]
		if not ISOLATED_BY_A_DOUBLE.has(fname):
			offenders.append(entry)
	assert_eq(offenders, [],
		"These tests drive a script that reaches an AutobattleSystem saver, without setting the flag — the two-hop shape that wrote three player-data files on 2026-09-17 while the one-hop arm stayed green. Gate them, or declare them with a measurement if a test double makes the write structurally impossible: %s" % str(offenders))


func test_the_two_hop_scan_can_actually_fire() -> void:
	# Floor by REASON: Combatant.load_profile is the entry that makes this arm worth having, since
	# 146 test files build a Combatant and only the ones driving load_profile can write.
	var reachers: Dictionary = _reacher_entries()
	assert_gt(reachers.size(), 0, "derived ZERO reachers — the scan is broken, not the code")
	assert_true(reachers.has("res://src/battle/Combatant.gd"),
		"control: Combatant reaches set_character_script from load_profile — its absence means the derivation broke")
	assert_true("load_profile" in reachers["res://src/battle/Combatant.gd"],
		"control: the entry must be load_profile specifically; save_current_profile is a pure read and must NOT be what this arm keys on")
	assert_false("save_current_profile" in reachers["res://src/battle/Combatant.gd"],
		"save_current_profile only READS (get_character_script) — if it appears here the derivation has stopped distinguishing reads from writes, and the corpus jumps from 2 files to 146")


## ⛔ ANY inner class, not `class Fake` specifically — that spelling was a FIXTURE DEPENDENCE, not a
## property. Renaming the double to `StubAutobattleSystem` is a correct change and the old predicate
## red on it, which is CLAUDE.md's coincidental-value ratchet: red on a right change, green on a
## wrong one. Mutation testing cannot find this — every mutation I wrote preserved the name. The
## question that finds it is "does a RIGHT change red this?", which needs an authored change rather
## than a broken one (@cowir-sfx's trim, @cowir-autogrind's speed 2.0, @cowir-sprites' animation).
func _declares_an_inner_class(src: String) -> bool:
	for line in src.split("\n"):
		if line.begins_with("class ") and line.strip_edges().ends_with(":"):
			return true
	return false


func test_a_declared_double_still_drives_the_entry() -> void:
	# A declaration nobody has watched fire is indistinguishable from a dead entry.
	var flagged: Array[String] = []
	for entry in _two_hop_offenders():
		flagged.append(str(entry).split(" ")[0])
	var stale: Array[String] = []
	for fname in ISOLATED_BY_A_DOUBLE:
		var src: String = FileAccess.get_file_as_string(TEST_DIR + "/" + str(fname))
		if src == "":
			stale.append("%s (missing)" % fname)
		elif not (str(fname) in flagged):
			stale.append("%s (no longer reaches a saver)" % fname)
		elif not _declares_an_inner_class(src):
			stale.append("%s (no local double — the stated reason for the declaration is gone)" % fname)
	assert_eq(stale, [],
		"a file declared as isolated by a test double no longer matches that description — drop the declaration or gate the file, rather than carrying a stale one: %s" % str(stale))
