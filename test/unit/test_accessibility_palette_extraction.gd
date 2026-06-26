extends GutTest

## tick 228: extracts the color-blind palette logic from
## DamageNumber (tick 226) and BattleScene (tick 227) to a shared
## AccessibilityPalette static util. Same pattern as TextScale
## (tick 223) and StatNames (tick 211).
##
## Before: each consumer had its own GameState.color_blind_mode
## lookup + color branch pair, with the scene-tree-root pattern
## duplicated 3 times.
##
## After: AccessibilityPalette.heal / crit / elem_weak. Consumers
## delegate. Future colorblind-aware sites add ONE function to
## AccessibilityPalette and call it.

const ACCESSIBILITY_PALETTE := "res://src/ui/AccessibilityPalette.gd"
const DAMAGE_NUMBER := "res://src/ui/DamageNumber.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── AccessibilityPalette util ─────────────────────────────────────────

func test_class_name_registered() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("class_name AccessibilityPalette"),
		"AccessibilityPalette class_name must register globally")


func test_is_on_helper_present_and_static() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func is_on() -> bool:"),
		"is_on must be static")


func test_is_on_uses_scene_tree_root_pattern() -> void:
	# Pin: must use scene-tree-root autoload lookup. The negative
	# constraint (no Engine.has_singleton) is already enforced
	# globally by test_no_engine_has_singleton.gd's source lint —
	# no need to repeat the literal here (which would itself trip
	# the lint).
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("tree.root.get_node_or_null(\"GameState\")"),
		"is_on must use scene-tree-root autoload lookup")


func test_heal_helper_returns_lime_green_by_default() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func heal() -> Color:"),
		"heal helper must be static")
	assert_true(src.contains("return Color.LIME_GREEN"),
		"heal must default to LIME_GREEN (preserve classic palette)")


func test_heal_helper_returns_cyan_in_accessibility_mode() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("return Color(0.30, 0.70, 1.00)"),
		"heal accessibility branch returns cyan/sky-blue")


func test_crit_helper_returns_orange_by_default() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func crit() -> Color:"),
		"crit helper must be static")
	assert_true(src.contains("return Color.ORANGE"),
		"crit must default to ORANGE")


func test_crit_helper_returns_yellow_in_accessibility_mode() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("return Color(1.00, 0.95, 0.40)"),
		"crit accessibility branch returns bright yellow")


func test_elem_weak_helper_returns_red_by_default() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("static func elem_weak() -> Color:"),
		"elem_weak helper must be static")
	assert_true(src.contains("return Color(1.0, 0.3, 0.3)"),
		"elem_weak must default to red Color(1.0, 0.3, 0.3)")


func test_elem_weak_helper_returns_magenta_in_accessibility_mode() -> void:
	var src := _read(ACCESSIBILITY_PALETTE)
	assert_true(src.contains("return Color(1.00, 0.40, 0.80)"),
		"elem_weak accessibility branch returns magenta")


# ── Live behavior ────────────────────────────────────────────────────

func test_heal_at_default() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.heal(), Color.LIME_GREEN,
		"OFF: heal = LIME_GREEN")


func test_heal_at_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var c := AccessibilityPalette.heal() as Color
	assert_almost_eq(c.r, 0.30, 0.001, "ON: heal R = 0.30")
	assert_almost_eq(c.g, 0.70, 0.001, "ON: heal G = 0.70")
	assert_almost_eq(c.b, 1.00, 0.001, "ON: heal B = 1.00")
	GameState.color_blind_mode = false


func test_crit_at_default() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	assert_eq(AccessibilityPalette.crit(), Color.ORANGE,
		"OFF: crit = ORANGE")


func test_crit_at_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var c := AccessibilityPalette.crit() as Color
	assert_almost_eq(c.r, 1.00, 0.001, "ON: crit R = 1.00")
	assert_almost_eq(c.g, 0.95, 0.001, "ON: crit G = 0.95")
	assert_almost_eq(c.b, 0.40, 0.001, "ON: crit B = 0.40")
	GameState.color_blind_mode = false


func test_elem_weak_at_default() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	var c := AccessibilityPalette.elem_weak() as Color
	assert_almost_eq(c.r, 1.0, 0.001, "OFF: WEAK R = 1.0")
	assert_almost_eq(c.g, 0.3, 0.001, "OFF: WEAK G = 0.3")
	assert_almost_eq(c.b, 0.3, 0.001, "OFF: WEAK B = 0.3")


func test_elem_weak_at_accessibility() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var c := AccessibilityPalette.elem_weak() as Color
	assert_almost_eq(c.r, 1.0, 0.001, "ON: WEAK R = 1.0")
	assert_almost_eq(c.g, 0.40, 0.001, "ON: WEAK G = 0.40")
	assert_almost_eq(c.b, 0.80, 0.001, "ON: WEAK B = 0.80")
	GameState.color_blind_mode = false


# ── Consumer delegations ─────────────────────────────────────────────

func test_damage_number_heal_delegates() -> void:
	var src := _read(DAMAGE_NUMBER)
	var fn_idx: int = src.find("func _heal_color() -> Color:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return AccessibilityPalette.heal()"),
		"DamageNumber._heal_color must delegate to AccessibilityPalette.heal()")


func test_damage_number_crit_delegates() -> void:
	var src := _read(DAMAGE_NUMBER)
	var fn_idx: int = src.find("func _crit_color() -> Color:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return AccessibilityPalette.crit()"),
		"DamageNumber._crit_color must delegate to AccessibilityPalette.crit()")


func test_battle_scene_elem_weak_delegates() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _elem_weak_color() -> Color:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return AccessibilityPalette.elem_weak()"),
		"BattleScene._elem_weak_color must delegate to AccessibilityPalette.elem_weak()")


# ── No duplicated GameState lookup in consumers ──────────────────────

func test_damage_number_no_local_gamestate_lookup() -> void:
	# Pin: the local _is_color_blind_mode_on helper from tick 226 is
	# gone — its logic lives in AccessibilityPalette.is_on now.
	var src := _read(DAMAGE_NUMBER)
	assert_false(src.contains("func _is_color_blind_mode_on()"),
		"DamageNumber._is_color_blind_mode_on must be removed (logic moved to AccessibilityPalette)")


func test_battle_scene_elem_weak_no_local_gamestate_lookup() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _elem_weak_color() -> Color:")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# The local scene-tree-root lookup is gone from this helper's body.
	assert_false(body.contains("tree.root.get_node_or_null"),
		"BattleScene._elem_weak_color must not duplicate the scene-tree-root lookup (delegated to AccessibilityPalette)")


# ── Cross-pin: tick 226/227 invariants preserved at consumer call sites ─

func test_damage_number_create_label_still_uses_helpers() -> void:
	# Tick 226 wiring at the call site stays unchanged (just the
	# helper implementation changed under it).
	var src := _read(DAMAGE_NUMBER)
	assert_true(src.contains("color = _heal_color()"),
		"_create_label still calls _heal_color()")
	assert_true(src.contains("color = _crit_color()"),
		"_create_label still calls _crit_color()")


func test_battle_scene_spawn_still_uses_helper() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("color = _elem_weak_color()"),
		"_spawn_elemental_indicator still calls _elem_weak_color()")
