extends GutTest

## Guards the player-data hazard measured 2026-08-06: the test suite was overwriting the
## player's live autogrind profiles on every full-suite run, by every lane.
##
## `AutogrindSystem._save_autogrind_profiles()` writes `user://autogrind/profiles.json` unless
## `_test_disable_persistence` is set. Two tests called `set_autogrind_rules` without setting
## it, so every gate rewrote the player's active profile with test fixtures — leaving
## `Standard Grind = always -> stop_grinding`, which halts autogrind on its first evaluation
## and reads as a broken feature.
##
## It survived because `user://` resolves per PROJECT NAME, not per checkout: every lane's
## clone writes the same directory, so no one lane's "my tests are clean" was ever the
## question. And `run_tests.sh`'s PLAYER-DATA NET covers `user://script_exports` only —
## `user://autogrind/` had no net under it at all.
##
## Both sides of this check are DERIVED, not hand-listed:
##   - the persisting functions come from AutogrindSystem's own source (any func whose body
##     reaches a `_save_*` writer)
##   - the offenders come from scanning test/ for calls to them
## A hand-list on either side would go stale the first time someone adds a writer, and today
## produced five separate instances of hand-lists having holes.
##
## NOTE this asserts the FLAG IS SET, not that a given test currently triggers a write. Two
## tests call `start_autogrind`/`stop_autogrind`, reach a saver only via `_record_session`,
## and happen not to write today — measured. Whether they write depends on execution paths
## that can change, so the flag is required regardless. Requiring the one-line deliverable is
## cheaper than re-deriving reachability every time the call graph moves.

const SYSTEM_PATH: String = "res://src/autogrind/AutogrindSystem.gd"
const TEST_DIR: String = "res://test/unit"
## ⛔ THIS WAS A HAND-LIST OF THREE AND THERE ARE SIX. Until 2026-09-17 it read
## ["_save_autogrind_profiles", "_save_csi_data", "_save_session_history"], omitting
## _save_permadead_characters, _save_learned_patterns and — worst — save_grind_snapshot, which is
## PUBLIC and writes user://autogrind_snapshot.json. A hand-listed corpus inside the guard whose
## whole subject is "which functions write player data" is the same defect one level up.
##
## DERIVED NOW: the gate IS the marker. A function carrying `if _test_disable_persistence: return`
## is by definition one that writes, so the list cannot drift behind the code it watches.
func _savers() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SYSTEM_PATH)
	assert_ne(src, "", "CONTROL: could not read AutogrindSystem — a derived-empty saver set makes every arm below vacuous")
	var out: Array[String] = []
	var current: String = ""
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		## ⛔ BOTH FORMS. Keying on "func " alone DROPS every `static func` — @cowir-battle found that
		## hole in this guard's autobattle twin, where it hid two exposed reachers and reported a
		## CLEAN tree, which is the direction that costs a defect rather than a deletion. Measured
		## here 2026-09-18: 13 static funcs across the scanned autogrind sources, ZERO of them
		## writers, so this lane's version is latent. Closed before a static writer arrives.
		if t.begins_with("func ") or t.begins_with("static func "):
			var head: int = t.find("func ") + 5
			current = t.substr(head, t.find("(") - head)
		elif current != "" and t.contains("_test_disable_persistence") and t.begins_with("if "):
			if not (current in out):
				out.append(current)
	return out


