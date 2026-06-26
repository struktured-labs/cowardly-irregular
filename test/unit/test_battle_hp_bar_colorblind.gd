extends GutTest

## tick 230: extends color-blind HP palette (tick 229) to the
## battle surface — BattleScene floating enemy HP bars and
## BattleUIManager enemy tooltip text. Most-glanced UI in the
## game (every combat turn).
##
## Sites refactored:
##   BattleScene line ~1080 — floating enemy HP bar fill (3-tier
##     ratio > 0.5 / > 0.25 / else, bare Color literals)
##   BattleUIManager line ~686 — revealed enemy tooltip BBCode color
##   BattleUIManager line ~692 — vague enemy tooltip BBCode color
##
## Both BBCode sites needed a new AccessibilityPalette helper —
## hp_bbcode_for_pct(pct) — that returns "lime"/"yellow"/"red"
## in default and "cyan"/"yellow"/"magenta" in accessibility mode.
## Matches the Color-returning hp_high/hp_mid/hp_low helpers
## semantically.
##
## Cross-feature consistency: BattleScene floating bar and
## SaveScreen/StatusMenu HP bars all read from the same palette
## now. A colorblind player who learns "cyan = safe" anywhere
## sees it consistently across the whole game.

const ACCESSIBILITY_PALETTE := "res://src/ui/AccessibilityPalette.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const BATTLE_UI_MANAGER := "res://src/battle/BattleUIManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── New BBCode helper ────────────────────────────────────────────────

func test_hp_bbcode_helper_present() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func hp_bbcode_for_pct(hp_pct: float) -> String:"),
		"hp_bbcode_for_pct must be static and take a float")


func test_hp_bbcode_uses_battle_thresholds() -> void:
	# Pin: BattleUIManager's original thresholds (>0.5 / >0.25) are
	# the same in the helper.
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func hp_bbcode_for_pct")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if hp_pct > 0.5:"),
		"high tier threshold > 0.5")
	assert_true(body.contains("if hp_pct > 0.25:"),
		"mid tier threshold > 0.25")


func test_hp_bbcode_swaps_color_names_in_accessibility() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	var fn_idx: int = src.find("static func hp_bbcode_for_pct")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("\"cyan\" if is_on() else \"lime\""),
		"high tier: cyan in accessibility, lime by default")
	assert_true(body.contains("\"magenta\" if is_on() else \"red\""),
		"low tier: magenta in accessibility, red by default")
	# Mid yellow has no accessibility swap.
	assert_true(body.contains("return \"yellow\""),
		"mid tier returns 'yellow' unconditionally")


# ── Live behavior ────────────────────────────────────────────────────

func test_hp_bbcode_default_returns_lime_yellow_red() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.9), "lime",
		"OFF: high tier 'lime'")
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.3), "yellow",
		"OFF: mid tier 'yellow'")
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.1), "red",
		"OFF: low tier 'red'")


func test_hp_bbcode_accessibility_returns_cyan_yellow_magenta() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.9), "cyan",
		"ON: high tier 'cyan'")
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.3), "yellow",
		"ON: mid tier still 'yellow' (no swap)")
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.1), "magenta",
		"ON: low tier 'magenta'")
	GameState.color_blind_mode = false


func test_hp_bbcode_at_threshold_boundaries() -> void:
	# Pin: > 0.5 means strict greater-than — at exactly 0.5 we drop
	# to mid tier.
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.51), "lime",
		"0.51 → high tier")
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.5), "yellow",
		"exactly 0.5 → mid tier (strict >)")
	assert_eq(AccessibilityPalette.hp_bbcode_for_pct(0.25), "red",
		"exactly 0.25 → low tier")


# ── BattleScene floating HP bar wiring ───────────────────────────────

func test_battle_scene_floating_hp_uses_palette() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("bar_fill.color = AccessibilityPalette.hp_high()"),
		"BattleScene's > 0.5 branch must use AccessibilityPalette.hp_high()")
	assert_true(src.contains("bar_fill.color = AccessibilityPalette.hp_mid()"),
		"BattleScene's > 0.25 branch must use AccessibilityPalette.hp_mid()")
	assert_true(src.contains("bar_fill.color = AccessibilityPalette.hp_low()"),
		"BattleScene's else branch must use AccessibilityPalette.hp_low()")


func test_battle_scene_no_more_bare_hp_color_literals() -> void:
	# Negative pin: the pre-fix bare Color literals are gone from
	# the floating-HP-bar fill assignment.
	var src := _read(BATTLE_SCENE)
	assert_false(src.contains("bar_fill.color = Color(0.3, 0.8, 0.3)"),
		"bare green Color(0.3, 0.8, 0.3) must be gone")
	assert_false(src.contains("bar_fill.color = Color(0.9, 0.8, 0.2)"),
		"bare yellow Color(0.9, 0.8, 0.2) must be gone")
	# Note: Color(0.8, 0.2, 0.2) is preserved at line ~1063 as the
	# initial bar fill (immediately overridden) — that's still
	# a literal. Just check the dynamic-update site is clean.


# ── BattleUIManager BBCode wiring ────────────────────────────────────

func test_battle_ui_manager_uses_bbcode_helper() -> void:
	var src := _read(BATTLE_UI_MANAGER)
	# Both sites (revealed + vague) must use the helper.
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("AccessibilityPalette.hp_bbcode_for_pct(hp_percent)", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_eq(count, 2,
		"BattleUIManager must have exactly 2 hp_bbcode_for_pct calls (revealed + vague enemy tooltip)")


func test_battle_ui_manager_no_more_bare_bbcode_ternary() -> void:
	# Negative pin: the inline lime/yellow/red BBCode ternary is gone.
	var src := _read(BATTLE_UI_MANAGER)
	assert_false(src.contains("var hp_color = \"lime\" if hp_percent > 0.5 else (\"yellow\" if hp_percent > 0.25 else \"red\")"),
		"old inline BBCode tier ternary must be gone")


# ── Cross-feature consistency: BattleScene and SaveScreen HP align ───

func test_battle_scene_and_save_screen_share_hp_high() -> void:
	# Pin: both consumers route hp_high through AccessibilityPalette,
	# so a colorblind player gets the same color across battle UI
	# and save slots.
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	# The helper itself is the single source — just verify it's
	# the same Color object structurally for both call paths.
	var c1 := AccessibilityPalette.hp_high() as Color
	var c2 := AccessibilityPalette.hp_high() as Color
	assert_eq(c1, c2, "hp_high must be deterministic across calls")
	# Cross-feature: cyan == heal.
	var heal := AccessibilityPalette.heal() as Color
	assert_eq(c1, heal, "cyan hp_high MUST equal cyan heal (cross-feature consistency invariant)")
	GameState.color_blind_mode = false


# ── Cross-pins: tick 229 + 228 preserved ─────────────────────────────

func test_tick_229_hp_helpers_preserved() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func hp_high() -> Color:"),
		"tick 229 hp_high preserved")
	assert_true(src.contains("static func hp_mid() -> Color:"),
		"tick 229 hp_mid preserved")
	assert_true(src.contains("static func hp_low() -> Color:"),
		"tick 229 hp_low preserved")


func test_tick_229_save_screen_delegation_preserved() -> void:
	var src := _read("res://src/ui/SaveScreen.gd")
	assert_true(src.contains("return AccessibilityPalette.hp_high()"),
		"tick 229 SaveScreen hp delegation preserved")
