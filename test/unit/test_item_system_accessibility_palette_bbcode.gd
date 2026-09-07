extends GutTest

## tick 297: ItemSystem battle-log messages now route lime/red through
## AccessibilityPalette.bonus_bbcode() / penalty_bbcode().
##
## Pre-fix 6 hardcoded color tags survived ticks 237/238's
## BattleManager palette refactor:
##   - revive line × 2 (line 352/356)
##   - heal_hp line  (line 366)
##   - heal_hp_percent line (line 376)
##   - elemental damage line (line 475)
##
## In colorblind mode (AccessibilityPalette.is_on() == true), bonus
## _bbcode() swaps lime → cyan and penalty_bbcode() swaps red →
## magenta. Hardcoded "lime" / "red" stayed unswapped — heal-positive
## and damage-negative semantics didn't survive into the accessibility
## palette. Players using colorblind mode saw a green that the rest
## of the battle log no longer used.

const ITEM_SYSTEM := "res://src/items/ItemSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Hardcoded lime/red BBCode in battle_log_message removed ──────

func test_no_hardcoded_lime_in_battle_log_emits() -> void:
	# Only audit lines that go through battle_log_message — print()
	# debug strings can stay literal.
	var src := _read(ITEM_SYSTEM)
	# Strict pin: no `[color=lime]` should appear in a battle_log
	# _message emit line. Iterate lines so we can scope correctly.
	var offenders: Array[String] = []
	var line_no: int = 0
	for line in src.split("\n"):
		line_no += 1
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if "battle_log_message.emit" in stripped and "color=lime" in stripped:
			offenders.append("line %d: %s" % [line_no, stripped])
	assert_eq(offenders.size(), 0,
		"no `[color=lime]` should survive in battle_log_message emits (use bonus_bbcode): %s" % str(offenders))


func test_no_hardcoded_red_in_battle_log_emits() -> void:
	var src := _read(ITEM_SYSTEM)
	var offenders: Array[String] = []
	var line_no: int = 0
	for line in src.split("\n"):
		line_no += 1
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if "battle_log_message.emit" in stripped and "color=red" in stripped:
			offenders.append("line %d: %s" % [line_no, stripped])
	assert_eq(offenders.size(), 0,
		"no `[color=red]` should survive in battle_log_message emits (use penalty_bbcode): %s" % str(offenders))


# ── bonus_bbcode / penalty_bbcode now referenced ─────────────────

func test_palette_helpers_referenced() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("AccessibilityPalette.bonus_bbcode()"),
		"ItemSystem must reference AccessibilityPalette.bonus_bbcode() for heal/positive lines")
	assert_true(src.contains("AccessibilityPalette.penalty_bbcode()"),
		"ItemSystem must reference AccessibilityPalette.penalty_bbcode() for damage/negative lines")


# ── Cross-pin: BattleManager's tick-237 palette wiring still live ─

func test_battle_manager_palette_wiring_preserved() -> void:
	var bm: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm.contains("AccessibilityPalette.bonus_bbcode()"),
		"BattleManager must still use AccessibilityPalette.bonus_bbcode() (tick 237 fix)")
	assert_true(bm.contains("AccessibilityPalette.penalty_bbcode()"),
		"BattleManager must still use AccessibilityPalette.penalty_bbcode() (tick 237 fix)")


# ── Behavioral: bonus_bbcode actually returns cyan in accessibility mode ─

func test_palette_helper_swaps_in_accessibility_mode() -> void:
	# Defensive: confirm the helper works as documented. If
	# AccessibilityPalette ever drifts, this catches it before
	# downstream consumers like ItemSystem regress quietly.
	# AccessibilityPalette.is_on() reads GameState.color_blind_mode
	# directly, not game_constants.
	var prior = GameState.color_blind_mode
	GameState.color_blind_mode = true
	var on_bonus: String = AccessibilityPalette.bonus_bbcode()
	var on_penalty: String = AccessibilityPalette.penalty_bbcode()
	GameState.color_blind_mode = false
	var off_bonus: String = AccessibilityPalette.bonus_bbcode()
	var off_penalty: String = AccessibilityPalette.penalty_bbcode()
	# Restore.
	GameState.color_blind_mode = prior

	assert_eq(on_bonus, "cyan", "accessibility-on bonus must be cyan")
	assert_eq(on_penalty, "magenta", "accessibility-on penalty must be magenta")
	assert_eq(off_bonus, "lime", "accessibility-off bonus must be lime")
	assert_eq(off_penalty, "red", "accessibility-off penalty must be red")