## Every AutogrindSystem function whose body reaches a user:// writer, read from source.
func _persisting_functions() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SYSTEM_PATH)
	assert_ne(src, "", "could not read AutogrindSystem — this check would silently pass on an empty corpus")
	var savers: Array[String] = _savers()
	assert_gt(savers.size(), 3,
		"CONTROL: derived only %d gated writers — the hand-list this replaced had 3 and missed half, so anything at or below that is the same defect returning" % savers.size())
	var out: Array[String] = []
	## Same both-forms scan as _savers above: find("\nfunc ") cannot see a `static func`.
	var starts: Array = []
	for m in RegEx.create_from_string("(?m)^(?:static )?func ([A-Za-z_][A-Za-z_0-9]*)\\(").search_all(src):
		starts.append([m.get_start(), m.get_string(1)])
	assert_gt(starts.size(), 20, "CONTROL: the function scan must find the autoload's functions")
	for i in range(starts.size()):
		var start: int = int(starts[i][0])
		var next: int = int(starts[i + 1][0]) if i + 1 < starts.size() else -1
		var body: String = src.substr(start, (next - start) if next > 0 else -1)
		var name: String = str(starts[i][1])
		## ⛔ A SAVER IS ITSELF A PERSISTING ENTRY POINT WHEN IT IS PUBLIC. The old form skipped every
		## name beginning with "_save" — correct for the private ones, and it also meant
		## `save_grind_snapshot` had to be reached INDIRECTLY to count. It is public, two tests call it
		## straight, and it calls no other saver, so it was in neither set. Savers are now seeded in.
		if savers.has(name):
			if not (name in out):
				out.append(name)
			continue
		if name.begins_with("_save"):
			continue
		for s in savers:
			if body.contains(s + "("):
				if not (name in out):
					out.append(name)
				break
	return out


## ⛔ THE FLAG IS NOT THE FIX FOR THESE TWO, AND THAT IS WHY THEY ARE NAMED RATHER THAN GATED.
## Their SUBJECT is the on-disk roundtrip: `test_save_and_load_roundtrip` asserts
## save_grind_snapshot() returns true, which the gate makes false. Setting the flag would delete the
## test's own claim. `SNAPSHOT_PATH` is a const with no per-test seam, so redirection is not
## available either — the shape CLAUDE.md prefers ("override the path in your own fixture") has
## nowhere to attach.
##
## ⚠️ SO THIS IS A DECLARATION, NOT AN EXEMPTION: both byte-snapshot the player's file and restore
## it, which memory records as WEAKER than the gate (the restore is itself a write, and an abort in
## between leaves the file modified). Recorded so the next reader knows the weaker protection is
## deliberate and bounded, not an oversight — and the arm below reds if a declared file stops
## calling a saver, so a stale entry cannot outlive its reason.
const ON_DISK_BY_DESIGN := {
	"test_autogrind_snapshot.gd": "exercises the real save/load roundtrip; the gate would make save_grind_snapshot return false and void the assertion. Byte-restores the player's file.",
	"test_autogrind_save_snapshot_loud_failures.gd": "same roundtrip, loud-failure arms. Byte-restores.",
}


func test_a_declared_on_disk_test_still_writes() -> void:
	## A declaration nobody has watched fire is indistinguishable from a dead entry. Each declared
	## file must STILL reach a saver — otherwise it was fixed or rewritten and the exemption is stale.
	var persisting := _persisting_functions()
	assert_gt(persisting.size(), 3, "CONTROL: the persisting set must be real, or every verdict here is vacuous")
	var stale: Array = []
	for fname in ON_DISK_BY_DESIGN:
		var src: String = FileAccess.get_file_as_string(TEST_DIR + "/" + str(fname))
		if src == "":
			stale.append("%s (missing)" % fname)
			continue
		var reaches := false
		for fn in persisting:
			if src.contains("." + fn + "("):
				reaches = true
				break
		if not reaches:
			stale.append("%s (no longer calls a saver)" % fname)
	assert_eq(stale, [],
		"a file declared as writing on disk by design no longer does — drop the declaration rather than carrying a stale exemption: %s" % str(stale))


func _test_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(f)
	return out


func test_the_derived_corpus_is_not_empty() -> void:
	# Control. Every assertion below is vacuously true if either side derives to nothing —
	# which is exactly how a broken scan reports a clean tree.
	var persisting := _persisting_functions()
	assert_gt(persisting.size(), 0,
		"derived ZERO persisting functions from AutogrindSystem — the parser is broken, not the code")
	assert_true("set_autogrind_rules" in persisting,
		"control: set_autogrind_rules is known to persist (it is the function that caused the incident) and must appear in the derived set")
	assert_gt(_test_files().size(), 100,
		"derived implausibly few test files — the directory scan is broken")


