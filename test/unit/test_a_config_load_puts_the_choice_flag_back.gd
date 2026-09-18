extends GutTest

## `InputProfileManager.load_config()` sets `profile_chosen_by_user = true` (InputProfileManager:665)
## and NOTHING ever sets it back. It is not self-healing the way a pitch or a binding is — the next
## call does not overwrite it, so once a test file turns it on it stays on for the whole process.
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


## One function's body, bounded by the next top-level `func` rather than by a character count —
## a fixed width is the coincidental-value shape, and load_config is long enough to be cut by one.
func _func_body(src: String, header: String) -> String:
	var at: int = src.find(header)
	if at < 0:
		return ""
	var stop: int = src.find("\nfunc ", at + header.length())
	return src.substr(at, stop - at) if stop > at else src.substr(at)


func test_the_manager_still_sets_the_flag_on_load() -> void:
	## ⛔ THE PREMISE, ASSERTED RATHER THAN ASSUMED. Every arm below defends against a write that
	## this line proves still happens. If the loader stops setting the flag, this guard becomes a
	## rule about nothing and should be deleted — it must say so instead of passing quietly.
	var src: String = GdSource.code_of("res://src/input/InputProfileManager.gd")
	assert_gt(src.length(), 0, "CONTROL: must be able to read the manager's source")
	## ⛔ SCOPED TO load_config's OWN BODY. My first version searched the whole file, and
	## `cycle_profile` writes `%s = true` too — so deleting the loader's write left the
	## other occurrence satisfying the assert and the premise arm passed on the mutation.
	var body: String = _func_body(src, "func load_config(")
	assert_gt(body.length(), 0, "CONTROL: load_config must still exist to have a body")
	assert_true(body.contains("%s = true" % FLAG),
		"premise: load_config must still SET %s — without that write there is nothing to restore" % FLAG)
	## The consequence path. If autodetect stops consulting the flag, a leaked `true` is harmless
	## and this whole file is obsolete — it must say that out loud rather than keep passing.
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
