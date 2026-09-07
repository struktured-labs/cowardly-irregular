extends GutTest

## Regression: TitleScreen's CONTINUE row surfaces a save-context subtitle
## ("Chapter — Location") below the main label, so the player knows what
## save they'd resume before pressing A. Subtitle is built live from
## SaveSystem metadata so it always reflects the most-recent slot.

const TITLE_SCREEN_PATH := "res://src/ui/TitleScreen.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _build_continue_subtitle_via(title_screen, mock_info: Dictionary) -> String:
	# Stub SaveSystem.get_save_info to return mock_info, then call the
	# subtitle builder. Restores the original lambda after.
	# (We can't easily monkey-patch the autoload, so we just exercise the
	# helper directly with the SaveSystem global as-is. The test below
	# verifies the source-level shape; this lets us at least confirm the
	# helper returns a string even with empty/no-save state.)
	return title_screen._build_continue_subtitle()


func test_continue_row_passes_subtitle_in_menu_item() -> void:
	var text = _read(TITLE_SCREEN_PATH)
	# CONTINUE menu_items entry must include a `subtitle` key populated by
	# _build_continue_subtitle(). Catches anyone reverting the row back to
	# the legacy {"id":"continue","label":"CONTINUE","enabled":true} form.
	var build_idx = text.find("\"id\": \"continue\"")
	assert_true(build_idx > -1, "menu_items must still register a continue row")
	if build_idx == -1:
		return
	var window = text.substr(build_idx, 200)
	assert_true(window.find("\"subtitle\"") > -1,
		"continue menu_items entry must include a subtitle key")
	assert_true(window.find("_build_continue_subtitle()") > -1,
		"subtitle value must come from _build_continue_subtitle()")


func test_create_menu_row_renders_subtitle_when_present() -> void:
	var text = _read(TITLE_SCREEN_PATH)
	# Look inside _create_menu_row for subtitle-handling logic.
	var fn_idx = text.find("func _create_menu_row(")
	assert_true(fn_idx > -1, "_create_menu_row must exist")
	var fn_end = text.find("\n\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1200)
	# Must add a Subtitle child node when subtitle is non-empty.
	assert_true(body.find("\"Subtitle\"") > -1,
		"_create_menu_row must add a child Label named 'Subtitle' when present")
	# Must bump row height when subtitle is set (44px vs 28px).
	assert_true(body.find("44 if subtitle") > -1 or body.find("if subtitle != \"\"") > -1,
		"Row height must grow when subtitle is non-empty so the two labels don't overlap")


func test_build_continue_subtitle_handles_missing_save_safely() -> void:
	# Behavioral: the helper must not crash when SaveSystem reports no
	# save (returns empty string). This covers the fresh-install path
	# where _check_for_save() somehow returns true but the metadata is
	# missing or empty.
	var script = load(TITLE_SCREEN_PATH)
	var t = script.new()
	add_child_autofree(t)
	# Call directly — depends on whatever SaveSystem state happens to be
	# in this test run. We only assert it returns a string, doesn't crash.
	var result = t._build_continue_subtitle()
	assert_typeof(result, TYPE_STRING,
		"_build_continue_subtitle must return a String (even when empty) — never crash")


func test_subtitle_format_when_chapter_and_location_present() -> void:
	# Source-level: the "chapter — location" format must be in the helper.
	# Catches anyone reverting to just location or just chapter.
	var text = _read(TITLE_SCREEN_PATH)
	assert_true(text.find("\"%s — %s\" % [chapter, location]") > -1,
		"Subtitle format with both fields must be `<chapter> — <location>` (em-dash separator)")
	# Each degrade path must exist so a partial save doesn't fall through
	# to "Chapter:  — Location:" garbled output.
	assert_true(text.find("if location != \"\":") > -1,
		"Degrade path: location-only must be supported when chapter is empty")
	assert_true(text.find("if chapter != \"\":") > -1,
		"Degrade path: chapter-only must be supported when location is empty")