func test_no_autogrind_test_persists_to_the_players_user_dir() -> void:
	var persisting := _persisting_functions()
	var offenders: Array[String] = []

	for fname in _test_files():
		var src: String = FileAccess.get_file_as_string(TEST_DIR + "/" + fname)
		if src == "" or not src.contains("AutogrindSystem"):
			continue
		if src.contains("_test_disable_persistence"):
			continue
		## ⛔ RECEIVER-AGNOSTIC, not `AutogrindSystem.<fn>(`. The qualified form misses a call through a
		## LOCAL — `_system.save_grind_snapshot(...)` — and an instance writes the same user:// path the
		## autoload does, so the receiver never mattered. Measured before widening: the qualified form
		## catches 0 ungated tests, the agnostic form catches exactly 2, so this costs no allowlist.
		## @cowir-controller's point from the controls census: `Receiver.api(` is vulnerable to a local
		## or a string lookup; `\.api(` is immune by construction.
		if ON_DISK_BY_DESIGN.has(fname):
			continue
		for fn in persisting:
			if src.contains("." + fn + "("):
				offenders.append("%s (calls %s)" % [fname, fn])
				break

	assert_eq(offenders.size(), 0,
		"These tests call a persisting AutogrindSystem function without setting `_test_disable_persistence`, so a full-suite run OVERWRITES the player's live user://autogrind data — and since user:// resolves per project name, it does so from every lane's checkout at once. Add `AutogrindSystem._test_disable_persistence = true` in before_each/before_all: %s" % ", ".join(offenders))


func test_the_offender_scan_can_actually_fire() -> void:
	# Control on the detector itself: construct the offending shape and confirm the predicate
	# matches it. Without this, `offenders.size() == 0` is equally true of a scan that never
	# matched anything — the empty-bucket failure that took four lanes today.
	var persisting := _persisting_functions()
	var fake_offender: String = "extends GutTest\nfunc t():\n\tAutogrindSystem.set_autogrind_rules([])\n"
	var matched: bool = false
	for fn in persisting:
		if fake_offender.contains("AutogrindSystem." + fn + "("):
			matched = true
			break
	assert_true(matched,
		"control: a fabricated ungated caller must match the predicate, else the scan cannot detect a real one")
	assert_false(fake_offender.contains("_test_disable_persistence"),
		"control: the fabricated offender must lack the flag, else the exclusion is untested")


## ⛔ THE ARM ABOVE IS ONE HOP, AND A REAL WRITE GOT THROUGH IT ON 2026-09-17. Its predicate is a
## literal `AutogrindSystem.<fn>(` in the test's own source, behind a `src.contains("AutogrindSystem")`
## filter. test_autogrind_editor_escape_backs_out_regression names AutogrindSystem NOWHERE: it loads
## AutogrindGridEditor and presses ui_cancel, whose arm calls _save_rules -> set_autogrind_rules.
## Measured in a virgin XDG_DATA_HOME, it wrote profiles.json, learned_patterns.json and csi_data.json
## while this file sat green. The detector was correct about what it checked and blind to the shape.
##
## ⚠️ AND NO REUSED SANDBOX COULD HAVE SHOWN IT: autogrind/ is in run_tests.sh's _NETTED_DIRS and the
## net restores with `cp -a`, which carries mtime — so the write is invisible to a content hash AND to
## mtime. Only a sandbox where the dir did not exist pre-run reveals it.

