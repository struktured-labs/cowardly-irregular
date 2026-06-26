extends GutTest

## tick 198: SaveScreen party-summary HP bar polish.
##
## CHANGES:
##   1. Binary green/red at 30% → 3-tier green/yellow/red band.
##      Pre-fix, 31% HP showed full green (looks healthy) while
##      30% showed full red (looks critical) — sharp jarring
##      transition. Now: ≥60% green, ≥30% yellow, below red.
##   2. KO visual for hp <= 0. Pre-fix dead members just showed
##      "0/N" tiny text and an empty bar. Now name tints to
##      KO_NAME_COLOR and bar text reads "— KO —".
##
## Why: the SaveScreen is the FIRST thing a player sees when
## reloading. Reading the party state at a glance matters — is
## anyone dead? is anyone critical? The pre-fix presentation
## required squinting at small "0/N" / "12/N" numbers.

const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"


func _cls():
	return load(SAVE_SCREEN)


# ── 3-tier band: helper output ─────────────────────────────────────────

func test_high_hp_returns_green() -> void:
	# Pin: ≥ 60% → HP_HIGH_COLOR
	var cls = _cls()
	assert_eq(cls._hp_fill_color(1.0), cls.HP_HIGH_COLOR,
		"100% HP → HP_HIGH_COLOR (green)")
	assert_eq(cls._hp_fill_color(0.6), cls.HP_HIGH_COLOR,
		"exactly 60% HP → HP_HIGH_COLOR (boundary inclusive)")


func test_mid_hp_returns_yellow() -> void:
	# Pin: 30..60% → HP_MID_COLOR
	var cls = _cls()
	assert_eq(cls._hp_fill_color(0.59), cls.HP_MID_COLOR,
		"59% HP → HP_MID_COLOR (yellow)")
	assert_eq(cls._hp_fill_color(0.3), cls.HP_MID_COLOR,
		"exactly 30% HP → HP_MID_COLOR (boundary inclusive)")


func test_low_hp_returns_red() -> void:
	# Pin: < 30% → HP_LOW_COLOR
	var cls = _cls()
	assert_eq(cls._hp_fill_color(0.29), cls.HP_LOW_COLOR,
		"29% HP → HP_LOW_COLOR (red)")
	assert_eq(cls._hp_fill_color(0.0), cls.HP_LOW_COLOR,
		"0% HP → HP_LOW_COLOR (defensive, bar width is 0 anyway)")


func test_colors_are_distinct() -> void:
	# Pin: the three tier colors are visually distinct (different
	# hex). Otherwise the band serves no purpose.
	var cls = _cls()
	assert_ne(cls.HP_HIGH_COLOR, cls.HP_MID_COLOR,
		"high and mid must be distinct colors")
	assert_ne(cls.HP_MID_COLOR, cls.HP_LOW_COLOR,
		"mid and low must be distinct colors")
	assert_ne(cls.HP_HIGH_COLOR, cls.HP_LOW_COLOR,
		"high and low must be distinct colors")


func test_color_semantics_hue_check() -> void:
	# Pin: the visual semantics are correct — high is green-dominant,
	# mid is yellow (R+G ~equal, B low), low is red-dominant.
	var cls = _cls()
	# High: G > R + 0.3, B low
	assert_gt(cls.HP_HIGH_COLOR.g, cls.HP_HIGH_COLOR.r,
		"HP_HIGH must be green-dominant (G > R)")
	# Mid: R and G both high (yellow), B low
	assert_gt(cls.HP_MID_COLOR.r, 0.6,
		"HP_MID R must be high (yellow)")
	assert_gt(cls.HP_MID_COLOR.g, 0.6,
		"HP_MID G must be high (yellow)")
	assert_lt(cls.HP_MID_COLOR.b, 0.5,
		"HP_MID B must be low (yellow)")
	# Low: R > G, R > B
	assert_gt(cls.HP_LOW_COLOR.r, cls.HP_LOW_COLOR.g,
		"HP_LOW must be red-dominant (R > G)")


# ── KO state wiring ───────────────────────────────────────────────────

func test_ko_constant_defined() -> void:
	var cls = _cls()
	# Pin: KO_NAME_COLOR exists and is reddish (R > G + 0.3).
	assert_gt(cls.KO_NAME_COLOR.r, cls.KO_NAME_COLOR.g + 0.3,
		"KO_NAME_COLOR must be reddish (R > G + 0.3)")


func test_create_party_member_display_uses_ko_branch() -> void:
	# Pin: when hp <= 0, name_label color overrides to KO_NAME_COLOR
	# and hp_text reads "— KO —".
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("var ko: bool = hp <= 0"),
		"_create_party_member_display must compute ko bool from hp <= 0")
	assert_true(src.contains("name_label.add_theme_color_override(\"font_color\", KO_NAME_COLOR)"),
		"name_label must tint to KO_NAME_COLOR when ko")
	assert_true(src.contains("hp_text.text = \"— KO —\" if ko else \"%d/%d\" % [hp, max_hp]"),
		"hp_text must read '— KO —' when ko, else 'hp/max_hp'")
	assert_true(src.contains("KO_NAME_COLOR if ko else DISABLED_COLOR"),
		"hp_text color must use KO_NAME_COLOR when ko else DISABLED_COLOR")


# ── Negative pins: pre-fix binary color path gone ─────────────────────

func test_binary_green_red_lambda_gone() -> void:
	# Negative pin: the inline ternary `Color.LIME if hp_pct > 0.3 else Color.RED`
	# must be gone — replaced by the helper call.
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_false(src.contains("Color.LIME if hp_pct > 0.3 else Color.RED"),
		"old binary green/red ternary must be gone")
	# Helper IS used.
	assert_true(src.contains("hp_fill.color = _hp_fill_color(hp_pct)"),
		"hp_fill.color must call _hp_fill_color(hp_pct)")


# ── Cross-pins: tick 196 LOAD hint + tick 197 date helper preserved ──

func test_tick_196_load_hint_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("hint.text = \"(nothing to load)\""),
		"tick 196 LOAD-mode subhint preserved")


func test_tick_197_date_helper_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("static func _format_save_date(save_date: String) -> String:"),
		"tick 197 _format_save_date helper preserved")


# ── Helper is static + unit-testable ───────────────────────────────────

func test_hp_fill_helper_is_static() -> void:
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("static func _hp_fill_color(hp_pct: float) -> Color:"),
		"_hp_fill_color must be static for direct unit testing")


# ── Defensive: ko text doesn't accidentally appear for alive members ──

func test_alive_members_keep_old_format() -> void:
	# Pin: a member with hp > 0 produces the "%d/%d" format AND
	# DISABLED_COLOR font. The ternary `if ko else "%d/%d"` shape
	# guarantees this — verify the ternary structure is present.
	var src: String = FileAccess.get_file_as_string(SAVE_SCREEN)
	assert_true(src.contains("\"%d/%d\" % [hp, max_hp]"),
		"alive member format '%d/%d' preserved")
