extends GutTest

## tick 210: EquipmentMenu stat display fixes two readability bugs.
##
## BUG 1: stat_name.capitalize() on "max_hp" / "max_mp" produces
## "Max Hp" / "Max Mp" — the HP/MP acronyms aren't preserved.
## Real-world JRPG convention is "Max HP" with full uppercase.
##
## BUG 2: stat_name.substr(0, 3).to_upper() on the per-item
## comparison row produces "MAX" for BOTH max_hp AND max_mp —
## ambiguous "+5 MAX" doesn't tell the player whether HP or MP
## was the gain. Classic JRPG abbreviations (ATK / DEF / MAG /
## SPD / HP / MP) disambiguate cleanly.
##
## Fix: explicit STAT_DISPLAY and STAT_SHORT maps with .capitalize()
## / substr fallbacks for unknown stat ids (Scriptweaver custom
## stats, future stats not yet mapped).

const EQUIPMENT_MENU := "res://src/ui/EquipmentMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _new_menu() -> Object:
	var scene = load(EQUIPMENT_MENU)
	return scene.new()


# ── STAT_DISPLAY map (long-form names) ─────────────────────────────────

func test_max_hp_displays_with_caps_acronym() -> void:
	# Pin: "max_hp" must display as "Max HP" not "Max Hp"
	# (the .capitalize() failure mode this fix exists for).
	var m = _new_menu()
	assert_eq(m._stat_display_name("max_hp"), "Max HP",
		"max_hp must display as 'Max HP' (acronym preserved)")
	m.queue_free()


func test_max_mp_displays_with_caps_acronym() -> void:
	var m = _new_menu()
	assert_eq(m._stat_display_name("max_mp"), "Max MP",
		"max_mp must display as 'Max MP'")
	m.queue_free()


func test_single_word_stats_display_correctly() -> void:
	var m = _new_menu()
	assert_eq(m._stat_display_name("attack"), "Attack",
		"attack → 'Attack'")
	assert_eq(m._stat_display_name("defense"), "Defense",
		"defense → 'Defense'")
	assert_eq(m._stat_display_name("magic"), "Magic",
		"magic → 'Magic'")
	assert_eq(m._stat_display_name("speed"), "Speed",
		"speed → 'Speed'")
	m.queue_free()


func test_unknown_stat_falls_back_to_capitalize() -> void:
	# Pin: unknown stat ids (Scriptweaver custom, future) cleanly
	# fall back to .capitalize() — no crash, no empty string.
	var m = _new_menu()
	# In Godot 4, .capitalize() on "fire_res" gives "Fire Res".
	# Whatever the result, it must be non-empty and start with uppercase.
	var result: String = m._stat_display_name("fire_res")
	assert_gt(result.length(), 0,
		"unknown stat must produce non-empty fallback")
	assert_eq(result[0], result[0].to_upper(),
		"unknown stat fallback must start with uppercase")
	m.queue_free()


# ── STAT_SHORT map (compact codes) ─────────────────────────────────────

func test_short_codes_disambiguate_hp_mp() -> void:
	# The core BUG 2 fix: pre-fix "MAX" for both → now "HP" and "MP"
	# are distinct.
	var m = _new_menu()
	assert_eq(m._stat_short_name("max_hp"), "HP",
		"max_hp short code must be 'HP' (not the collision 'MAX')")
	assert_eq(m._stat_short_name("max_mp"), "MP",
		"max_mp short code must be 'MP' (not the collision 'MAX')")
	assert_ne(m._stat_short_name("max_hp"), m._stat_short_name("max_mp"),
		"HP and MP short codes must be distinct (no 'MAX/MAX' ambiguity)")
	m.queue_free()


func test_short_codes_canonical_jrpg_abbreviations() -> void:
	# Pin: canonical JRPG abbreviations (ATK / DEF / MAG / SPD).
	var m = _new_menu()
	assert_eq(m._stat_short_name("attack"), "ATK",
		"attack → 'ATK' (canonical, not 'ATT')")
	assert_eq(m._stat_short_name("defense"), "DEF",
		"defense → 'DEF'")
	assert_eq(m._stat_short_name("magic"), "MAG",
		"magic → 'MAG'")
	assert_eq(m._stat_short_name("speed"), "SPD",
		"speed → 'SPD' (canonical, not 'SPE')")
	m.queue_free()


func test_unknown_stat_short_falls_back_to_substr() -> void:
	# Pin: unknown stat → substr(0, 3).to_upper() fallback preserved
	# (legacy behavior — better to leak something than crash).
	var m = _new_menu()
	# "fire_res" substr(0, 3).to_upper() = "FIR"
	assert_eq(m._stat_short_name("fire_res"), "FIR",
		"unknown stat falls back to substr(0, 3).to_upper()")
	m.queue_free()


# ── Const maps present ────────────────────────────────────────────────

func test_stat_display_map_const_defined() -> void:
	# Tick 211 extracted the maps from EquipmentMenu to the shared
	# StatNames class. Pin the maps' new home.
	var src: String = FileAccess.get_file_as_string("res://src/ui/StatNames.gd")
	assert_true(src.contains("const DISPLAY := {"),
		"DISPLAY const map must be defined on StatNames (post-tick 211 home)")


func test_stat_short_map_const_defined() -> void:
	# Tick 211 extracted the maps from EquipmentMenu to the shared
	# StatNames class.
	var src: String = FileAccess.get_file_as_string("res://src/ui/StatNames.gd")
	assert_true(src.contains("const SHORT := {"),
		"SHORT const map must be defined on StatNames")


# ── Wiring at the call sites ──────────────────────────────────────────

func test_bonus_label_uses_display_helper() -> void:
	# Pin: the equip_mods loop uses _stat_display_name, not the bare
	# .capitalize() fallback.
	var src := _read(EQUIPMENT_MENU)
	assert_true(src.contains("[_stat_display_name(stat_name), \"+\" if mod_value > 0 else \"\", mod_value]"),
		"bonus label must call _stat_display_name(stat_name)")


func test_comparison_row_uses_short_helper() -> void:
	# Pin: the diff comparison rows use _stat_short_name, not the
	# substring-collision fallback.
	var src := _read(EQUIPMENT_MENU)
	assert_true(src.contains("[diff, _stat_short_name(stat_name)]"),
		"comparison row must call _stat_short_name(stat_name)")


# ── Negative pins: old broken patterns gone ───────────────────────────

func test_old_capitalize_on_bonus_gone() -> void:
	var src := _read(EQUIPMENT_MENU)
	assert_false(src.contains("[stat_name.capitalize(), \"+\" if mod_value"),
		"old stat_name.capitalize() bonus label pattern must be gone")


func test_old_substr_collision_gone() -> void:
	# Both substr usages in the comparison loop must be replaced.
	var src := _read(EQUIPMENT_MENU)
	assert_false(src.contains("[diff, stat_name.substr(0, 3).to_upper()]"),
		"old substr(0, 3).to_upper() comparison pattern must be gone")


# ── Helper functions present ──────────────────────────────────────────

func test_helpers_present() -> void:
	var src := _read(EQUIPMENT_MENU)
	assert_true(src.contains("func _stat_display_name(stat_name: String) -> String:"),
		"_stat_display_name helper must exist")
	assert_true(src.contains("func _stat_short_name(stat_name: String) -> String:"),
		"_stat_short_name helper must exist")
