extends GutTest

## tick 226: color-blind friendly accessibility palette for
## damage popups. Companion to tick 222's text size scale.
##
## Real impact: deuteranopia/protanopia (red-green color
## blindness, ~5% of males globally) struggles to distinguish
## the default damage popup colors:
##   heal = LIME_GREEN  (problematic — green is the affected end)
##   crit = ORANGE      (problematic — sits in the red-green spectrum)
##
## When color_blind_mode is on, DamageNumber swaps to a
## deuteranopia-safe palette:
##   heal → cyan/sky-blue Color(0.30, 0.70, 1.00)
##   crit → bright yellow Color(1.00, 0.95, 0.40)
## Both colors are distinguishable from each other AND from the
## default white damage popup under both deuteranopia and
## protanopia simulations.
##
## End-to-end plumbing:
##   GameState.color_blind_mode (bool, default false)
##   SettingsMenu toggle "Color-blind Friendly"
##   SaveSystem persists across sessions
##   DamageNumber._heal_color / _crit_color read live each spawn

const GAME_STATE := "res://src/meta/GameState.gd"
const SETTINGS_MENU := "res://src/ui/SettingsMenu.gd"
const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"
const DAMAGE_NUMBER := "res://src/ui/DamageNumber.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── GameState plumbing ───────────────────────────────────────────────

func test_gamestate_var_declared_default_false() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("var color_blind_mode: bool = false"),
		"GameState.color_blind_mode must default to false (preserve classic palette)")


# ── SettingsMenu plumbing ────────────────────────────────────────────

func test_settings_menu_load_from_gamestate() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("if \"color_blind_mode\" in GameState:"),
		"_ready must check for color_blind_mode on GameState before reading")
	assert_true(src.contains("color_blind_mode = bool(GameState.color_blind_mode)"),
		"_ready must load value coerced to bool")


func test_settings_menu_ui_toggle_added() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("\"Color-blind Friendly\""),
		"UI label must read 'Color-blind Friendly'")
	assert_true(src.contains("\"Cyan/yellow damage popups (vs green/orange)\""),
		"UI description must explain the visual change concretely")
	assert_true(src.contains("\"id\": \"color_blind_mode\""),
		"setting registers with id 'color_blind_mode'")


func test_settings_menu_click_handler_present() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("elif item[\"id\"] == \"color_blind_mode\":"),
		"click handler must branch on item id 'color_blind_mode'")
	assert_true(src.contains("color_blind_mode = not color_blind_mode"),
		"click handler must toggle the bool")
	assert_true(src.contains("_save_color_blind_mode_setting()"),
		"click handler must call save helper")


func test_save_helper_writes_to_gamestate() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _save_color_blind_mode_setting")
	assert_gt(fn_idx, -1, "_save_color_blind_mode_setting must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("GameState.color_blind_mode = color_blind_mode"),
		"helper must write to GameState.color_blind_mode")
	assert_true(body.contains("settings_changed.emit(\"color_blind_mode\", color_blind_mode)"),
		"helper must emit settings_changed signal")
	assert_true(body.contains("_persist_settings()"),
		"helper must persist via SaveSystem")


# ── SaveSystem persistence ───────────────────────────────────────────

func test_save_system_writes_color_blind_mode() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("settings[\"color_blind_mode\"] = GameState.color_blind_mode"),
		"SaveSystem must persist color_blind_mode")
	assert_true(src.contains("if \"color_blind_mode\" in GameState:"),
		"persistence write must be guarded with `in GameState` check")


func test_save_system_loads_color_blind_mode() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("if settings.has(\"color_blind_mode\"):"),
		"load path must check for color_blind_mode key")
	assert_true(src.contains("GameState.color_blind_mode = bool(settings[\"color_blind_mode\"])"),
		"load path must coerce to bool defensively")


# ── DamageNumber consumer ────────────────────────────────────────────

func test_damage_number_heal_color_helper_present() -> void:
	# Tick 228: color literals live in AccessibilityPalette now.
	# DamageNumber._heal_color just delegates.
	var src := _read(DAMAGE_NUMBER)
	assert_true(src.contains("func _heal_color() -> Color:"),
		"_heal_color helper must exist")
	var palette: String = FileAccess.get_file_as_string("res://src/ui/AccessibilityPalette.gd")
	assert_true(palette.contains("return Color(0.30, 0.70, 1.00)"),
		"accessibility heal color = cyan/sky-blue (in AccessibilityPalette)")
	assert_true(palette.contains("return Color.LIME_GREEN"),
		"default heal color preserved as LIME_GREEN (in AccessibilityPalette)")


