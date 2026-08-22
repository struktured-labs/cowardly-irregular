extends GutTest

## Snapshot of the developer's REAL slot 98, restored from after_each so an
## abort mid-test cannot leave his live autosave as harness state
## (@cowir-overworld msg-3773). Same abort-skips-the-restore class fixed in the
## win-condition teardown tonight — worse here, because the restore was not even
## in a teardown to be skipped.
var _auto_path: String = ""
var _had_real_autosave: bool = false
var _real_autosave_backup: PackedByteArray = PackedByteArray()
var _snapshot_taken: bool = false


func after_each() -> void:
	if not _snapshot_taken:
		return
	_snapshot_taken = false
	if _had_real_autosave:
		var f := FileAccess.open(_auto_path, FileAccess.WRITE)
		if f:
			f.store_buffer(_real_autosave_backup)
			f.close()
	elif SaveSystem and SaveSystem.save_exists(SaveSystem.AUTO_SAVE_SLOT):
		SaveSystem.delete_save(SaveSystem.AUTO_SAVE_SLOT)

## Regression: auto_save() must NEVER write to a manual user save slot.
##
## Bug (high severity, silent data loss): auto_save() wrote to slot 0,
## which SaveScreen presents to the player as "Slot 1" (panels are labeled
## "Slot %d" % (slot + 1)). auto_save_enabled defaults to true and is fired
## both by SaveSystem._process every auto_save_interval (300s) AND by
## GameLoop on every zone/area transition. So a player who manually saved
## their run in "Slot 1" lost it 5 minutes later — or immediately on the
## next area change — with no overwrite warning.
##
## Fix: route auto-saves to a dedicated AUTO_SAVE_SLOT (98), kept out of the
## user slot range range(MAX_SAVE_SLOTS) so manual saves are never clobbered.
## has_save() / get_most_recent_slot() also learn about AUTO_SAVE_SLOT so a
## fresh launch's "Continue" can still resume from the latest auto-save.


const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


# The reserved auto-save slot constant must exist and live OUTSIDE the
# manual user slot range (0..MAX_SAVE_SLOTS-1).
func test_auto_save_slot_constant_outside_user_range() -> void:
	assert_true("AUTO_SAVE_SLOT" in SaveSystem,
		"SaveSystem must define a dedicated AUTO_SAVE_SLOT constant")
	assert_true(SaveSystem.AUTO_SAVE_SLOT >= SaveSystem.MAX_SAVE_SLOTS,
		"AUTO_SAVE_SLOT (%d) must be >= MAX_SAVE_SLOTS (%d) so it never " %
		[SaveSystem.AUTO_SAVE_SLOT, SaveSystem.MAX_SAVE_SLOTS] +
		"collides with a manual user slot")
	# And it must not alias the quick-save slot either.
	assert_ne(SaveSystem.AUTO_SAVE_SLOT, SaveSystem.QUICK_SAVE_SLOT,
		"AUTO_SAVE_SLOT must be distinct from QUICK_SAVE_SLOT")


# Source-level guard: auto_save() must target AUTO_SAVE_SLOT, never slot 0
# (or any manual slot). This pins the routing so a future refactor can't
# silently re-introduce the slot-0 clobber.
func test_auto_save_routes_to_auto_save_slot() -> void:
	var src = _read(SAVE_SYSTEM_PATH)
	var idx = src.find("func auto_save")
	assert_gt(idx, -1, "auto_save() must exist")
	var body = src.substr(idx, 600)
	assert_string_contains(body, "save_game(AUTO_SAVE_SLOT)",
		"auto_save() must write to AUTO_SAVE_SLOT, not a manual user slot")
	# Anti-pattern: the old slot-0 routing must be gone.
	assert_eq(body.find("return save_game(0)"), -1,
		"auto_save() must NOT route to slot 0 (rendered to player as 'Slot 1')")


# has_save() (title-screen Continue gate) must recognize an auto-save-only
# state, otherwise a player whose only save is the auto-save sees no Continue.
func test_has_save_considers_auto_save_slot() -> void:
	var src = _read(SAVE_SYSTEM_PATH)
	var idx = src.find("func has_save")
	assert_gt(idx, -1)
	var body = src.substr(idx, 400)
	assert_string_contains(body, "save_exists(AUTO_SAVE_SLOT)",
		"has_save() must also check AUTO_SAVE_SLOT so Continue appears when " +
		"only an auto-save exists")


# get_most_recent_slot() must include AUTO_SAVE_SLOT in the recency search.
func test_most_recent_slot_considers_auto_save_slot() -> void:
	var src = _read(SAVE_SYSTEM_PATH)
	var idx = src.find("func get_most_recent_slot")
	assert_gt(idx, -1)
	var body = src.substr(idx, 800)
	# 2026-08-22: was pinned to the literal get_save_info(AUTO_SAVE_SLOT) call, which a
	# refactor to a collected candidate list broke while preserving the behaviour. Pin the
	# constant's presence, not the call shape.
	assert_string_contains(body, "AUTO_SAVE_SLOT",
		"get_most_recent_slot() must consider AUTO_SAVE_SLOT so Continue can " +
		"resume from the latest auto-save")


# End-to-end runtime guard: an actual auto_save() must land in AUTO_SAVE_SLOT
# and leave every manual user slot untouched. We snapshot the manual slots,
# run auto_save(), and assert none of them gained/changed a file because of it.
func test_auto_save_does_not_touch_manual_slots_runtime() -> void:
	# can_quick_save() requires a non-active battle; in the headless test
	# harness no battle is active, so auto_save() should proceed.
	if BattleManager and BattleManager.is_battle_active():
		pass_test("battle active in harness — source-level guards cover routing")
		return

	# 2026-07-16 test-isolation rule (feedback_test_isolation_from_user_save): this leg calls the REAL auto_save() and its cleanup used to DELETE the developer's real slot-98 — struktured's live autosave vanished after every full-suite run. Snapshot the real file first; restore it in cleanup.
	# Snapshot into MEMBERS and restore from after_each, not inline below. The
	# restore used to be straight-line code after two assert loops: a failing
	# assert, a crash, or a killed run between auto_save() and it left the real
	# slot 98 holding harness state. after_each runs even when the body aborts.
	var auto_path := "user://saves/save_%02d.json" % SaveSystem.AUTO_SAVE_SLOT
	_auto_path = auto_path
	_had_real_autosave = FileAccess.file_exists(auto_path)
	_real_autosave_backup = FileAccess.get_file_as_bytes(auto_path) if _had_real_autosave else PackedByteArray()
	_snapshot_taken = true

	# Record which manual slots exist (and their mtimes) before auto_save().
	var before := {}
	for slot in range(SaveSystem.MAX_SAVE_SLOTS):
		var path = "user://saves/save_%02d.json" % slot
		before[slot] = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1

	var ok = SaveSystem.auto_save()
	# auto_save() returns false only if can_quick_save() blocks; if it ran,
	# verify it produced the AUTO_SAVE_SLOT file.
	if ok:
		assert_true(SaveSystem.save_exists(SaveSystem.AUTO_SAVE_SLOT),
			"a successful auto_save() must create the AUTO_SAVE_SLOT file")

	# No manual slot may have been created or modified by the auto-save.
	for slot in range(SaveSystem.MAX_SAVE_SLOTS):
		var path = "user://saves/save_%02d.json" % slot
		var now = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1
		assert_eq(now, before[slot],
			"auto_save() must NOT create or overwrite manual slot %d" % slot)

	# Restore happens in after_each — NEVER inline here. Inline is what made an
	# abort between auto_save() above and the restore leave his live slot 98 as
	# harness state.
