extends GutTest

## tick 211: stat-name display logic extracted from EquipmentMenu
## (tick 210) to a shared StatNames class. Same fix applied across
## 5 surfaces that all had the same broken patterns:
##
##   - MenuScene equipment list (substr collision MAX/MAX)
##   - JobMenu job preview (had local max_hp guard but no max_mp)
##   - BattleUIManager buff/debuff list (inline dict missed HP/MP)
##   - AbilitiesMenu stat_mods display (capitalize acronym break)
##   - ShopScene item description (capitalize acronym break, 4 sites)
##
## Now every stat display surface produces "Max HP" (not "Max Hp")
## and distinguishes "HP"/"MP" (not the ambiguous "MAX/MAX"
## collision).

const STAT_NAMES := "res://src/ui/StatNames.gd"


# ── Long-form display ─────────────────────────────────────────────────

func test_display_name_known_stats() -> void:
	assert_eq(StatNames.display_name("attack"), "Attack",
		"attack → 'Attack'")
	assert_eq(StatNames.display_name("defense"), "Defense",
		"defense → 'Defense'")
	assert_eq(StatNames.display_name("magic"), "Magic",
		"magic → 'Magic'")
	assert_eq(StatNames.display_name("speed"), "Speed",
		"speed → 'Speed'")


func test_display_name_preserves_hp_mp_acronyms() -> void:
	# Core invariant from tick 210/211 — Godot's capitalize() gives
	# "Max Hp" which is wrong. Explicit map gives "Max HP".
	assert_eq(StatNames.display_name("max_hp"), "Max HP",
		"max_hp must display as 'Max HP'")
	assert_eq(StatNames.display_name("max_mp"), "Max MP",
		"max_mp must display as 'Max MP'")


func test_display_name_falls_back_to_capitalize() -> void:
	# Unknown stats fall back to .capitalize() (Godot 4 word-aware).
	var result: String = StatNames.display_name("fire_resist")
	assert_gt(result.length(), 0,
		"unknown stat must produce non-empty fallback")
	assert_eq(result[0], result[0].to_upper(),
		"fallback starts with uppercase")


func test_display_name_empty_returns_empty() -> void:
	assert_eq(StatNames.display_name(""), "",
		"empty input → empty output (no crash)")


# ── Short code ────────────────────────────────────────────────────────

func test_short_code_canonical_jrpg_abbreviations() -> void:
	assert_eq(StatNames.short_code("attack"), "ATK", "attack → 'ATK'")
	assert_eq(StatNames.short_code("defense"), "DEF", "defense → 'DEF'")
	assert_eq(StatNames.short_code("magic"), "MAG", "magic → 'MAG'")
	assert_eq(StatNames.short_code("speed"), "SPD", "speed → 'SPD'")


func test_short_code_disambiguates_hp_mp() -> void:
	# Core invariant — pre-fix both max_hp and max_mp got "MAX" from
	# substr(0, 3).to_upper(). Now distinct.
	assert_eq(StatNames.short_code("max_hp"), "HP",
		"max_hp short code 'HP' (not 'MAX')")
	assert_eq(StatNames.short_code("max_mp"), "MP",
		"max_mp short code 'MP' (not 'MAX')")
	assert_ne(StatNames.short_code("max_hp"), StatNames.short_code("max_mp"),
		"HP and MP short codes must be distinct")


func test_short_code_falls_back_to_substr() -> void:
	# Unknown stats fall back to substr(0, 3).to_upper().
	assert_eq(StatNames.short_code("fire_resist"), "FIR",
		"unknown stat → first 3 chars uppercase")


func test_short_code_empty_returns_empty() -> void:
	assert_eq(StatNames.short_code(""), "",
		"empty input → empty output (no crash)")


# ── Call site refactors ──────────────────────────────────────────────

func test_equipment_menu_delegates_to_stat_names() -> void:
	# EquipmentMenu's local helpers now delegate to StatNames (single
	# source of truth).
	var src: String = FileAccess.get_file_as_string("res://src/ui/EquipmentMenu.gd")
	assert_true(src.contains("return StatNames.display_name(stat_name)"),
		"EquipmentMenu._stat_display_name delegates")
	assert_true(src.contains("return StatNames.short_code(stat_name)"),
		"EquipmentMenu._stat_short_name delegates")
	# Local const maps removed (single source of truth).
	assert_false(src.contains("const STAT_DISPLAY := {"),
		"EquipmentMenu's local STAT_DISPLAY const removed")
	assert_false(src.contains("const STAT_SHORT := {"),
		"EquipmentMenu's local STAT_SHORT const removed")


func test_menu_scene_uses_stat_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/MenuScene.gd")
	assert_true(src.contains("StatNames.short_code(stat)"),
		"MenuScene equipment list uses StatNames.short_code")
	assert_false(src.contains("stat.substr(0, 3).to_upper()"),
		"MenuScene's old substr collision pattern removed")


func test_job_menu_uses_stat_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/JobMenu.gd")
	assert_true(src.contains("StatNames.short_code(stat_name)"),
		"JobMenu uses StatNames.short_code")
	# Old local max_hp guard removed (StatNames handles all known stats).
	assert_false(src.contains("if stat_name == \"max_hp\":\n\t\t\t\tshort_name = \"HP\""),
		"JobMenu's local max_hp guard removed (StatNames covers it)")


func test_battle_ui_manager_uses_stat_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_true(src.contains("var abbrev: String = StatNames.short_code(stat_name)"),
		"BattleUIManager buff/debuff uses StatNames.short_code")
	# Old inline dict removed.
	assert_false(src.contains("{\"attack\": \"ATK\", \"defense\": \"DEF\", \"magic\": \"MAG\", \"speed\": \"SPD\"}"),
		"BattleUIManager's inline abbreviation dict removed")


func test_abilities_menu_uses_stat_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/AbilitiesMenu.gd")
	assert_true(src.contains("StatNames.display_name(stat)"),
		"AbilitiesMenu uses StatNames.display_name(stat)")
	assert_true(src.contains("StatNames.display_name(mod_name)"),
		"AbilitiesMenu uses StatNames.display_name(mod_name)")
	# Old capitalize() on stat removed.
	assert_false(src.contains("stat.capitalize()"),
		"AbilitiesMenu's stat.capitalize() removed")
	assert_false(src.contains("mod_name.capitalize()"),
		"AbilitiesMenu's mod_name.capitalize() removed")


func test_shop_scene_uses_stat_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")
	# All 4 desc lines now use StatNames.
	var idx: int = 0
	var count: int = 0
	while true:
		var next: int = src.find("StatNames.display_name(stat)", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_gte(count, 4,
		"ShopScene must have at least 4 StatNames.display_name(stat) calls")
	# Old capitalize on stat removed in those sites.
	assert_false(src.contains("[stat.capitalize(), value]"),
		"ShopScene's stat.capitalize() patterns removed")


# ── Helpers are static ────────────────────────────────────────────────

func test_helpers_are_static() -> void:
	var src: String = FileAccess.get_file_as_string(STAT_NAMES)
	assert_true(src.contains("static func display_name(stat_name: String) -> String:"),
		"display_name must be static")
	assert_true(src.contains("static func short_code(stat_name: String) -> String:"),
		"short_code must be static")
