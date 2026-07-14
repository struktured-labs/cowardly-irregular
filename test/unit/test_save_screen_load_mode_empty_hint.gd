extends GutTest

## tick 196: SaveScreen._build_empty_slot now differentiates
## SAVE-mode vs LOAD-mode empty slots visually.
##
## Pre-fix: empty slots read "- Empty -" in EMPTY_COLOR (gray)
## in both modes. In SAVE mode that means "available target".
## In LOAD mode it means "you can't load this", but the visual
## was identical — players hovered/clicked and got an error
## Toast as their first feedback ("Load failed: that slot has
## no save"). Trial-and-error discoverability.
##
## Fix: in LOAD mode, the empty label reads "- No save -" in
## DISABLED_COLOR plus a second-line "(nothing to load)" subhint.
## In SAVE mode, label stays "- Empty -" in EMPTY_COLOR (still a
## valid save target). The Toast handler remains as fallback,
## but it's no longer the FIRST signal the user gets.

const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _empty_body() -> String:
	var src := _read(SAVE_SCREEN)
	var fn_idx: int = src.find("func _build_empty_slot")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	return src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)


# ── Mode-aware empty label ────────────────────────────────────────────

func test_save_mode_keeps_empty_label() -> void:
	# Pin: SAVE mode still shows "- Empty -" (valid target).
	var body := _empty_body()
	assert_true(body.contains("\"- Empty -\" if current_mode == Mode.SAVE"),
		"SAVE mode must keep '- Empty -' (valid save target)")


func test_load_mode_swaps_to_no_save_label() -> void:
	# Pin: LOAD mode shows "- No save -" (clear unavailability).
	var body := _empty_body()
	assert_true(body.contains("else \"- No save -\""),
		"LOAD mode must swap label to '- No save -'")


func test_load_mode_color_is_disabled() -> void:
	# Pin: LOAD mode uses DISABLED_COLOR (greyed out) for the
	# label so it visually reads as not-a-target.
	var body := _empty_body()
	assert_true(body.contains("EMPTY_COLOR if current_mode == Mode.SAVE else DISABLED_COLOR"),
		"empty label color must switch to DISABLED_COLOR in LOAD mode")


# ── Subhint ───────────────────────────────────────────────────────────

func test_load_mode_adds_subhint() -> void:
	# Pin: LOAD mode adds a second line "(nothing to load)" in
	# DISABLED_COLOR — extra visual weight.
	var body := _empty_body()
	assert_true(body.contains("if current_mode == Mode.LOAD:"),
		"LOAD-mode subhint must be guarded by current_mode == Mode.LOAD")
	assert_true(body.contains("hint.text = \"(nothing to load)\""),
		"subhint must read '(nothing to load)'")
	assert_true(body.contains("hint.add_theme_color_override(\"font_color\", DISABLED_COLOR)"),
		"subhint must use DISABLED_COLOR")


func test_save_mode_no_subhint() -> void:
	# Negative pin: SAVE mode must NOT add the "(nothing to load)"
	# hint — overwriting an empty slot IS the valid action.
	var body := _empty_body()
	# The subhint creation must live inside the `if current_mode == Mode.LOAD:`
	# block. We verify by checking the hint creation is preceded within
	# 200 chars by the LOAD check.
	var hint_idx: int = body.find("hint.text = \"(nothing to load)\"")
	assert_gt(hint_idx, -1)
	var pre: String = body.substr(max(0, hint_idx - 300), 300)
	assert_true(pre.contains("if current_mode == Mode.LOAD:"),
		"subhint creation must be inside the LOAD-mode guard")


# ── Pre-existing behavior preserved ───────────────────────────────────

func test_slot_label_unchanged() -> void:
	var body := _empty_body()
	# Slot N / Quick Save header still present, color still DISABLED_COLOR.
	assert_true(body.contains("_slot_label(slot)"),
		"slot header label preserved (unified helper covers Slot N / Quick Save / Autosave)")
	assert_true(body.contains("slot_label.add_theme_color_override(\"font_color\", DISABLED_COLOR)"),
		"slot header color preserved")


func test_load_handler_still_shows_toast_fallback() -> void:
	# The visual upfront is the primary signal; the Toast handler
	# stays as a defensive fallback (e.g., race between menu build
	# and save-file delete). Verify it's still wired.
	var src := _read(SAVE_SCREEN)
	assert_true(src.contains("Toast.show_warning(self, \"Load failed: that slot has no save\")"),
		"_handle_confirm's Toast fallback preserved")


# ── Position separation ───────────────────────────────────────────────

func test_empty_label_position_makes_room_for_subhint() -> void:
	# Pin: empty label moved up slightly (y - 14 vs old y - 10) so
	# the subhint at y + 10 doesn't visually collide.
	var body := _empty_body()
	assert_true(body.contains("Vector2(panel_size.x / 2 - 40, panel_size.y / 2 - 14)"),
		"empty label moved up 4px to make room for subhint")
