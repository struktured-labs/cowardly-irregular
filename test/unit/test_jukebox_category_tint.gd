extends GutTest

## tick 201: jukebox rows now get a per-category color tint so the
## 150-entry alphabetical list reads as vertical color bands. Battle
## tracks are muted red, boss tracks are gold, overworld is cyan,
## village is pastel blue, dungeon is purple, danger is orange.
## Active playback still wins (PLAYING_COLOR green overrides).
##
## Why: post-tick-199 the jukebox has 150 entries vs the prior 29.
## Duration suffixes (tick 200) help skim but the eye still needs
## category boundaries. A tint band shows where battle_* ends and
## boss_* begins without inline section headers (which would require
## navigation skip logic).

const JUKEBOX_MENU := "res://src/ui/JukeboxMenu.gd"


func _cls():
	return load(JUKEBOX_MENU)


# ── Category prefix dispatch ──────────────────────────────────────────

func test_boss_prefix_returns_gold() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("boss_medieval"), cls.CAT_BOSS_COLOR,
		"boss_* → CAT_BOSS_COLOR (gold)")
	assert_eq(cls._category_color("boss_rat_king"), cls.CAT_BOSS_COLOR,
		"boss_rat_king → CAT_BOSS_COLOR")
	assert_eq(cls._category_color("boss_warden_medieval"), cls.CAT_BOSS_COLOR,
		"masterite boss tracks → CAT_BOSS_COLOR")


func test_battle_prefix_returns_red() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("battle_medieval"), cls.CAT_BATTLE_COLOR,
		"battle_* → CAT_BATTLE_COLOR (red)")
	assert_eq(cls._category_color("battle_slime"), cls.CAT_BATTLE_COLOR,
		"battle_slime → CAT_BATTLE_COLOR")


func test_overworld_prefix_returns_cyan() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("overworld_medieval"), cls.CAT_OVERWORLD_COLOR,
		"overworld_* → CAT_OVERWORLD_COLOR (cyan)")
	assert_eq(cls._category_color("overworld_abstract"), cls.CAT_OVERWORLD_COLOR,
		"all 6 world overworlds map to the same tint")


func test_village_prefix_returns_blue() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("village_medieval"), cls.CAT_VILLAGE_COLOR,
		"village_* → CAT_VILLAGE_COLOR (blue)")


func test_dungeon_prefix_returns_purple() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("dungeon_medieval"), cls.CAT_DUNGEON_COLOR,
		"dungeon_* → CAT_DUNGEON_COLOR (purple)")


func test_danger_prefix_returns_orange() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("danger_medieval"), cls.CAT_DANGER_COLOR,
		"danger_* → CAT_DANGER_COLOR (orange)")
	assert_eq(cls._category_color("danger"), cls.CAT_DANGER_COLOR,
		"bare 'danger' id → CAT_DANGER_COLOR (legacy spec)")


# ── Unknown / uncategorized stays TEXT_COLOR ───────────────────────────

func test_uncategorized_ids_return_text_color() -> void:
	var cls = _cls()
	assert_eq(cls._category_color("title"), cls.TEXT_COLOR,
		"title → default TEXT_COLOR")
	assert_eq(cls._category_color("victory"), cls.TEXT_COLOR,
		"victory → default TEXT_COLOR")
	assert_eq(cls._category_color("game_over"), cls.TEXT_COLOR,
		"game_over → default TEXT_COLOR")
	assert_eq(cls._category_color("autogrind"), cls.TEXT_COLOR,
		"autogrind → default TEXT_COLOR")
	assert_eq(cls._category_color(""), cls.TEXT_COLOR,
		"empty id → default TEXT_COLOR (defensive)")


# ── Constants are distinct (otherwise the band serves no purpose) ─────

func test_all_category_colors_are_distinct() -> void:
	var cls = _cls()
	var palette: Array = [
		cls.CAT_BATTLE_COLOR,
		cls.CAT_BOSS_COLOR,
		cls.CAT_OVERWORLD_COLOR,
		cls.CAT_VILLAGE_COLOR,
		cls.CAT_DUNGEON_COLOR,
		cls.CAT_DANGER_COLOR,
		cls.TEXT_COLOR,
		cls.PLAYING_COLOR,
	]
	for i in palette.size():
		for j in range(i + 1, palette.size()):
			assert_ne(palette[i], palette[j],
				"category colors must all be distinct (index %d == %d)" % [i, j])


func test_category_colors_avoid_playing_color_hue() -> void:
	# Pin: no category tint should be too close to PLAYING_COLOR's
	# bright lime green (0.3, 1.0, 0.4). Otherwise the "is this
	# track playing?" signal becomes ambiguous.
	var cls = _cls()
	var play_g: float = cls.PLAYING_COLOR.g
	for cat in [cls.CAT_BATTLE_COLOR, cls.CAT_BOSS_COLOR, cls.CAT_OVERWORLD_COLOR,
			cls.CAT_VILLAGE_COLOR, cls.CAT_DUNGEON_COLOR, cls.CAT_DANGER_COLOR]:
		# Category should NOT be a pure bright-green (G > 0.95 and R < 0.4).
		var is_too_green: bool = cat.g > 0.95 and cat.r < 0.4
		assert_false(is_too_green,
			"category color (%s) too close to PLAYING_COLOR hue" % cat)


# ── Wiring: _refresh_list calls _category_color for the fallback ──────

func test_refresh_list_uses_category_color() -> void:
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("PLAYING_COLOR if track_id == _currently_playing else _category_color(track_id)"),
		"_refresh_list must use _category_color as the non-playing fallback")


func test_old_bare_text_color_fallback_gone() -> void:
	# Negative pin: the prior shape `PLAYING_COLOR if ... else TEXT_COLOR`
	# in _refresh_list must be gone (it's the bare fallback being replaced).
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	# Find _refresh_list body.
	var fn_idx: int = src.find("func _refresh_list")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("else TEXT_COLOR"),
		"_refresh_list's TEXT_COLOR fallback must be replaced by _category_color")


# ── Helper is static ──────────────────────────────────────────────────

func test_helper_is_static() -> void:
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("static func _category_color(track_id: String) -> Color:"),
		"_category_color must be a static helper")


# ── Cross-pins: prior jukebox ticks preserved ─────────────────────────

func test_tick_199_manifest_load_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("static func _load_manifest_tracks() -> Array:"),
		"tick 199 _load_manifest_tracks preserved")


func test_tick_200_duration_format_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(JUKEBOX_MENU)
	assert_true(src.contains("static func _format_duration(sec: float) -> String:"),
		"tick 200 _format_duration preserved")
	assert_true(src.contains("var dur_str: String = _format_duration"),
		"tick 200 duration suffix wiring preserved")


# ── Integration: live manifest produces multi-band coverage ───────────

func test_live_manifest_covers_multiple_categories() -> void:
	# Pin: the live manifest has tracks across multiple categories,
	# so the tint helper actually creates visible bands. Catches a
	# regression where manifest schema change collapses all tracks
	# into one category (or none).
	var cls = _cls()
	var tracks: Array = cls._load_manifest_tracks()
	var category_counts: Dictionary = {}
	for t in tracks:
		var color = cls._category_color(t[0])
		var key: String = "%s_%s_%s" % [color.r, color.g, color.b]
		category_counts[key] = category_counts.get(key, 0) + 1
	assert_gte(category_counts.size(), 4,
		"live manifest must produce at least 4 distinct color bands (got %d)" % category_counts.size())
