extends RefCounted
class_name AccessibilityPalette

## Shared color-blind aware palette helpers — tick 228.
##
## Extracted from DamageNumber (tick 226) and BattleScene (tick 227)
## which both duplicated the same `GameState.color_blind_mode`
## lookup + branch pattern across their local color helpers.
##
## All helpers return the default classic palette unless
## GameState.color_blind_mode is true, in which case they return
## a deuteranopia/protanopia-safe alternative.
##
## Color choices target the most common color-blindness types
## (red-green, ~5% of males globally). Cross-feature distinctness
## checked between heal/crit/weak so the player with multiple
## indicators on screen still sees distinguishable colors.
##
## Use anywhere a color literal would have been:
##   color = AccessibilityPalette.heal()
##   color = AccessibilityPalette.crit()
##   color = AccessibilityPalette.elem_weak()
##
## Reads GameState live each call so a SettingsMenu toggle applies
## immediately (no signal/redraw machinery needed at call sites).

# Tick 228: scene-tree-root autoload lookup (Engine.has_singleton matches NATIVE singletons only — see test_no_engine_has_singleton.gd lint).
static func is_on() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var gs = tree.root.get_node_or_null("GameState")
		if gs and "color_blind_mode" in gs:
			return bool(gs.color_blind_mode)
	return false


# Tick 226: heal popup color — LIME_GREEN default, cyan/sky-blue in accessibility mode.
static func heal() -> Color:
	if is_on():
		return Color(0.30, 0.70, 1.00)  # Cyan/sky-blue
	return Color.LIME_GREEN


# Tick 226: crit popup color — ORANGE default, bright yellow in accessibility mode.
static func crit() -> Color:
	if is_on():
		return Color(1.00, 0.95, 0.40)  # Bright yellow
	return Color.ORANGE


# Tick 227: WEAK! elemental indicator color — red default, magenta in accessibility mode (distinguishable from cyan heal + yellow crit + blue RESIST + gray IMMUNE).
static func elem_weak() -> Color:
	if is_on():
		return Color(1.00, 0.40, 0.80)  # Magenta
	return Color(1.0, 0.3, 0.3)  # Red


# Tick 229: HP bar high-tier (≥60% HP) — green default, cyan in accessibility mode. Cyan == heal color: consistent "safe/healing" cool-color semantic.
static func hp_high() -> Color:
	if is_on():
		return Color(0.30, 0.70, 1.00)  # Cyan (matches heal)
	return Color(0.35, 0.90, 0.35)  # Green


# Tick 229: HP bar mid-tier (30..60% HP) — yellow. Already colorblind-safe (yellow reads clearly under deuteranopia/protanopia); same value either way for cross-mode consistency.
static func hp_mid() -> Color:
	return Color(0.95, 0.85, 0.30)  # Yellow


# Tick 229: HP bar low-tier (<30% HP) — red default, magenta in accessibility mode. Magenta == elem_weak color: consistent "danger" warm-color semantic.
static func hp_low() -> Color:
	if is_on():
		return Color(1.00, 0.40, 0.80)  # Magenta (matches elem_weak)
	return Color(0.90, 0.30, 0.30)  # Red


# Tick 230: BBCode-friendly HP tier name for [color=X]…[/color] text in RichTextLabels (BattleUIManager enemy tooltips). Tiers match BattleUIManager's original thresholds (>0.5, >0.25). Color-blind mode swaps lime→cyan and red→magenta to match the visual HP bar palette.
static func hp_bbcode_for_pct(hp_pct: float) -> String:
	if hp_pct > 0.5:
		return "cyan" if is_on() else "lime"
	if hp_pct > 0.25:
		return "yellow"
	return "magenta" if is_on() else "red"


# Tick 236: bonus/positive stat color — green default, cyan in accessibility mode. Used by StatusMenu, JobMenu, EquipmentMenu for "+N stat" displays. Same cyan as heal + hp_high — consistent "positive" semantic.
static func bonus() -> Color:
	if is_on():
		return Color(0.30, 0.70, 1.00)  # Cyan (matches heal, hp_high)
	return Color(0.4, 0.9, 0.4)  # Green


# Tick 236: penalty/negative stat color — red default, magenta in accessibility mode. Used for "-N stat" displays. Same magenta as elem_weak + hp_low — consistent "negative" semantic.
static func penalty() -> Color:
	if is_on():
		return Color(1.00, 0.40, 0.80)  # Magenta (matches elem_weak, hp_low)
	return Color(0.9, 0.4, 0.4)  # Red (PartyStatusScreen / EquipmentMenu / StatusMenu PENALTY shade)


# Tick 236: injury color — darker red default, darker magenta in accessibility mode. Used by StatusMenu for permanent injury labels. Darker variant keeps it visually distinct from regular penalty (more severe state).
static func injury() -> Color:
	if is_on():
		return Color(0.75, 0.25, 0.65)  # Darker magenta
	return Color(0.8, 0.2, 0.2)  # Darker red
