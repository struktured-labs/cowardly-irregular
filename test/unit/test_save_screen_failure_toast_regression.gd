extends GutTest

## SaveScreen used to swallow save/load failures with only a menu_error
## SFX — no visible message. Player clicks Load, hears a beep, nothing
## else happens, menu stays open. Indistinguishable from "the button
## did nothing".
##
## Fix: Toast.show_warning on every failure path with a reason. Three
## distinct messages so the player can tell:
##   - load slot has no save
##   - load file unreadable / corrupt
##   - save failed (most commonly: in-battle)

const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_load_failure_toasts() -> void:
	var src := _read(SAVE_SCREEN)
	# Two distinct failure messages — slot-empty vs file-corrupt — so
	# the player can tell why their click did nothing.
	assert_true(src.contains("Load failed: that slot has no save"),
		"empty-slot Load click must Toast a 'no save' message")
	assert_true(src.contains("Load failed: save file unreadable or corrupt"),
		"corrupt-load failure must Toast a 'unreadable' message")


func test_save_failure_toasts() -> void:
	var src := _read(SAVE_SCREEN)
	assert_true(src.contains("Save failed"),
		"save failure must Toast a 'save failed' message (most commonly an in-battle save attempt)")


func test_failure_paths_still_play_menu_error_sfx() -> void:
	# Audio feedback is preserved alongside the new visual feedback —
	# don't replace the SFX, augment it.
	var src := _read(SAVE_SCREEN)
	# Both _do_save and the Mode.LOAD branch must play menu_error AND
	# Toast. Verify by counting occurrences in the file.
	var menu_error_count := 0
	var idx := 0
	while true:
		idx = src.find("menu_error", idx)
		if idx < 0:
			break
		menu_error_count += 1
		idx += 1
	assert_gte(menu_error_count, 3,
		"menu_error SFX must still fire alongside the Toast on each failure path (3+ sites: load-empty, load-corrupt, save-failed)")
