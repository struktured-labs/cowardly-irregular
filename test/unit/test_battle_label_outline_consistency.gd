extends GutTest

## tick 219: extends tick 218's outline contrast pattern to the
## remaining shadow-only Labels in BattleScene.
##
## Pre-fix 7 labels used font_shadow_color without
## font_outline_color — sprite name labels (below sprites, on
## Mode 7 floor), one-shot celebration text (one_shot_label,
## rank_label, bonus_label), and autobattle celebration text
## (auto_label, turns_label, bonus_label). The shadow alone is
## offset (lower-right only) — upper-left edges blend into busy
## backgrounds (Mode 7 grid lines, scene tints, post-flash floor).
##
## Fix: each site now adds outline_size + font_outline_color
## BEFORE the existing shadow overrides. Single visual language
## across all floating text in battle:
##   - DamageNumber (pre-existing)
##   - Elemental indicators (tick 218)
##   - Sprite name labels (tick 219)
##   - One-shot celebration text (tick 219)
##   - Autobattle celebration text (tick 219)
##
## Tick 218 used outline_size = 2 for 14pt elem indicators.
## Sprite name labels at 10pt use outline_size = 1
## (proportionate). Celebration labels at 22-48pt all use 2 —
## consistent visual weight regardless of size (the size itself
## scales the apparent thickness).

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── _add_sprite_label (name labels under sprites) ──────────────────────

func test_sprite_label_has_outline() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _add_sprite_label")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Size-proportional outline (10pt → 1px outline).
	assert_true(body.contains("label.add_theme_constant_override(\"outline_size\", 1)"),
		"_add_sprite_label must use outline_size=1 (proportional to 10pt font)")
	assert_true(body.contains("label.add_theme_color_override(\"font_outline_color\", Color.BLACK)"),
		"_add_sprite_label must use BLACK outline color")


# ── Celebration labels (one-shot + autobattle) ────────────────────────

func test_one_shot_label_has_outline() -> void:
	# Pin: ONE-SHOT! 48pt label gets outline_size=2.
	var src := _read(BATTLE_SCENE)
	# Find the one_shot_label setup region (anchored by 'ONE-SHOT!').
	var idx: int = src.find("one_shot_label.text = \"ONE-SHOT!\"")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("one_shot_label.add_theme_constant_override(\"outline_size\", 2)"),
		"one_shot_label must have outline_size=2")
	assert_true(window.contains("one_shot_label.add_theme_color_override(\"font_outline_color\", Color.BLACK)"),
		"one_shot_label must have BLACK outline color")


func test_rank_label_has_outline() -> void:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("rank_label.text = \"Rank:")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("rank_label.add_theme_constant_override(\"outline_size\", 2)"),
		"rank_label must have outline_size=2")
	assert_true(window.contains("rank_label.add_theme_color_override(\"font_outline_color\", Color.BLACK)"),
		"rank_label must have BLACK outline color")


func test_auto_label_has_outline() -> void:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("auto_label.text = \"AUTO-BATTLE!\"")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("auto_label.add_theme_constant_override(\"outline_size\", 2)"),
		"auto_label must have outline_size=2")


func test_turns_label_has_outline() -> void:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("turns_label.text = \"%d turns automated\"")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("turns_label.add_theme_constant_override(\"outline_size\", 2)"),
		"turns_label must have outline_size=2")


func test_bonus_labels_have_outline() -> void:
	# Two bonus_label sites (one-shot + autobattle ctx). Both should
	# have outline_size=2. Count occurrences of the pattern.
	var src := _read(BATTLE_SCENE)
	var pattern := "bonus_label.add_theme_constant_override(\"outline_size\", 2)"
	var idx: int = 0
	var count: int = 0
	while true:
		var next: int = src.find(pattern, idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_gte(count, 2,
		"both bonus_label sites must have outline_size=2 (one-shot + autobattle)")


# ── Shadow preservation ────────────────────────────────────────────────

func test_shadows_all_preserved() -> void:
	# Pin: outline is ADDED, shadow stays. Belt + suspenders contrast.
	var src := _read(BATTLE_SCENE)
	# Count font_shadow_color occurrences. Pre-fix: 6 sites in BattleScene
	# (line numbers from grep tick 219). Post-fix should match.
	var pattern := "font_shadow_color"
	var idx: int = 0
	var count: int = 0
	while true:
		var next: int = src.find(pattern, idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	# At least 7 sites (sprite label + 6 celebration labels).
	assert_gte(count, 7,
		"at least 7 shadow sites must still be present (no shadow removed)")


# ── Symmetry with tick 218 ─────────────────────────────────────────────

func test_tick_218_elem_indicator_outline_preserved() -> void:
	# Cross-pin: don't regress tick 218.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("label.add_theme_constant_override(\"outline_size\", 2)"),
		"tick 218 elem indicator outline preserved")
	assert_true(body.contains("label.add_theme_color_override(\"font_outline_color\", Color.BLACK)"),
		"tick 218 BLACK outline color preserved")


# ── Symmetry with DamageNumber's pre-existing scheme ──────────────────

func test_damage_number_outline_pattern_unchanged() -> void:
	# DamageNumber set the precedent. All these BattleScene labels
	# now match the same scheme. Confirm DamageNumber wasn't touched.
	var dn: String = FileAccess.get_file_as_string("res://src/ui/DamageNumber.gd")
	assert_true(dn.contains("add_theme_constant_override(\"outline_size\", 2)"),
		"DamageNumber outline_size=2 preserved (the reference)")