func test_damage_number_crit_color_helper_present() -> void:
	# Tick 228: color literals live in AccessibilityPalette now.
	var src := _read(DAMAGE_NUMBER)
	assert_true(src.contains("func _crit_color() -> Color:"),
		"_crit_color helper must exist")
	var palette: String = FileAccess.get_file_as_string("res://src/ui/AccessibilityPalette.gd")
	assert_true(palette.contains("return Color(1.00, 0.95, 0.40)"),
		"accessibility crit color = bright yellow (in AccessibilityPalette)")
	assert_true(palette.contains("return Color.ORANGE"),
		"default crit color preserved as ORANGE (in AccessibilityPalette)")


func test_damage_number_uses_helper_in_create_label() -> void:
	var src := _read(DAMAGE_NUMBER)
	# Pin: _create_label uses the helpers, not bare LIME_GREEN/ORANGE.
	assert_true(src.contains("if is_heal:\n\t\t\tcolor = _heal_color()"),
		"_create_label must call _heal_color() for heal popups")
	assert_true(src.contains("elif is_critical:\n\t\t\tcolor = _crit_color()"),
		"_create_label must call _crit_color() for crit popups")


func test_damage_number_crit_wobble_uses_helper() -> void:
	# The crit wobble effect cycles to the crit color — must use the
	# helper too so accessibility mode is consistent through the
	# animation.
	var src := _read(DAMAGE_NUMBER)
	assert_true(src.contains("tween_property(_label, \"theme_override_colors/font_color\", _crit_color(), 0.15)"),
		"crit wobble effect must use _crit_color() helper (consistent with initial color)")


# ── No bare LIME_GREEN / ORANGE outside the helpers ──────────────────

func test_no_bare_lime_green_in_create_label() -> void:
	# Negative pin: the old hardcoded Color.LIME_GREEN in _create_label
	# is gone; only the helper returns it as the default.
	var src := _read(DAMAGE_NUMBER)
	# Find _create_label body.
	var fn_idx: int = src.find("func _create_label")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("color = Color.LIME_GREEN"),
		"_create_label must not hardcode LIME_GREEN (must call _heal_color)")
	assert_false(body.contains("color = Color.ORANGE"),
		"_create_label must not hardcode ORANGE (must call _crit_color)")


# ── Live behavior ────────────────────────────────────────────────────

func test_helpers_return_default_palette_when_off() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	var dn = load(DAMAGE_NUMBER).new()
	add_child_autofree(dn)
	assert_eq(dn._heal_color(), Color.LIME_GREEN,
		"OFF: heal color must be LIME_GREEN")
	assert_eq(dn._crit_color(), Color.ORANGE,
		"OFF: crit color must be ORANGE")


func test_helpers_return_accessibility_palette_when_on() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var dn = load(DAMAGE_NUMBER).new()
	add_child_autofree(dn)
	# Use floats-close compare via approx_eq on each channel
	# since assert_eq on Color can be picky.
	var heal := dn._heal_color() as Color
	assert_almost_eq(heal.r, 0.30, 0.001, "heal color R channel = 0.30 (cyan)")
	assert_almost_eq(heal.g, 0.70, 0.001, "heal color G channel = 0.70")
	assert_almost_eq(heal.b, 1.00, 0.001, "heal color B channel = 1.00")
	var crit := dn._crit_color() as Color
	assert_almost_eq(crit.r, 1.00, 0.001, "crit color R channel = 1.00 (yellow)")
	assert_almost_eq(crit.g, 0.95, 0.001, "crit color G channel = 0.95")
	assert_almost_eq(crit.b, 0.40, 0.001, "crit color B channel = 0.40")
	# Reset for other tests.
	GameState.color_blind_mode = false


# ── Cross-pin: tick 222 plumbing preserved ───────────────────────────

func test_tick_222_text_size_preserved() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("var text_size_scale: float = 1.0"),
		"tick 222 GameState.text_size_scale preserved")
