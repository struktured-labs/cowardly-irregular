extends GutTest

## tick 202: TitleScreen.CONTINUE row now surfaces WHICH slot
## will resume — Slot 1/2/3, Quick Save, or Auto-Save.
##
## Pre-fix the subtitle showed only "Chapter — Location" derived
## from get_most_recent_slot()'s pick. Players had no way to tell
## whether Continue would load their carefully-curated Slot 2
## or the auto-save from 5 seconds ago when they panic-quit.
## Especially impactful for players juggling multiple narrative
## branches across slots.
##
## Fix: prepend a slot label always, format the subtitle as
## "Slot N · Chapter — Location" (with reasonable degradation
## when chapter / location are missing).

const TITLE_SCREEN := "res://src/ui/TitleScreen.gd"


func _cls():
	return load(TITLE_SCREEN)


# ── _format_continue_slot_label helper ─────────────────────────────────

func test_manual_slot_zero_one_indexed() -> void:
	# Pin: slot 0 → "Slot 1" (one-indexed for users), slot 1 → "Slot 2", etc.
	assert_eq(_cls()._format_continue_slot_label(0), "Slot 1",
		"slot 0 displays as 'Slot 1' (one-indexed)")
	assert_eq(_cls()._format_continue_slot_label(1), "Slot 2",
		"slot 1 → 'Slot 2'")
	assert_eq(_cls()._format_continue_slot_label(2), "Slot 3",
		"slot 2 → 'Slot 3'")


func test_quick_save_slot_named() -> void:
	# Pin: QUICK_SAVE_SLOT (99) → "Quick Save".
	if not SaveSystem or not ("QUICK_SAVE_SLOT" in SaveSystem):
		pending("SaveSystem not available")
		return
	assert_eq(_cls()._format_continue_slot_label(SaveSystem.QUICK_SAVE_SLOT), "Quick Save",
		"QUICK_SAVE_SLOT → 'Quick Save'")


func test_auto_save_slot_named() -> void:
	# Pin: AUTO_SAVE_SLOT (98) → "Auto-Save".
	if not SaveSystem or not ("AUTO_SAVE_SLOT" in SaveSystem):
		pending("SaveSystem not available")
		return
	assert_eq(_cls()._format_continue_slot_label(SaveSystem.AUTO_SAVE_SLOT), "Auto-Save",
		"AUTO_SAVE_SLOT → 'Auto-Save'")


func test_negative_slot_returns_empty() -> void:
	# Defensive: get_most_recent_slot returns -1 for "no save found".
	# The helper should handle that without crashing.
	assert_eq(_cls()._format_continue_slot_label(-1), "",
		"slot < 0 → empty string (no crash)")


func test_unknown_high_slot_falls_back_to_slot_n() -> void:
	# Pin: a slot that isn't QUICK / AUTO and isn't in 0..MAX_SLOTS
	# still gets a generic "Slot N" label rather than empty/crash.
	# This is forward-compat for MAX_SAVE_SLOTS growth.
	var label: String = _cls()._format_continue_slot_label(5)
	assert_eq(label, "Slot 6",
		"unknown high slot → generic 'Slot N+1' (one-indexed)")


# ── Subtitle composition ──────────────────────────────────────────────

func test_subtitle_format_pin_slot_then_detail() -> void:
	# Pin: when both slot label and detail are present, format is
	# "Slot N · Chapter — Location" with middle-dot separator.
	var src: String = FileAccess.get_file_as_string(TITLE_SCREEN)
	assert_true(src.contains("return \"%s · %s\" % [slot_label, detail]"),
		"subtitle must join slot_label and detail with ' · '")


func test_subtitle_falls_back_to_slot_only_when_no_detail() -> void:
	# Pin: when detail is empty (corrupted save, older format with no
	# chapter/location keys), subtitle still shows "Slot N".
	var src: String = FileAccess.get_file_as_string(TITLE_SCREEN)
	# In the new logic, the early-returns yield slot_label alone when
	# get_save_info isn't available or info is empty.
	assert_true(src.contains("if not SaveSystem.has_method(\"get_save_info\"):\n\t\treturn slot_label"),
		"missing get_save_info → fall back to slot_label only")
	assert_true(src.contains("if info.is_empty():\n\t\treturn slot_label"),
		"empty save info → fall back to slot_label only")


func test_subtitle_skips_slot_only_when_slot_empty() -> void:
	# Pin: if slot_label is "" (returned by helper for negative slots),
	# subtitle falls through to detail-only — preserves pre-fix
	# behavior at this corner.
	var src: String = FileAccess.get_file_as_string(TITLE_SCREEN)
	assert_true(src.contains("if slot_label == \"\":\n\t\treturn detail"),
		"empty slot_label → return detail only")


# ── Pre-existing behavior preserved ────────────────────────────────────

func test_no_save_system_returns_empty() -> void:
	# Pre-existing: if SaveSystem isn't available, subtitle is "".
	var src: String = FileAccess.get_file_as_string(TITLE_SCREEN)
	assert_true(src.contains("if not SaveSystem or not SaveSystem.has_method(\"get_most_recent_slot\"):\n\t\treturn \"\""),
		"early-return on SaveSystem unavailability preserved")


func test_chapter_and_location_merge_preserved() -> void:
	# Pre-existing: when both chapter and location are present, they
	# merge as "Chapter — Location" with em-dash.
	var src: String = FileAccess.get_file_as_string(TITLE_SCREEN)
	assert_true(src.contains("detail = \"%s — %s\" % [chapter, location]"),
		"chapter + location em-dash merge preserved")


# ── Helper is static / unit-testable ───────────────────────────────────

func test_helper_is_static() -> void:
	var src: String = FileAccess.get_file_as_string(TITLE_SCREEN)
	assert_true(src.contains("static func _format_continue_slot_label(slot: int) -> String:"),
		"_format_continue_slot_label must be static for direct testing")


# ── Cross-pin: tick 197 SaveScreen date format unaffected ──────────────

func test_save_screen_date_helper_preserved() -> void:
	# Non-regression: my edit only touched TitleScreen — confirm
	# SaveScreen's tick 197 helper is still in place.
	var src: String = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")
	assert_true(src.contains("static func _format_save_date(save_date: String) -> String:"),
		"tick 197 _format_save_date preserved")
