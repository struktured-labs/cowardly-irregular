extends GutTest

## tick 222: text size scale accessibility setting.
##
## New end-to-end feature:
##   1. GameState.text_size_scale (float, default 1.0)
##   2. SettingsMenu UI option (5 presets: 80% / 100% / 125% / 150% / 200%)
##   3. SaveSystem persists the setting alongside other UX prefs
##   4. CutsceneDialogue scales its 4 font sizes via _scaled_font_size
##
## Intentional scope limit: only CutsceneDialogue consumes the
## setting in this tick. Other surfaces (battle log, status menu,
## quest log) can be wired in follow-up ticks. The plumbing
## (GameState + SettingsMenu + SaveSystem persistence) is shared.

const GAME_STATE := "res://src/meta/GameState.gd"
const SETTINGS_MENU := "res://src/ui/SettingsMenu.gd"
const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── GameState plumbing ───────────────────────────────────────────────

func test_gamestate_var_declared_with_default_1() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("var text_size_scale: float = 1.0"),
		"GameState.text_size_scale must default to 1.0 (100%)")


# ── SettingsMenu plumbing ────────────────────────────────────────────

func test_settings_menu_presets_defined() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("const TEXT_SIZE_PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]"),
		"TEXT_SIZE_PRESETS const must list the 5 scale values")
	assert_true(src.contains("const TEXT_SIZE_LABELS: Array = [\"80%\", \"100%\", \"125%\", \"150%\", \"200%\"]"),
		"TEXT_SIZE_LABELS const must show readable percentages")


func test_settings_menu_loads_from_gamestate() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("if \"text_size_scale\" in GameState:"),
		"_ready must check for text_size_scale on GameState before reading")
	assert_true(src.contains("text_size_scale = float(GameState.text_size_scale)"),
		"_ready must load the value from GameState")
	assert_true(src.contains("text_size_index = TEXT_SIZE_PRESETS.find(text_size_scale)"),
		"_ready must compute the preset index for the UI")


func test_settings_menu_ui_item_added() -> void:
	# Pin the UI build site — the option setting goes after Screen Shake.
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("var text_size_idx: int = _settings_items.size()"),
		"text size option must use dynamic index (append at end of static section)")
	assert_true(src.contains("\"Text Size\""),
		"UI label must read 'Text Size'")
	assert_true(src.contains("\"Scale dialogue text size (accessibility)\""),
		"UI description must mention accessibility")


func test_settings_menu_click_handler_present() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("elif item[\"id\"] == \"text_size\":"),
		"click handler must branch on item id 'text_size'")
	assert_true(src.contains("text_size_index = clampi(text_size_index + delta, 0, TEXT_SIZE_PRESETS.size() - 1)"),
		"click handler must clampi the new index to preset range")
	assert_true(src.contains("text_size_scale = TEXT_SIZE_PRESETS[text_size_index]"),
		"click handler must update the scale value from preset")
	assert_true(src.contains("_save_text_size_scale()"),
		"click handler must call _save_text_size_scale")


func test_save_helper_writes_to_gamestate() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _save_text_size_scale")
	assert_gt(fn_idx, -1, "_save_text_size_scale must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("GameState.text_size_scale = text_size_scale"),
		"helper must write to GameState.text_size_scale")
	assert_true(body.contains("settings_changed.emit(\"text_size_scale\", text_size_scale)"),
		"helper must emit settings_changed signal")
	assert_true(body.contains("_persist_settings()"),
		"helper must persist via SaveSystem")


# ── SaveSystem persistence ───────────────────────────────────────────

func test_save_system_writes_text_size_scale() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("settings[\"text_size_scale\"] = GameState.text_size_scale"),
		"SaveSystem must persist text_size_scale to settings dict")
	# Guard so missing field on older builds doesn't crash.
	assert_true(src.contains("if \"text_size_scale\" in GameState:"),
		"persistence write must be guarded with `in GameState` check")


