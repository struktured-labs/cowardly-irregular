extends GutTest

## `InputProfileManager.load_config()` ASSIGNS `profile_chosen_by_user` and NOTHING ever sets it
## back. It is not self-healing the way a pitch or a binding is — the next call does not overwrite
## it, so once a test file turns it on it stays on for the whole process.
##
## ⚠️ THE PREMISE ARM USED TO PIN THE LITERAL `= true`, AND A CORRECT FIX RED IT. The loader now
## reads the flag from the config rather than inferring it from the profile's presence, because a
## SAVED profile is not a CHOSEN one — three of four `save_config` callers are not profile choices,
## so toggling one setting permanently disabled pad autodetection. The leak this file defends is
## unchanged: the loader still writes the flag, so a test that calls it still pollutes the process.
## Only the SPELLING moved, which is exactly the shape this lane spent the day removing — the arm
## now asserts the loader ASSIGNS the flag, which is the property that makes a leak possible.
##
## ⛔ WHAT A LEAKED `true` COSTS: `_on_joy_connection_changed` runs autodetect only
## `if connected and not profile_chosen_by_user` (:189). A later file that connects a pad and
## expects its profile to be detected silently gets no detection — and the pad-connection signal
## still fires, so every caption arm downstream still passes. The failure is invisible from the
## side anyone would look at.
##
## 🔑 WHY THE TWO FILES THAT LEAKED LOOKED COMPLETE: both restore `active_profile`, both restore
## `custom_bindings`, both snapshot and rewrite the on-disk config with real care. Those are the
## things the file WRITES. The flag is written three calls down, by the loader, and naming it was
## the one thing a reading of either file would not produce.
##
## Measured before this guard: 53 test files touch the profile manager's state, 51 were clean,
## these 2 leaked, and all 5 downstream files that consume the flag survived the pollution today.
## So the fix is latent correctness — worth making because the leak is STICKY and the consumer set
## grows, not because anything is red.
##
## The corpus is DERIVED and CODE-ONLY. A hand-list would have held the two files that existed
## when it was written; and a raw text scan reports four, because two source-reading tests name
## `InputProfileManager.load_config` in a section-header comment and never call it.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const TEST_DIR := "res://test/unit"
const CALL := "InputProfileManager.load_config("
const FLAG := "profile_chosen_by_user"


## ⛔ THE RESTORE LIVES IN A TEARDOWN, NOT AT THE END OF THE ARM — AND IT DID NOT, UNTIL I RAN THIS
## LANE'S OWN FIXTURE-STRAND LENS AGAINST MY OWN FILE. The driven arm below writes a fixture
## `controls.json`, calls `load_config()`, and moves `profile_chosen_by_user` and `active_profile`.
## Restoring those at the END of the arm means a GDScript error anywhere above the restore strands
## all three for every later test in the process.
##
## 🔑 AND THE STRANDED THING IS THE SUBJECT OF THIS VERY FILE: a leaked `profile_chosen_by_user`
## silently disables pad autodetection for every file that runs after. I wrote a guard about that
## leak whose own repair could cause it.
var _had_config: bool = false
var _config_raw: String = ""
var _saved_flag: bool = false
var _saved_profile: String = ""

## ⛔ THE CATCHER'S BASELINE IS CAPTURED ONCE, NOT PER ARM, AND MY FIRST VERSION GOT THIS WRONG.
## `before_each` runs before the CATCHER too, so comparing against it re-snapshots whatever the
## pollution left and the arm compares a polluted value with itself. Measured: with the teardown
## removed and an abort planted, the catcher stayed GREEN. A pristine `before_all` baseline cannot
## be refreshed by the damage it is meant to detect.
var _pristine_flag: bool = false
var _pristine_had_config: bool = false


func before_all() -> void:
	_pristine_flag = InputProfileManager.profile_chosen_by_user
	_pristine_had_config = FileAccess.file_exists(InputProfileManager.CONFIG_PATH)


func before_each() -> void:
	_had_config = FileAccess.file_exists(InputProfileManager.CONFIG_PATH)
	_config_raw = FileAccess.get_file_as_string(InputProfileManager.CONFIG_PATH) if _had_config else ""
	_saved_flag = InputProfileManager.profile_chosen_by_user
	_saved_profile = InputProfileManager.active_profile


func after_each() -> void:
	if _had_config:
		var w := FileAccess.open(InputProfileManager.CONFIG_PATH, FileAccess.WRITE)
		if w:
			w.store_string(_config_raw)
			w.close()
	elif FileAccess.file_exists(InputProfileManager.CONFIG_PATH):
		DirAccess.remove_absolute(InputProfileManager.CONFIG_PATH)
	if _saved_profile != "":
		InputProfileManager.apply_profile(_saved_profile)
	InputProfileManager.profile_chosen_by_user = _saved_flag


## One function's body, bounded by the next top-level `func` rather than by a character count —
## a fixed width is the coincidental-value shape, and load_config is long enough to be cut by one.
func _func_body(src: String, header: String) -> String:
	var at: int = src.find(header)
	if at < 0:
		return ""
	var stop: int = src.find("\nfunc ", at + header.length())
	return src.substr(at, stop - at) if stop > at else src.substr(at)


