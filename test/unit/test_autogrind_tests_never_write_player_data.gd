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
const SAVERS: Array[String] = ["_save_autogrind_profiles", "_save_csi_data", "_save_session_history"]


## Every AutogrindSystem function whose body reaches a user:// writer, read from source.
func _persisting_functions() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SYSTEM_PATH)
	assert_ne(src, "", "could not read AutogrindSystem — this check would silently pass on an empty corpus")
	var out: Array[String] = []
	var idx: int = 0
	while true:
		var start: int = src.find("\nfunc ", idx)
		if start < 0:
			break
		var next: int = src.find("\nfunc ", start + 1)
		var body: String = src.substr(start, (next - start) if next > 0 else -1)
		var name: String = body.substr(6, body.find("(") - 6).strip_edges()
		idx = start + 1
		if name.begins_with("_save"):
			continue
		for s in SAVERS:
			if body.contains(s + "("):
				if not (name in out):
					out.append(name)
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
		for fn in persisting:
			if src.contains("AutogrindSystem." + fn + "("):
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
