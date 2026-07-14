extends GutTest

## Boss-defeat used to commit story flags to in-memory GameState but
## NOT trigger an auto-save. The next save backstop was either a zone
## transition or the 5-min periodic timer. A crash in that window lost
## the boss-defeat flag entirely — and these are the highest-stakes
## fights in the game (Rat King → Mordaine).
##
## Fix: _apply_pending_boss_defeat now ends with an auto_save() call so
## the win lands on disk before the player even confirms the victory
## screen.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_apply_pending_boss_defeat_calls_auto_save() -> void:
	var src := _read(GAME_LOOP_PATH)
	var idx := src.find("func _apply_pending_boss_defeat")
	assert_gt(idx, -1, "_apply_pending_boss_defeat must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("SaveSystem.auto_save()"),
		"_apply_pending_boss_defeat must auto_save() so boss flags survive a crash")
	# Must be guarded — SaveSystem can be null on weird boot paths / unit tests.
	assert_true(body.contains("SaveSystem and SaveSystem.has_method(\"auto_save\")"),
		"the auto_save() call must be guarded against missing SaveSystem")


func test_auto_save_lands_after_pending_clear() -> void:
	# The auto-save must happen AFTER the pending_boss_defeat dict is
	# cleared. Otherwise a save in the middle of mutation could persist
	# a half-applied state.
	var src := _read(GAME_LOOP_PATH)
	var idx := src.find("func _apply_pending_boss_defeat")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	var clear_at := body.find("GameState.pending_boss_defeat = {}")
	var save_at := body.find("SaveSystem.auto_save()")
	assert_gt(clear_at, -1, "pending_boss_defeat must be cleared in this function")
	assert_gt(save_at, -1, "auto_save call must exist in this function")
	assert_gt(save_at, clear_at,
		"auto_save() must run AFTER pending_boss_defeat is cleared, not before")
