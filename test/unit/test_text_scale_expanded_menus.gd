extends GutTest

## tick 224: extends tick 223's TextScale wiring to 4 more menus:
## QuestLog, BestiaryMenu, SaveScreen, JukeboxMenu.
##
## Now 7 menus consume the accessibility text-size setting:
##   CutsceneDialogue   tick 222 (precursor, now via TextScale)
##   PartyStatusScreen  tick 223
##   StatusMenu         tick 223
##   QuestLog           tick 224  (6 sites — 5 integer + 1 variable)
##   BestiaryMenu       tick 224  (15 sites)
##   SaveScreen         tick 224  (17 sites)
##   JukeboxMenu        tick 224  (7 sites)
##
## QuestLog has a variable-based font_size site (`line["size"]`).
## The sed pass only caught integer literals; the variable site
## was manually wrapped: TextScale.scaled(int(line["size"])).
##
## ~45 font_size sites across the 4 menus now scale.

const QUEST_LOG := "res://src/ui/QuestLog.gd"
const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"
const SAVE_SCREEN := "res://src/ui/SaveScreen.gd"
const JUKEBOX_MENU := "res://src/ui/JukeboxMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _count_calls(src: String) -> int:
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("TextScale.scaled(", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	return count


# ── Each menu uses TextScale at expected site counts ──────────────────

func test_quest_log_uses_text_scale_at_all_sites() -> void:
	var src := _read(QUEST_LOG)
	# 5 integer literals + 1 variable = 6 total font_size sites,
	# all should be wrapped now.
	assert_gte(_count_calls(src), 6,
		"QuestLog must have ≥6 TextScale.scaled calls (was 6 raw font_size sites)")


func test_bestiary_menu_uses_text_scale() -> void:
	var src := _read(BESTIARY_MENU)
	assert_gte(_count_calls(src), 15,
		"BestiaryMenu must have ≥15 TextScale.scaled calls")


func test_save_screen_uses_text_scale() -> void:
	var src := _read(SAVE_SCREEN)
	assert_gte(_count_calls(src), 17,
		"SaveScreen must have ≥17 TextScale.scaled calls")


func test_jukebox_menu_uses_text_scale() -> void:
	var src := _read(JUKEBOX_MENU)
	assert_gte(_count_calls(src), 7,
		"JukeboxMenu must have ≥7 TextScale.scaled calls")


# ── Negative pins: no bare integer font_size left ─────────────────────

func test_quest_log_no_bare_integer_font_size() -> void:
	var src := _read(QUEST_LOG)
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"QuestLog must have NO bare integer font_size overrides: %s" % (match.get_string() if match else "(clean)"))


func test_bestiary_menu_no_bare_integer_font_size() -> void:
	var src := _read(BESTIARY_MENU)
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"BestiaryMenu must have NO bare integer font_size overrides: %s" % (match.get_string() if match else "(clean)"))


func test_save_screen_no_bare_integer_font_size() -> void:
	var src := _read(SAVE_SCREEN)
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"SaveScreen must have NO bare integer font_size overrides: %s" % (match.get_string() if match else "(clean)"))


func test_jukebox_menu_no_bare_integer_font_size() -> void:
	var src := _read(JUKEBOX_MENU)
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"JukeboxMenu must have NO bare integer font_size overrides: %s" % (match.get_string() if match else "(clean)"))


# ── QuestLog variable site handled correctly ──────────────────────────

func test_quest_log_variable_size_wrapped() -> void:
	# Pin: the variable-driven font_size site (`line["size"]`) was
	# manually wrapped in TextScale.scaled(int(...)). The sed pass
	# wouldn't have caught it (matches integer literals only).
	var src := _read(QUEST_LOG)
	assert_true(src.contains("TextScale.scaled(int(line[\"size\"]))"),
		"QuestLog's variable-driven line['size'] site must be wrapped in TextScale.scaled(int(...))")


# ── Cross-pins: ticks 222 + 223 preserved ─────────────────────────────

func test_tick_223_text_scale_util_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/TextScale.gd")
	assert_true(src.contains("static func scaled(base: int) -> int:"),
		"tick 223 TextScale.scaled preserved")


func test_tick_223_party_status_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/PartyStatusScreen.gd")
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	assert_eq(rgx.search(src), null,
		"tick 223 PartyStatusScreen refactor preserved (no bare integer font_size)")


func test_tick_222_settings_menu_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_true(src.contains("const TEXT_SIZE_PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]"),
		"tick 222 TEXT_SIZE_PRESETS preserved")
