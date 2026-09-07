extends GutTest

## tick 239: extends ticks 237-238's BBCode palette refactor to
## BattleScene's log_message emits. 6 semantically-clear sites
## refactored:
##
##   Penalty (red default / magenta accessibility):
##     - "=== DEFEAT ===" header
##     - "✖ %s has fallen!" (party member KO)
##
##   Bonus (lime/green default / cyan accessibility):
##     - "Autobattle enabled - AI will control your turns"
##     - ">>> AUTOBATTLE: ALL PLAYERS ENABLED"
##     - "=== VICTORY ===" header
##     - "%s: \"%s\"" PC dialogue speaker line
##
## Cyan log_message sites (battle title banner, battle start/retry,
## formation announce) intentionally left as bare [color=cyan] —
## cyan is already colorblind-safe (matches the accessibility
## palette's "positive/cool" color even at default).

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Penalty refactors ────────────────────────────────────────────────

func test_defeat_header_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("\\n[color=%s]=== DEFEAT ===[/color]\" % AccessibilityPalette.penalty_bbcode()"),
		"DEFEAT header must use penalty_bbcode()")


func test_party_fallen_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("[color=%s]✖ %s has fallen![/color]\" % [AccessibilityPalette.penalty_bbcode(), member.combatant_name]"),
		"Party-member fallen log must use penalty_bbcode()")


# ── Bonus refactors ──────────────────────────────────────────────────

func test_autobattle_enabled_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("[color=%s]Autobattle enabled - AI will control your turns[/color]\" % AccessibilityPalette.bonus_bbcode()"),
		"'Autobattle enabled' must use bonus_bbcode()")


func test_all_players_autobattle_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("[color=%s]>>> AUTOBATTLE: ALL PLAYERS ENABLED[/color]\" % AccessibilityPalette.bonus_bbcode()"),
		"AUTOBATTLE all-players announcement must use bonus_bbcode()")


func test_victory_header_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("\\n[color=%s]=== VICTORY ===[/color]\" % AccessibilityPalette.bonus_bbcode()"),
		"VICTORY header must use bonus_bbcode()")


func test_dialogue_speaker_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("[color=%s]%s:[/color] \\\"%s\\\"\" % [AccessibilityPalette.bonus_bbcode(), speaker.combatant_name, line]"),
		"PC dialogue speaker line must use bonus_bbcode()")


# ── Cyan log_message sites still bare (intentional) ──────────────────

func test_cyan_sites_intentionally_bare() -> void:
	# Cyan is already colorblind-safe AND matches the accessibility
	# "positive" color. Leaving these as bare [color=cyan] is correct.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("[color=cyan]=== COWARDLY IRREGULAR ===[/color]"),
		"Title banner stays bare cyan (already colorblind-safe)")
	assert_true(src.contains("[color=cyan]Starting new battle...[/color]"),
		"Battle start stays bare cyan")
	assert_true(src.contains("[color=cyan]Retrying battle...[/color]"),
		"Battle retry stays bare cyan")


# ── Coverage count: BattleScene palette usage after tick 239 ─────────

func test_battle_scene_palette_usage_count() -> void:
	var src := _read(BATTLE_SCENE)
	var penalty_count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("AccessibilityPalette.penalty_bbcode()", idx)
		if next < 0:
			break
		penalty_count += 1
		idx = next + 1
	var bonus_count: int = 0
	idx = 0
	while true:
		var next: int = src.find("AccessibilityPalette.bonus_bbcode()", idx)
		if next < 0:
			break
		bonus_count += 1
		idx = next + 1
	assert_gte(penalty_count, 2,
		"BattleScene must have ≥2 penalty_bbcode usages (DEFEAT header + party fallen)")
	assert_gte(bonus_count, 4,
		"BattleScene must have ≥4 bonus_bbcode usages (autobattle on, all-autobattle, VICTORY, dialogue)")


# ── Cross-pins: tick 237 + 238 BattleManager work preserved ──────────

func test_battle_manager_palette_usage_preserved() -> void:
	var bm: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm.contains("AccessibilityPalette.penalty_bbcode()"),
		"BattleManager penalty_bbcode usage preserved (ticks 237/238)")
	assert_true(bm.contains("AccessibilityPalette.bonus_bbcode()"),
		"BattleManager bonus_bbcode usage preserved (ticks 237/238)")


func test_palette_bbcode_helpers_preserved() -> void:
	var palette: String = FileAccess.get_file_as_string("res://src/ui/AccessibilityPalette.gd")
	assert_true(palette.contains("static func bonus_bbcode() -> String:"),
		"AccessibilityPalette.bonus_bbcode helper preserved")
	assert_true(palette.contains("static func penalty_bbcode() -> String:"),
		"AccessibilityPalette.penalty_bbcode helper preserved")
