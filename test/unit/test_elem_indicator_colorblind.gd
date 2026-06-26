extends GutTest

## tick 227: extends tick 226's color-blind palette to the
## BattleScene elemental indicator labels (WEAK!/RESIST/IMMUNE!).
##
## Pre-fix palette (still default behavior):
##   IMMUNE! = gray  Color(0.7, 0.7, 0.7) — colorblind-safe
##   WEAK!   = red   Color(1.0, 0.3, 0.3) — PROBLEMATIC
##   RESIST  = blue  Color(0.3, 0.5, 1.0) — colorblind-safe
##
## Under deuteranopia/protanopia (red-green color blindness,
## ~5% of males), the WEAK red blends with the visual environment
## (especially against the Mode 7 floor tints — see tick 218).
## Player can't tell at a glance whether the indicator says
## WEAK (red) or RESIST (blue).
##
## When GameState.color_blind_mode is on, WEAK swaps to magenta
## Color(1.00, 0.40, 0.80). Magenta is:
##   - distinguishable from blue RESIST (different hue family)
##   - distinguishable from yellow crit popups (tick 226)
##   - distinguishable from cyan heal popups (tick 226)
##   - distinguishable from gray IMMUNE and white damage
##
## Combined with ticks 218 (outline) + 209 (stagger), the
## elemental indicator is now legible across the contrast,
## overlap, and color-blindness dimensions.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Helper is defined ────────────────────────────────────────────────

func test_elem_weak_color_helper_present() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("func _elem_weak_color() -> Color:"),
		"_elem_weak_color helper must exist on BattleScene")


func test_elem_weak_color_defaults_to_red() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _elem_weak_color")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(1.0, 0.3, 0.3)"),
		"default WEAK color preserved as red Color(1.0, 0.3, 0.3)")


func test_elem_weak_color_uses_magenta_in_accessibility_mode() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _elem_weak_color")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return Color(1.00, 0.40, 0.80)"),
		"accessibility WEAK color = magenta Color(1.00, 0.40, 0.80)")


func test_elem_weak_helper_reads_gamestate_live() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _elem_weak_color")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Scene-tree-root lookup pattern (Engine.has_singleton lint enforces).
	assert_true(body.contains("gs.get_node_or_null") or body.contains("tree.root.get_node_or_null(\"GameState\")"),
		"helper must use scene-tree-root autoload lookup, not Engine.has_singleton")
	assert_true(body.contains("\"color_blind_mode\" in gs"),
		"helper must check for the color_blind_mode property before reading")
	assert_true(body.contains("bool(gs.color_blind_mode)"),
		"helper must coerce to bool")


# ── _spawn_elemental_indicator wiring ────────────────────────────────

func test_spawn_uses_helper_for_weak() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("color = _elem_weak_color()"),
		"_spawn_elemental_indicator's WEAK branch must call _elem_weak_color()")


# ── Negative pin: bare red literal gone from WEAK branch ─────────────

func test_no_bare_red_in_weak_branch() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# The pre-fix shape `color = Color(1.0, 0.3, 0.3)` directly inside
	# the spawn function must be gone — that color now lives in the
	# helper's default branch only.
	assert_false(body.contains("color = Color(1.0, 0.3, 0.3)  # Red"),
		"pre-fix bare red literal in WEAK branch must be gone (replaced by _elem_weak_color())")


# ── Colorblind-safe colors preserved (IMMUNE gray, RESIST blue) ──────

func test_immune_gray_preserved() -> void:
	# Pin: IMMUNE gray Color(0.7, 0.7, 0.7) is already colorblind-safe
	# (achromatic) and stays unchanged.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("color = Color(0.7, 0.7, 0.7)"),
		"IMMUNE gray preserved (colorblind-safe achromatic)")


func test_resist_blue_preserved() -> void:
	# Pin: RESIST blue Color(0.3, 0.5, 1.0) is colorblind-safe under
	# the most common types (protanopia/deuteranopia) — kept unchanged.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("color = Color(0.3, 0.5, 1.0)"),
		"RESIST blue preserved (colorblind-safe)")


# ── Magenta is distinct from prior CB-mode swaps (tick 226) ───────────

func test_magenta_distinct_from_tick_226_colors() -> void:
	# Cross-feature consistency check: WEAK magenta (1.0, 0.4, 0.8)
	# must not collide with heal cyan (0.30, 0.70, 1.00) or crit
	# yellow (1.00, 0.95, 0.40) from tick 226 — otherwise a player
	# with multiple popups stacked sees indistinguishable colors.
	var dn: String = FileAccess.get_file_as_string("res://src/ui/DamageNumber.gd")
	assert_true(dn.contains("return Color(0.30, 0.70, 1.00)"),
		"tick 226 heal cyan preserved")
	assert_true(dn.contains("return Color(1.00, 0.95, 0.40)"),
		"tick 226 crit yellow preserved")
	# Magenta R=1.0 G=0.4 B=0.8 — distinct from both.


# ── Live runtime behavior ────────────────────────────────────────────

func test_helper_runtime_default_returns_red() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = false
	# Instantiate BattleScene's helper via load — bare Control,
	# helper is an instance method so we need a fresh node.
	var cls = load(BATTLE_SCENE)
	var bs = cls.new()
	add_child_autofree(bs)
	var c := bs._elem_weak_color() as Color
	assert_almost_eq(c.r, 1.0, 0.001, "default R = 1.0")
	assert_almost_eq(c.g, 0.3, 0.001, "default G = 0.3")
	assert_almost_eq(c.b, 0.3, 0.001, "default B = 0.3")


func test_helper_runtime_accessibility_returns_magenta() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.color_blind_mode = true
	var cls = load(BATTLE_SCENE)
	var bs = cls.new()
	add_child_autofree(bs)
	var c := bs._elem_weak_color() as Color
	assert_almost_eq(c.r, 1.0, 0.001, "accessibility R = 1.0")
	assert_almost_eq(c.g, 0.40, 0.001, "accessibility G = 0.40")
	assert_almost_eq(c.b, 0.80, 0.001, "accessibility B = 0.80")
	# Reset.
	GameState.color_blind_mode = false


# ── Cross-pins: prior elem indicator work preserved ──────────────────

func test_tick_209_stagger_preserved() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("label.set_meta(\"elem_indicator\", true)"),
		"tick 209 elem_indicator meta tag preserved")


func test_tick_218_outline_preserved() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("label.add_theme_constant_override(\"outline_size\", 2)"),
		"tick 218 outline preserved")


func test_tick_226_damage_palette_preserved() -> void:
	var dn: String = FileAccess.get_file_as_string("res://src/ui/DamageNumber.gd")
	assert_true(dn.contains("func _heal_color() -> Color:"),
		"tick 226 _heal_color preserved")
	assert_true(dn.contains("func _crit_color() -> Color:"),
		"tick 226 _crit_color preserved")
