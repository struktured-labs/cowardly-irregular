extends GutTest

## tick 236: extends AccessibilityPalette with bonus / penalty /
## injury helpers, then wires StatusMenu + EquipmentMenu to use
## them. 6 sites across 2 menus now scale color-blind aware:
##
##   StatusMenu:
##     - stat diff label (BONUS / PENALTY ternary)
##     - learned passive label (BONUS)
##     - injury title (INJURY)
##     - injury label (INJURY)
##
##   EquipmentMenu:
##     - stat-mod label (POSITIVE / NEGATIVE ternary)
##     - stats panel positive line (POSITIVE)
##     - stats panel negative line (NEGATIVE)
##
## Cross-feature color sharing (intentional):
##   bonus()  == heal()       == hp_high()  → cyan in accessibility
##   penalty() == elem_weak() == hp_low()   → magenta in accessibility
##   injury()                                → darker magenta (severe state)
##
## JobMenu also defines POSITIVE_COLOR / NEGATIVE_COLOR but
## doesn't actively use them (dead consts) — left untouched for
## backwards compatibility.

const ACCESSIBILITY_PALETTE := "res://src/ui/AccessibilityPalette.gd"
const STATUS_MENU := "res://src/ui/StatusMenu.gd"
const EQUIPMENT_MENU := "res://src/ui/EquipmentMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── New AccessibilityPalette helpers ──────────────────────────────────

func test_bonus_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func bonus() -> Color:"),
		"bonus helper must be static")
	assert_true(src.contains("return Color(0.4, 0.9, 0.4)"),
		"bonus default = green Color(0.4, 0.9, 0.4)")


func test_bonus_accessibility_matches_heal() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func bonus")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(0.30, 0.70, 1.00)"),
		"bonus accessibility = cyan (matches heal + hp_high)")


func test_penalty_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func penalty() -> Color:"),
		"penalty helper must be static")
	assert_true(src.contains("return Color(0.9, 0.4, 0.4)"),
		"penalty default = red Color(0.9, 0.4, 0.4)")


func test_penalty_accessibility_matches_elem_weak() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func penalty")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(1.00, 0.40, 0.80)"),
		"penalty accessibility = magenta (matches elem_weak + hp_low)")


func test_injury_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func injury() -> Color:"),
		"injury helper must be static")
	assert_true(src.contains("return Color(0.8, 0.2, 0.2)"),
		"injury default = darker red Color(0.8, 0.2, 0.2)")


func test_injury_accessibility_is_darker_magenta() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func injury")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(0.75, 0.25, 0.65)"),
		"injury accessibility = darker magenta Color(0.75, 0.25, 0.65)")


# ── Live runtime: cross-feature semantic equality ────────────────────

func test_bonus_runtime_equals_heal_in_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	assert_eq(AccessibilityPalette.bonus(), AccessibilityPalette.heal(),
		"ON: bonus MUST equal heal (consistent 'positive' semantic)")
	assert_eq(AccessibilityPalette.bonus(), AccessibilityPalette.hp_high(),
		"ON: bonus MUST equal hp_high (consistent 'positive' semantic)")
	GameState.color_blind_mode = false


func test_penalty_runtime_equals_elem_weak_in_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	assert_eq(AccessibilityPalette.penalty(), AccessibilityPalette.elem_weak(),
		"ON: penalty MUST equal elem_weak (consistent 'negative' semantic)")
	assert_eq(AccessibilityPalette.penalty(), AccessibilityPalette.hp_low(),
		"ON: penalty MUST equal hp_low (consistent 'negative' semantic)")
	GameState.color_blind_mode = false


func test_injury_distinct_from_penalty() -> void:
	# Injury is DARKER than penalty — distinguishable as "more severe".
	if not GameState:
		pending("GameState autoload missing")
		return
	# Off mode: both red but injury (0.8, 0.2, 0.2) ≠ penalty (0.9, 0.4, 0.4).
	GameState.color_blind_mode = false
	assert_ne(AccessibilityPalette.injury(), AccessibilityPalette.penalty(),
		"OFF: injury must be distinguishable from penalty (darker red shade)")
	# On mode: both magenta but injury is darker.
	GameState.color_blind_mode = true
	assert_ne(AccessibilityPalette.injury(), AccessibilityPalette.penalty(),
		"ON: injury must be distinguishable from penalty (darker magenta shade)")
	GameState.color_blind_mode = false


# ── StatusMenu consumer (4 sites) ───────────────────────────────────

func test_status_menu_breakdown_uses_palette() -> void:
	var src := _read(STATUS_MENU)
	assert_true(src.contains("AccessibilityPalette.bonus() if diff > 0 else AccessibilityPalette.penalty()"),
		"StatusMenu stat-diff ternary must use AccessibilityPalette")


func test_status_menu_passive_uses_palette() -> void:
	var src := _read(STATUS_MENU)
	# Pin: the passive label uses bonus() (no else branch).
	assert_true(src.contains("passive_label.add_theme_color_override(\"font_color\", AccessibilityPalette.bonus())"),
		"StatusMenu passive label must use AccessibilityPalette.bonus()")


func test_status_menu_injury_sites_use_palette() -> void:
	var src := _read(STATUS_MENU)
	# Two injury sites: title + per-injury label. Both use injury().
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("AccessibilityPalette.injury()", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_eq(count, 2,
		"StatusMenu must have exactly 2 AccessibilityPalette.injury() calls (title + per-injury label)")


# ── EquipmentMenu consumer (3 sites) ────────────────────────────────

func test_equipment_menu_mod_label_uses_palette() -> void:
	var src := _read(EQUIPMENT_MENU)
	assert_true(src.contains("AccessibilityPalette.bonus() if mod_value > 0 else AccessibilityPalette.penalty()"),
		"EquipmentMenu mod_label ternary must use AccessibilityPalette")


func test_equipment_menu_stats_panel_uses_palette() -> void:
	var src := _read(EQUIPMENT_MENU)
	# Positive and negative stats panel lines must both delegate.
	assert_true(src.contains("stats_label.add_theme_color_override(\"font_color\", AccessibilityPalette.bonus())"),
		"EquipmentMenu stats positive line must use AccessibilityPalette.bonus()")
	assert_true(src.contains("stats_label.add_theme_color_override(\"font_color\", AccessibilityPalette.penalty())"),
		"EquipmentMenu stats negative line must use AccessibilityPalette.penalty()")


func test_equipment_menu_no_bare_positive_negative_color() -> void:
	# Negative pin: the bare POSITIVE_COLOR / NEGATIVE_COLOR references
	# in font_color overrides are gone. (The const declarations stay
	# for backwards compatibility, but no font_color override should
	# use them directly.)
	var src := _read(EQUIPMENT_MENU)
	assert_false(src.contains("\"font_color\", POSITIVE_COLOR"),
		"EquipmentMenu must not bare-use POSITIVE_COLOR in font_color overrides")
	assert_false(src.contains("\"font_color\", NEGATIVE_COLOR"),
		"EquipmentMenu must not bare-use NEGATIVE_COLOR in font_color overrides")


# ── Cross-pin: prior accessibility palette work preserved ────────────

func test_tick_229_hp_helpers_preserved() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func hp_high() -> Color:"),
		"tick 229 hp_high preserved")
	assert_true(src.contains("static func hp_low() -> Color:"),
		"tick 229 hp_low preserved")


func test_tick_226_helpers_preserved() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func heal() -> Color:"),
		"tick 226 heal preserved")
	assert_true(src.contains("static func crit() -> Color:"),
		"tick 226 crit preserved")