func test_save_system_loads_text_size_scale_with_clamp() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("if settings.has(\"text_size_scale\"):"),
		"load path must check for text_size_scale key")
	assert_true(src.contains("GameState.text_size_scale = clampf(float(settings[\"text_size_scale\"]), 0.8, 2.0)"),
		"load path must clampf to [0.8, 2.0] (the valid preset range)")


# ── CutsceneDialogue consumer ────────────────────────────────────────

func test_cutscene_dialogue_helper_present() -> void:
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("func _scaled_font_size(base: int) -> int:"),
		"_scaled_font_size helper must exist")


func test_cutscene_dialogue_helper_reads_gamestate_live() -> void:
	# Tick 223: CutsceneDialogue._scaled_font_size now delegates to
	# TextScale.scaled. The "reads GameState live" invariant moved
	# into TextScale (pinned in test_text_scale_util_extraction.gd).
	# Here we just confirm the delegation is in place.
	var src := _read(CUTSCENE_DIALOGUE)
	var fn_idx: int = src.find("func _scaled_font_size")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return TextScale.scaled(base)"),
		"helper must delegate to TextScale.scaled (post-tick 223 extraction)")


func test_cutscene_dialogue_helper_floor_min_1() -> void:
	# Tick 223: floor-at-1 invariant moved to TextScale.scaled. Pinned
	# in the test_text_scale_util_extraction.gd file instead.
	var src: String = FileAccess.get_file_as_string("res://src/ui/TextScale.gd")
	assert_true(src.contains("return max(1, int(round(float(base) * scale)))"),
		"floor at 1 moved into TextScale.scaled (post-tick 223)")


func test_cutscene_dialogue_4_font_sites_use_helper() -> void:
	# Pin: all 4 font_size overrides in _build_ui route through the helper.
	var src := _read(CUTSCENE_DIALOGUE)
	# 14pt speaker label
	assert_true(src.contains("_speaker_label.add_theme_font_size_override(\"font_size\", _scaled_font_size(18))"),
		"speaker label (14pt) must use _scaled_font_size")
	# 13pt text label
	assert_true(src.contains("_text_label.add_theme_font_size_override(\"normal_font_size\", _scaled_font_size(16))"),
		"text label (13pt) must use _scaled_font_size")
	# 10pt advance hint
	assert_true(src.contains("_advance_hint.add_theme_font_size_override(\"font_size\", _scaled_font_size(12))"),
		"advance hint (10pt) must use _scaled_font_size")
	# 18pt thinking label
	assert_true(src.contains("_thinking_label.add_theme_font_size_override(\"font_size\", _scaled_font_size(18))"),
		"thinking label (18pt) must use _scaled_font_size")


# ── Live behavior check ─────────────────────────────────────────────

func test_helper_actually_scales_at_runtime() -> void:
	# Live check: instantiate the dialogue and call the helper directly
	# with different GameState.text_size_scale values.
	if not GameState:
		pending("GameState autoload not available")
		return
	var cls = load(CUTSCENE_DIALOGUE)
	var dlg = cls.new()
	add_child_autofree(dlg)

	# 100% (default)
	GameState.text_size_scale = 1.0
	assert_eq(dlg._scaled_font_size(13), 13, "1.0x scale → base unchanged")
	# 150%
	GameState.text_size_scale = 1.5
	assert_eq(dlg._scaled_font_size(13), 20, "1.5x scale of 13 → 20 (rounded from 19.5)")
	# 200%
	GameState.text_size_scale = 2.0
	assert_eq(dlg._scaled_font_size(14), 28, "2.0x scale of 14 → 28")
	# 80%
	GameState.text_size_scale = 0.8
	assert_eq(dlg._scaled_font_size(10), 8, "0.8x scale of 10 → 8")
	# Reset to default for other tests.
	GameState.text_size_scale = 1.0
