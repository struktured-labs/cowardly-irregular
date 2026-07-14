extends GutTest

## tick 215: shared StatusNames util consolidates four status-
## display sites that each prettified the status id slightly
## differently.
##
## Pre-fix sites:
##   - StatusMenu.gd:405 — status.replace("_", " ").capitalize()
##   - AutobattleGridEditor.gd:1010 — status.capitalize()
##   - BattleManager.gd:2804 — effect.capitalize() (status inflict log)
##   - BattleManager.gd:2896 — effect.capitalize() (magic inflict log)
##
## In Godot 4 .capitalize() is word-aware on underscores so all
## four produced identical output. The risk was content drift —
## a future status needing custom phrasing (e.g. "regen" →
## "Regenerating") would only land at whichever site got updated.
##
## Fix: src/ui/StatusNames.gd as single source. Each site calls
## StatusNames.display(name). The DISPLAY_OVERRIDES const is the
## extension point — empty for now, but content additions touch
## one file.

const STATUS_NAMES := "res://src/ui/StatusNames.gd"


# ── Helper behavior ───────────────────────────────────────────────────

func test_single_word_status_titlecased() -> void:
	assert_eq(StatusNames.display("poison"), "Poison",
		"poison → 'Poison'")
	assert_eq(StatusNames.display("burn"), "Burn",
		"burn → 'Burn'")
	assert_eq(StatusNames.display("sleep"), "Sleep",
		"sleep → 'Sleep'")


func test_snake_case_status_word_split() -> void:
	# Pin: Godot 4 capitalize handles word boundaries on underscores.
	assert_eq(StatusNames.display("cannot_act"), "Cannot Act",
		"cannot_act → 'Cannot Act'")
	assert_eq(StatusNames.display("chained_actions_disabled"), "Chained Actions Disabled",
		"3-word snake_case rendered correctly")


func test_empty_input_returns_empty() -> void:
	# Defensive: empty input → empty output, no crash.
	assert_eq(StatusNames.display(""), "",
		"empty input → empty output")


func test_override_takes_precedence() -> void:
	# The DISPLAY_OVERRIDES map is the extension point — verify it
	# exists and is checked first. We can't add a real override in
	# a test without mutating the const (illegal), so just confirm
	# the const exists.
	var src: String = FileAccess.get_file_as_string(STATUS_NAMES)
	assert_true(src.contains("const DISPLAY_OVERRIDES := {"),
		"DISPLAY_OVERRIDES extension-point const must exist")
	assert_true(src.contains("if DISPLAY_OVERRIDES.has(status_name):"),
		"display() must check overrides before falling back")
	assert_true(src.contains("return DISPLAY_OVERRIDES[status_name]"),
		"display() must return override when present")


# ── Helper signature ──────────────────────────────────────────────────

func test_helper_is_static() -> void:
	var src: String = FileAccess.get_file_as_string(STATUS_NAMES)
	assert_true(src.contains("static func display(status_name: String) -> String:"),
		"display() must be static for direct call")


# ── Call-site refactors ───────────────────────────────────────────────

func test_status_menu_uses_status_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/StatusMenu.gd")
	assert_true(src.contains("StatusNames.display(status)"),
		"StatusMenu must use StatusNames.display(status)")
	assert_false(src.contains("status.replace(\"_\", \" \").capitalize()"),
		"StatusMenu's pre-fix replace+capitalize pattern must be gone")


func test_autobattle_grid_editor_uses_status_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	assert_true(src.contains("StatusNames.display(status)"),
		"AutobattleGridEditor must use StatusNames.display(status)")
	# The bare `status.capitalize()` line must be gone at that callsite.
	# (Other unrelated capitalize calls in this file may exist; we just
	# check the specific 'Has %s' pattern is now using StatusNames.)
	assert_true(src.contains("\"Has %s\" % StatusNames.display(status)"),
		"AutobattleGridEditor 'Has %s' branch must call StatusNames.display")


func test_battle_manager_inflict_log_uses_status_names() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Tick 354: display MUST reflect the resolved status, not the raw
	# effect (random_debuff picks from a pool; showing "random_debuff"
	# leaks the sentinel). 2026-07-03: log_effect captures the
	# post-pool, PRE-alias name — random_debuff still displays its
	# picked entry, and freeze displays "Frozen" (via
	# DISPLAY_OVERRIDES) rather than the aliased "Stun".
	var count: int = src.count("StatusNames.display(log_effect)")
	assert_eq(count, 2,
		"BattleManager must have exactly 2 StatusNames.display(log_effect) calls (status inflict log + magic inflict log)")
	# Old bare effect.capitalize() pattern must be gone.
	assert_false(src.contains("effect.capitalize()"),
		"BattleManager's effect.capitalize() must be gone")


# ── Cross-pin: tick 211 StatNames pattern preserved ───────────────────

func test_tick_211_stat_names_preserved() -> void:
	# Non-regression: don't accidentally remove the prior StatNames util.
	var src: String = FileAccess.get_file_as_string("res://src/ui/StatNames.gd")
	assert_true(src.contains("static func display_name(stat_name: String) -> String:"),
		"tick 211 StatNames.display_name preserved")
	assert_true(src.contains("static func short_code(stat_name: String) -> String:"),
		"tick 211 StatNames.short_code preserved")
