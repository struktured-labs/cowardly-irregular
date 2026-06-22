extends GutTest

## TitleScreen._check_for_save used to check two hardcoded paths:
##   - user://save_data.json (legacy single-save)
##   - user://saves/save_00.json (slot 0)
## It missed AUTO_SAVE_SLOT (98) and QUICK_SAVE_SLOT entirely. A player
## whose only progress was auto-saved (periodic timer / zone-transition
## auto-save / boss-defeat auto-save) would see NO Continue button on
## the title screen, even though their save was right there on disk.
##
## Fix: defer to SaveSystem.has_save() which walks every slot including
## AUTO and QUICK. Hardcoded paths remain as a boot-path fallback.

const TITLE_SCREEN_PATH := "res://src/ui/TitleScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_check_for_save_defers_to_save_system() -> void:
	var src := _read(TITLE_SCREEN_PATH)
	var idx := src.find("func _check_for_save")
	assert_gt(idx, -1, "_check_for_save must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("SaveSystem.has_save()"),
		"_check_for_save must defer to SaveSystem.has_save() so AUTO_SAVE_SLOT and QUICK_SAVE_SLOT count")
	# Must be guarded — SaveSystem may not be ready on a very early boot.
	assert_true(body.contains("SaveSystem and SaveSystem.has_method(\"has_save\")"),
		"the SaveSystem call must be guarded against missing autoload")


func test_save_system_has_save_walks_auto_slot() -> void:
	# Pin the SaveSystem-side contract too — has_save MUST check the
	# auto-save slot, otherwise TitleScreen's delegation is for nothing.
	var src := _read("res://src/save/SaveSystem.gd")
	var idx := src.find("func has_save")
	assert_gt(idx, -1, "SaveSystem.has_save must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("AUTO_SAVE_SLOT"),
		"has_save() must check AUTO_SAVE_SLOT — otherwise auto-saves are invisible to the title")
	assert_true(body.contains("QUICK_SAVE_SLOT"),
		"has_save() must check QUICK_SAVE_SLOT too")
