extends GutTest

## tick 218: BattleScene._spawn_elemental_indicator now applies a
## full-perimeter outline so RESIST/IMMUNE/WEAK text stays legible
## against busy backgrounds (Mode 7 floor grid lines especially).
##
## Pre-fix used font_shadow_color + shadow_offset (1, 1) only —
## that produces a shadow on the lower-right of each character but
## leaves the upper-left edge unprotected. Against the BattleMode7Floor
## grid (which uses Color(0.55, 0.45, 0.75, 0.85) — bright purple),
## the IMMUNE!  label's gray (Color(0.7, 0.7, 0.7)) is nearly
## isoluminant with the grid lines — text bleeds into the background
## wherever the shadow doesn't cover.
##
## Fix: match DamageNumber's contrast scheme — outline_size = 2 +
## font_outline_color = Color.BLACK. The shadow stays as a softness
## layer underneath, so the text gets both edge protection (outline)
## and surface protection (shadow).
##
## This is the long-deferred Mode 7 hit-text contrast fix that the
## audit schedules kept pointing to.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const DAMAGE_NUMBER := "res://src/ui/DamageNumber.gd"
const MODE7_FLOOR := "res://src/battle/BattleMode7Floor.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Outline applied to elemental indicator ────────────────────────────

func test_elem_indicator_has_outline() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("label.add_theme_constant_override(\"outline_size\", 2)"),
		"_spawn_elemental_indicator must set outline_size=2")
	assert_true(body.contains("label.add_theme_color_override(\"font_outline_color\", Color.BLACK)"),
		"_spawn_elemental_indicator must set font_outline_color=BLACK")


func test_shadow_kept_alongside_outline() -> void:
	# Pin: shadow stays as a secondary contrast layer. Belt + suspenders
	# — outline handles edges, shadow softens the type against the
	# background underneath.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("label.add_theme_color_override(\"font_shadow_color\", Color(0, 0, 0, 0.8))"),
		"shadow color preserved as a secondary contrast layer")
	assert_true(body.contains("label.add_theme_constant_override(\"shadow_offset_x\", 1)"),
		"shadow_offset_x preserved")


func test_outline_ordering_before_shadow() -> void:
	# Pin: outline overrides come BEFORE shadow overrides so reading
	# the code top-to-bottom, the "primary contrast" mechanism shows
	# up first.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var outline_idx: int = body.find("outline_size")
	var shadow_idx: int = body.find("font_shadow_color")
	assert_gt(outline_idx, -1)
	assert_gt(shadow_idx, -1)
	assert_lt(outline_idx, shadow_idx,
		"outline_size override must come BEFORE shadow_color (reading order = primary contrast first)")


# ── Symmetry with DamageNumber's existing contrast scheme ─────────────

func test_matches_damage_number_outline_pattern() -> void:
	# DamageNumber set the precedent: outline_size = 2, BLACK outline.
	# The elemental indicator now uses the same pattern — single
	# visual language across floating text.
	var dn: String = _read(DAMAGE_NUMBER)
	assert_true(dn.contains("add_theme_constant_override(\"outline_size\", 2)"),
		"DamageNumber's outline_size=2 must still be the reference pattern")
	assert_true(dn.contains("add_theme_color_override(\"font_outline_color\", Color.BLACK)"),
		"DamageNumber's BLACK outline must still be the reference pattern")


# ── Mode 7 floor color sanity (catches future visibility regressions) ──

func test_mode7_floor_color_alpha_known() -> void:
	# Pin: the floor color's alpha is < 1.0 so the background shows
	# through. Future floor opacity changes that approach alpha 1.0
	# would require revisiting contrast (currently we rely on the
	# alpha letting battlefield colors blend through).
	var src := _read(MODE7_FLOOR)
	assert_true(src.contains("floor_color: Color = Color(0.10, 0.06, 0.18, 0.55)"),
		"BattleMode7Floor.floor_color must remain at known alpha 0.55 (semi-transparent)")
	assert_true(src.contains("grid_color: Color = Color(0.55, 0.45, 0.75, 0.85)"),
		"BattleMode7Floor.grid_color must remain at known alpha 0.85")


# ── Cross-pin: tick 209 elem stagger preserved ─────────────────────────

func test_tick_209_stagger_preserved() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("label.set_meta(\"elem_indicator\", true)"),
		"tick 209 elem_indicator meta tag preserved")
	assert_true(src.contains("pos.y -= _count_recent_elem_indicators_near(pos) * ELEM_STAGGER_STEP"),
		"tick 209 stagger formula preserved")


# ── Non-regression: meta-tag still set BEFORE add_child ───────────────

func test_meta_still_set_before_add_child() -> void:
	# Tick 209 invariant — set_meta runs BEFORE add_child so back-to-
	# back spawns find the tag during the next stagger lookup.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var set_meta_idx: int = body.find("set_meta(\"elem_indicator\"")
	var add_child_idx: int = body.find("add_child(label)")
	assert_gt(set_meta_idx, -1)
	assert_gt(add_child_idx, -1)
	assert_lt(set_meta_idx, add_child_idx,
		"set_meta must still come before add_child (tick 209 invariant)")