## ⛔ THE PREMISE, DRIVEN RATHER THAN SCANNED — AND IT WENT VACUOUS AS A SCAN, TWICE, THE SAME WAY.
## v1 searched the whole file and `cycle_profile`'s `= true` satisfied it. v2 scoped to
## `load_config`'s body and pinned the literal `= true` — which red on a CORRECT change, because
## the loader now reads the flag from the config instead of inferring it. Loosening that to
## `= ` went vacuous immediately: the v1-migration line `profile_chosen_by_user = false` lives in
## the same body, so deleting the real write left it satisfying the assert. Measured — the arm
## passed 2/2 against a loader that no longer wrote the flag at all.
##
## ✅ So it is driven. Calling the loader against a config that SAYS false and one that SAYS true
## proves the loader assigns the flag, in both directions, which is the entire premise this file
## rests on — and it cannot be satisfied by a neighbouring line, a rename, or a reword.
func test_the_manager_still_sets_the_flag_on_load() -> void:
	for want in [false, true]:
		var cfg := {
			"version": 2,
			"active_profile": "8BitDo SN30",
			"nintendo_mode": InputProfileManager.nintendo_mode,
			"custom_bindings": {},
			"profile_chosen_by_user": want,
		}
		var f := FileAccess.open(InputProfileManager.CONFIG_PATH, FileAccess.WRITE)
		assert_not_null(f, "CONTROL: the fixture config must be writable")
		f.store_string(JSON.stringify(cfg, "\t"))
		f.close()
		InputProfileManager.profile_chosen_by_user = not want
		InputProfileManager.load_config()
		assert_eq(InputProfileManager.profile_chosen_by_user, want,
			"premise: load_config must ASSIGN %s — it read a config saying %s and left the flag at %s. "
				% [FLAG, want, InputProfileManager.profile_chosen_by_user]
			+ "Without that write there is nothing to leak and nothing to restore, and this whole "
			+ "file is a rule about nothing.")




## The consequence path, still a source claim because it is about a GATE rather than a write: if
## autodetect stops consulting the flag, a leaked `true` is harmless and this file is obsolete.
func test_the_leak_still_costs_something() -> void:
	var src: String = GdSource.code_of("res://src/input/InputProfileManager.gd")
	assert_gt(src.length(), 0, "CONTROL: must be able to read the manager's source")
	assert_true(src.contains("connected and not %s" % FLAG),
		"premise: pad-connection autodetect must still be gated on %s — that gate is the reason " % FLAG
		+ "a leaked `true` costs anything")


func test_every_config_loading_test_restores_the_choice_flag() -> void:
	var callers: Array = []
	var unrestored: Array = []
	var unread: Array = []
	for file_name in DirAccess.get_files_at(TEST_DIR):
		if not file_name.ends_with(".gd"):
			continue
		var path: String = "%s/%s" % [TEST_DIR, file_name]
		## Cheap reject first: code_of on every file in the directory is wasted work when the
		## overwhelming majority never mention the call at all.
		var raw: String = FileAccess.get_file_as_string(path)
		## ⛔ A FAILED READ IS A SKIP, AND THE SKIP HAPPENS BEFORE THE DEFECT SCAN.
		## get_file_as_string returns "" on failure, so a file that cannot be read misses CALL,
		## `continue`s, and never reaches `unrestored` — the leaker drops out of the list of
		## leakers. Recorded per file rather than floored in aggregate: `callers.size() >= 2`
		## below is satisfied by two files and cannot see a third go dark.
		if raw.strip_edges().is_empty():
			unread.append(file_name)
			continue
		if raw.find(CALL) == -1:
			continue
		## ⛔ CODE ONLY. A raw scan finds four files here; two of them are source-READING tests
		## that name the function in a `# ── InputProfileManager.load_config ──` header and in a
		## path constant, and never invoke it. Requiring a restore from a file that cannot leak is
		## the "gate wider than the evidence" shape, and it teaches the next author to add a line
		## that does nothing.
		var code: String = GdSource.code_of(path)
		if code.find(CALL) == -1:
			continue
		callers.append(file_name)
		if code.find(FLAG) == -1:
			unrestored.append(file_name)

	## CONTROL: the derivation must FIND the callers. An empty corpus satisfies the assert below
	## perfectly — the shrinking-corpus shape, which is how a derived guard goes quietly vacuous.
	assert_true(callers.size() >= 2,
		"CONTROL: expected at least the two known config-loading tests, derived %s" % [callers])
	assert_true(unread.is_empty(),
		"%s enumerated but read EMPTY. The cheap-reject above treats an unreadable file as one " % [unread]
		+ "that does not call load_config, so a leaker would be skipped rather than reported.")
	assert_true(unrestored.is_empty(),
		"test file(s) %s call load_config() without ever naming %s — the loader sets it, nothing " % [unrestored, FLAG]
		+ "resets it, and a leaked `true` silently disables pad autodetection for every later file")


## ⛔ THE STRAND CATCHER, DECLARED LAST BECAUSE DECLARATION ORDER IS RUN ORDER. Without it "I moved
## the restore into a teardown" is unfalsifiable: an arm that aborts still reports PASSING, so the
## hazard and its repair look identical on screen (cowir-music, 2026-09-18). This arm runs after the
## driving arm and asserts the shared state came back.
func test_zz_the_shared_config_state_was_handed_back() -> void:
	assert_eq(InputProfileManager.profile_chosen_by_user, _pristine_flag,
		"%s was left at %s by an earlier arm — the teardown did not run, and every later file in "
			% [FLAG, InputProfileManager.profile_chosen_by_user]
		+ "this process now inherits it. That is the exact leak this file exists to guard.")
	assert_eq(FileAccess.file_exists(InputProfileManager.CONFIG_PATH), _pristine_had_config,
		"the fixture config was left on disk (or the real one deleted) — %s existed at file start: %s"
			% [InputProfileManager.CONFIG_PATH, _pristine_had_config])
