extends GutTest

## tick 237: BBCode-string accessibility helpers + initial battle
## log refactor.
##
## BattleManager has 133 battle_log_message emits. ~30 of them
## use color-blind-problematic [color=red] / [color=lime] /
## [color=green] inline literals. Refactoring all 30 at once is
## risky (each one needs `%s` placeholder + tuple argument
## changes). This tick:
##
##   1. Adds the helpers to AccessibilityPalette:
##        bonus_bbcode()   — "lime" / "cyan"
##        penalty_bbcode() — "red"  / "magenta"
##   2. Refactors 5 representative emits as proof-of-pattern:
##        - "cannot defer while exposed" (penalty)
##        - "Limit Break requires AP" (penalty)
##        - "Combo Magic AP" (penalty)
##        - "Combo Magic elements" (penalty)
##        - "escaped successfully" (bonus — escape = positive)
##
## Future ticks can mechanically refactor the remaining 25 sites
## following this established pattern.

const ACCESSIBILITY_PALETTE := "res://src/ui/AccessibilityPalette.gd"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── BBCode helpers ───────────────────────────────────────────────────

func test_bonus_bbcode_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func bonus_bbcode() -> String:"),
		"bonus_bbcode helper must be static")


func test_bonus_bbcode_defaults_to_lime() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("return \"cyan\" if is_on() else \"lime\""),
		"bonus_bbcode: default 'lime', accessibility 'cyan'")


func test_penalty_bbcode_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func penalty_bbcode() -> String:"),
		"penalty_bbcode helper must be static")


func test_penalty_bbcode_defaults_to_red() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("return \"magenta\" if is_on() else \"red\""),
		"penalty_bbcode: default 'red', accessibility 'magenta'")


# ── Live runtime ─────────────────────────────────────────────────────

func test_bonus_bbcode_default() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.bonus_bbcode(), "lime",
		"OFF: bonus_bbcode = 'lime'")


func test_bonus_bbcode_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	assert_eq(AccessibilityPalette.bonus_bbcode(), "cyan",
		"ON: bonus_bbcode = 'cyan'")
	GameState.color_blind_mode = false


func test_penalty_bbcode_default() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.penalty_bbcode(), "red",
		"OFF: penalty_bbcode = 'red'")


func test_penalty_bbcode_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	assert_eq(AccessibilityPalette.penalty_bbcode(), "magenta",
		"ON: penalty_bbcode = 'magenta'")
	GameState.color_blind_mode = false


# ── Cross-feature consistency with tick 230 hp_bbcode_for_pct ────────

func test_bbcode_helpers_align_with_hp_tier_palette() -> void:
	# Pin: the bbcode helpers use the SAME color names as
	# hp_bbcode_for_pct's tier outputs (lime/red default,
	# cyan/magenta accessibility). A player who learns
	# "magenta = bad" anywhere sees it consistently.
	if not GameState:
		pending("GameState autoload missing")
		return
	# Default mode.
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.bonus_bbcode(),
		AccessibilityPalette.hp_bbcode_for_pct(0.9),
		"OFF: bonus_bbcode MUST match hp_bbcode_for_pct(high) = 'lime'")
	assert_eq(AccessibilityPalette.penalty_bbcode(),
		AccessibilityPalette.hp_bbcode_for_pct(0.1),
		"OFF: penalty_bbcode MUST match hp_bbcode_for_pct(low) = 'red'")
	# Accessibility mode.
	GameState.color_blind_mode = true
	assert_eq(AccessibilityPalette.bonus_bbcode(),
		AccessibilityPalette.hp_bbcode_for_pct(0.9),
		"ON: bonus_bbcode MUST match hp_bbcode_for_pct(high) = 'cyan'")
	assert_eq(AccessibilityPalette.penalty_bbcode(),
		AccessibilityPalette.hp_bbcode_for_pct(0.1),
		"ON: penalty_bbcode MUST match hp_bbcode_for_pct(low) = 'magenta'")
	GameState.color_blind_mode = false


# ── BattleManager refactored sites ───────────────────────────────────

func test_cannot_defer_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s cannot defer while exposed![/color]\" % [AccessibilityPalette.penalty_bbcode(), current_combatant.combatant_name])"),
		"'cannot defer while exposed' emit must use AccessibilityPalette.penalty_bbcode()")


func test_limit_break_ap_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]Limit Break requires ALL participants at full AP (4)![/color]\" % AccessibilityPalette.penalty_bbcode()"),
		"Limit Break AP requirement emit must use penalty_bbcode()")


func test_combo_magic_ap_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]Combo Magic requires ALL participants to have >= 2 AP![/color]\" % AccessibilityPalette.penalty_bbcode()"),
		"Combo Magic AP emit must use penalty_bbcode()")


func test_combo_magic_elements_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]Combo Magic requires at least 2 different magic elements![/color]\" % AccessibilityPalette.penalty_bbcode()"),
		"Combo Magic elements emit must use penalty_bbcode()")


func test_escape_success_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s escaped successfully![/color]\" % [AccessibilityPalette.bonus_bbcode(), caster.combatant_name])"),
		"escape success emit must use AccessibilityPalette.bonus_bbcode()")


# ── Refactor coverage count ──────────────────────────────────────────

func test_refactored_emit_count() -> void:
	# Pin: at least 5 emits now reference the new helpers.
	var src := _read(BATTLE_MANAGER)
	var penalty_count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("AccessibilityPalette.penalty_bbcode()", idx)
		if next < 0:
			break
		penalty_count += 1
		idx = next + 1
	var bonus_count: int = 0
	idx = 0
	while true:
		var next: int = src.find("AccessibilityPalette.bonus_bbcode()", idx)
		if next < 0:
			break
		bonus_count += 1
		idx = next + 1
	assert_gte(penalty_count, 4,
		"BattleManager must have ≥4 penalty_bbcode usages (4 representative penalty emits refactored)")
	assert_gte(bonus_count, 1,
		"BattleManager must have ≥1 bonus_bbcode usage (escape success refactored)")


# ── Cross-pin: tick 236 helpers preserved ────────────────────────────

func test_tick_236_color_helpers_preserved() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func bonus() -> Color:"),
		"tick 236 bonus() Color helper preserved")
	assert_true(src.contains("static func penalty() -> Color:"),
		"tick 236 penalty() Color helper preserved")