## Scripts that call a persisting AutogrindSystem function on the player's behalf. DERIVED, because a
## hand-list is what made the hop-1 arm miss this. AutogrindSystem itself is excluded: it reaches its
## own savers by construction, and including it would flag every guard that reads it as text.
func _indirect_reachers() -> Array[String]:
	var persisting := _persisting_functions()
	var out: Array[String] = []
	## ⛔ SCOPED TO THE LANE'S OWN UI, AND THAT IS A DELIBERATE NARROWING WITH A MEASUREMENT BEHIND IT.
	## Deriving reachers from ALL of src/ is correct and useless: `save_grind_snapshot` is public and
	## GameLoop calls it, so every test that instantiates GameLoop becomes a "reacher" — 94 out-of-lane
	## files on one run, every one of them proven NOT to write by the exhaustive per-file sweep.
	## A check whose correct case needs 94 declarations is not a check (CLAUDE.md), and the blast-radius
	## rule says the same thing: a general-purpose object cannot discriminate.
	## The arm's actual subject is a test driving a GRIND UI NODE into a writer — which is what the
	## 2026-09-17 leak was — and every such node lives in these two directories.
	var stack: Array = ["res://src/autogrind", "res://src/ui/autogrind"]
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			var path: String = "%s/%s" % [d, f]
			if not path.ends_with(".gd") or path.ends_with("AutogrindSystem.gd"):
				continue
			var body: String = FileAccess.get_file_as_string(path)
			for fn in persisting:
				if body.contains("AutogrindSystem." + fn + "("):
					out.append(path)
					break
	out.sort()
	return out


## A test is exposed when it names a reacher's res:// path AND instantiates something — reading the
## file as text is how the source-level guards use it and must not count.
func _two_hop_offenders() -> Array[String]:
	var reachers := _indirect_reachers()
	var out: Array[String] = []
	for fname in _test_files():
		var src: String = FileAccess.get_file_as_string(TEST_DIR + "/" + fname)
		if src == "" or src.contains("_test_disable_persistence"):
			continue
		if not (src.contains(".new()") or src.contains(".instantiate()")):
			continue
		for r in reachers:
			if src.contains(r):
				out.append(fname)
				break
	return out


## Owned by other lanes, measured 2026-09-17 to write nothing today, reported in-channel. A SUBSET
## check, not equality: a new exposure reds, and a lane fixing one of theirs never reds mine.
const OTHER_LANE_KNOWN: Array[String] = [
	"test_an_empty_grid_has_no_row_minus_one.gd",
	"test_autobattle_editor_pad_value_dial_regression.gd",
	"test_battle_captions_are_not_nintendo_only.gd",
	"test_dial_reached_by_real_axis_routing_regression.gd",
	"test_input_handling_regression.gd",
	"test_input_reaches_the_handler_regression.gd",
	"test_legend_claims_are_wired_regression.gd",
	"test_low_hp_threshold_single_source_regression.gd",
	"test_shift_r_rename_is_reachable_regression.gd",
	"test_the_stick_steps_once_in_the_rule_editors.gd",
]


func test_the_two_hop_scan_can_actually_fire() -> void:
	# Same control the hop-1 arm carries, for the same reason: "0 offenders" and "the scan never
	# matched" are the same green. Floor by REASON — AutogrindGridEditor is the script that carried
	# the real write, so if the derivation stops naming it, every count below is about an empty set.
	var reachers := _indirect_reachers()
	assert_gt(reachers.size(), 0, "derived ZERO indirect reachers — the scan is broken, not the code")
	assert_true("res://src/ui/autogrind/AutogrindGridEditor.gd" in reachers,
		"control: AutogrindGridEditor reaches set_autogrind_rules via _save_rules and is the script that produced the 2026-09-17 write — its absence means the derivation broke")


func test_no_autogrind_test_reaches_a_saver_through_a_ui_node() -> void:
	var mine: Array[String] = []
	var theirs: Array[String] = []
	for f in _two_hop_offenders():
		if f.begins_with("test_autogrind"):
			mine.append(f)
		else:
			theirs.append(f)

	assert_eq(mine, [],
		"These autogrind tests instantiate a script that reaches an AutogrindSystem saver, without setting the flag — the shape that wrote three player-data files on 2026-09-17 while the one-hop arm above stayed green. Add `AutogrindSystem._test_disable_persistence = true` in before_each: %s" % str(mine))

	var unknown: Array[String] = []
	for f in theirs:
		if not (f in OTHER_LANE_KNOWN):
			unknown.append(f)
	assert_eq(unknown, [],
		"New out-of-lane tests reach an autogrind saver through a UI node: %s — report to the owning lane and add to OTHER_LANE_KNOWN with the measurement" % str(unknown))
