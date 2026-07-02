extends GutTest

## tick 225: TextScale wired into the battle surface — the
## highest-time-spent screen in the game.
##
## Mechanical refactor across 2 files. BattleScene had 3
## different theme-override keys (font_size, bold_font_size,
## normal_font_size); the sed pass handles all three so 20
## sites scale together. BattleResultsDisplay's 11 sites
## (victory overlay) also wired so the post-battle summary
## scales consistently with the rest of battle UI.
##
## Coverage after tick 225 (TextScale consumers):
##   CutsceneDialogue
##   PartyStatusScreen
##   StatusMenu
##   QuestLog
##   BestiaryMenu
##   SaveScreen
##   JukeboxMenu
##   BattleScene           tick 225  (20 sites)
##   BattleResultsDisplay  tick 225  (11 sites)
##
## Roughly 130 font_size sites across the codebase now scale
## with the accessibility text-size setting.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const BATTLE_RESULTS_DISPLAY := "res://src/battle/BattleResultsDisplay.gd"


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


# ── Site counts ──────────────────────────────────────────────────────

func test_battle_scene_uses_text_scale_at_all_sites() -> void:
	# Pre-fix BattleScene had 20 font_size sites across 3 theme keys.
	# 2026-07-01: quip bubble extracted to BattleSpeechBubble.gd (msg 2101),
	# carrying 2 scaled sites with it — count both files as one surface.
	var src := _read(BATTLE_SCENE) + _read("res://src/battle/BattleSpeechBubble.gd")
	assert_gte(_count_calls(src), 20,
		"BattleScene + BattleSpeechBubble must have ≥20 TextScale.scaled calls (one per pre-fix font_size site)")


func test_battle_results_display_uses_text_scale() -> void:
	# Pre-fix BattleResultsDisplay had 11 font_size sites.
	var src := _read(BATTLE_RESULTS_DISPLAY)
	assert_gte(_count_calls(src), 11,
		"BattleResultsDisplay must have ≥11 TextScale.scaled calls")


# ── Negative pins: no bare integer font_size remaining ──────────────

func test_battle_scene_no_bare_integer_font_size() -> void:
	var src := _read(BATTLE_SCENE)
	# Covers font_size, bold_font_size, normal_font_size.
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"(font_size|bold_font_size|normal_font_size)\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"BattleScene must have NO bare integer font_size / bold_font_size / normal_font_size overrides: %s" % (match.get_string() if match else "(clean)"))


func test_battle_results_display_no_bare_integer_font_size() -> void:
	var src := _read(BATTLE_RESULTS_DISPLAY)
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"(font_size|bold_font_size|normal_font_size)\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"BattleResultsDisplay must have NO bare integer font_size overrides: %s" % (match.get_string() if match else "(clean)"))


# ── All 3 override keys handled ──────────────────────────────────────

func test_battle_scene_handles_normal_font_size_key() -> void:
	# Pin: the sed pattern covers `normal_font_size` (used by RichTextLabel
	# instances in battle). Pre-fix several RichTextLabel sites would
	# have been missed by a font_size-only sed.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("normal_font_size\", TextScale.scaled("),
		"BattleScene must scale `normal_font_size` overrides (RichTextLabel theme key)")


func test_battle_scene_handles_bold_font_size_key() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("bold_font_size\", TextScale.scaled("),
		"BattleScene must scale `bold_font_size` overrides")


# ── Cross-pins: prior TextScale wiring preserved ──────────────────────

func test_tick_224_quest_log_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/QuestLog.gd")
	assert_true(src.contains("TextScale.scaled(int(line[\"size\"]))"),
		"tick 224 QuestLog variable-site wrap preserved")


func test_tick_223_text_scale_util_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/TextScale.gd")
	assert_true(src.contains("static func scaled(base: int) -> int:"),
		"tick 223 TextScale.scaled preserved")
