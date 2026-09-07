extends GutTest

## tick 229: extends AccessibilityPalette (tick 228) with HP bar
## tier helpers, then wires SaveScreen + StatusMenu to use them.
##
## Pre-fix HP bar threshold colors used:
##   high (≥60%) = green
##   mid  (30..60%) = yellow
##   low  (<30%) = red
##
## Under deuteranopia/protanopia (~5% of males), the green→red
## tier transition is the worst-possible signal: both colors sit
## on the affected spectrum and become hard to distinguish. The
## binary StatusMenu pattern (green or red at 30%) hits the same
## issue.
##
## Color-blind mode swaps:
##   high → cyan    (same as heal — consistent "safe/healing" cool)
##   mid  → yellow  (unchanged — already colorblind-safe)
##   low  → magenta (same as elem_weak — consistent "danger" warm)
##
## The cross-feature color sharing (cyan=heal=hp_high;
## magenta=elem_weak=hp_low) is intentional: both pairings carry
## the same semantic meaning, so a player learning the palette in
## one context understands it in the other.

const ACCESSIBILITY_PALETTE := "res://src/ui/AccessibilityPalette.gd"
const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"
const STATUS_MENU := "res://src/ui/StatusMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── AccessibilityPalette HP helpers ──────────────────────────────────

func test_hp_high_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func hp_high() -> Color:"),
		"hp_high helper must be static")
	assert_true(src.contains("return Color(0.35, 0.90, 0.35)"),
		"hp_high default = green Color(0.35, 0.90, 0.35)")


func test_hp_high_accessibility_matches_heal() -> void:
	# Pin: hp_high accessibility = cyan, SAME as heal accessibility.
	# This consistency is intentional (semantic carry-over).
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func hp_high")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(0.30, 0.70, 1.00)"),
		"hp_high accessibility = cyan Color(0.30, 0.70, 1.00) (matches heal)")


func test_hp_mid_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func hp_mid() -> Color:"),
		"hp_mid helper must be static")
	assert_true(src.contains("return Color(0.95, 0.85, 0.30)"),
		"hp_mid color = yellow Color(0.95, 0.85, 0.30) (single value, already colorblind-safe)")


func test_hp_mid_is_same_in_both_modes() -> void:
	# Pin: hp_mid does NOT have an is_on() branch — yellow is
	# already colorblind-safe so the value is single-cased.
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func hp_mid")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("if is_on()"),
		"hp_mid should NOT branch on accessibility (yellow is safe in both modes)")


func test_hp_low_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func hp_low() -> Color:"),
		"hp_low helper must be static")
	assert_true(src.contains("return Color(0.90, 0.30, 0.30)"),
		"hp_low default = red Color(0.90, 0.30, 0.30)")


func test_hp_low_accessibility_matches_elem_weak() -> void:
	# Pin: hp_low accessibility = magenta, SAME as elem_weak.
	# hp_low is the last static func in the file — guard against -1.
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func hp_low")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(1.00, 0.40, 0.80)"),
		"hp_low accessibility = magenta Color(1.00, 0.40, 0.80) (matches elem_weak)")


# ── Live runtime checks ──────────────────────────────────────────────

func test_hp_high_default_returns_green() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	var c := AccessibilityPalette.hp_high() as Color
	assert_almost_eq(c.r, 0.35, 0.001, "OFF: hp_high R = 0.35")
	assert_almost_eq(c.g, 0.90, 0.001, "OFF: hp_high G = 0.90")
	assert_almost_eq(c.b, 0.35, 0.001, "OFF: hp_high B = 0.35")


func test_hp_high_accessibility_returns_cyan() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var c := AccessibilityPalette.hp_high() as Color
	# Cross-feature: same as heal cyan.
	var heal := AccessibilityPalette.heal() as Color
	assert_eq(c, heal, "ON: hp_high MUST equal heal (cross-feature consistency)")
	GameState.color_blind_mode = false


func test_hp_low_accessibility_returns_magenta() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var c := AccessibilityPalette.hp_low() as Color
	# Cross-feature: same as elem_weak magenta.
	var weak := AccessibilityPalette.elem_weak() as Color
	assert_eq(c, weak, "ON: hp_low MUST equal elem_weak (cross-feature consistency)")
	GameState.color_blind_mode = false


func test_hp_mid_stable_across_modes() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	var c_off := AccessibilityPalette.hp_mid() as Color
	GameState.color_blind_mode = true
	var c_on := AccessibilityPalette.hp_mid() as Color
	assert_eq(c_off, c_on, "hp_mid must be the same in OFF and ON modes")
	GameState.color_blind_mode = false


# ── SaveScreen consumer ──────────────────────────────────────────────

func test_save_screen_hp_fill_color_uses_palette() -> void:
	var src := _read(SAVE_SCREEN)
	var fn_idx: int = src.find("static func _hp_fill_color")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return AccessibilityPalette.hp_high()"),
		"SaveScreen._hp_fill_color ≥0.6 branch delegates to AccessibilityPalette.hp_high()")
	assert_true(body.contains("return AccessibilityPalette.hp_mid()"),
		"SaveScreen._hp_fill_color 0.3..0.6 branch delegates to hp_mid()")
	assert_true(body.contains("return AccessibilityPalette.hp_low()"),
		"SaveScreen._hp_fill_color <0.3 branch delegates to hp_low()")


func test_save_screen_no_more_bare_hp_const_returns() -> void:
	# Negative pin: the bare HP_HIGH_COLOR / HP_MID_COLOR / HP_LOW_COLOR
	# returns inside _hp_fill_color must be gone.
	var src := _read(SAVE_SCREEN)
	var fn_idx: int = src.find("static func _hp_fill_color")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("return HP_HIGH_COLOR"),
		"SaveScreen._hp_fill_color must not return the bare HP_HIGH_COLOR const")
	assert_false(body.contains("return HP_MID_COLOR"),
		"SaveScreen._hp_fill_color must not return the bare HP_MID_COLOR const")
	assert_false(body.contains("return HP_LOW_COLOR"),
		"SaveScreen._hp_fill_color must not return the bare HP_LOW_COLOR const")


# ── StatusMenu consumer ──────────────────────────────────────────────

func test_status_menu_hp_bar_uses_palette() -> void:
	var src := _read(STATUS_MENU)
	assert_true(src.contains("hp_bar.color = AccessibilityPalette.hp_high() if hp_pct > 0.3 else AccessibilityPalette.hp_low()"),
		"StatusMenu HP bar must use AccessibilityPalette.hp_high / hp_low (binary tier)")
	# Old bare ternary gone.
	assert_false(src.contains("hp_bar.color = HP_COLOR if hp_pct > 0.3 else PENALTY_COLOR"),
		"StatusMenu's old HP_COLOR/PENALTY_COLOR ternary must be gone")


# ── Cross-pin: tick 228 helpers + tick 198 _hp_fill_color preserved ──

func test_tick_228_palette_helpers_preserved() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func heal() -> Color:"),
		"tick 228 heal helper preserved")
	assert_true(src.contains("static func crit() -> Color:"),
		"tick 228 crit helper preserved")
	assert_true(src.contains("static func elem_weak() -> Color:"),
		"tick 228 elem_weak helper preserved")


func test_tick_198_hp_fill_color_function_signature_preserved() -> void:
	var src := _read(SAVE_SCREEN)
	assert_true(src.contains("static func _hp_fill_color(hp_pct: float) -> Color:"),
		"tick 198 _hp_fill_color signature preserved (only the body changed)")
