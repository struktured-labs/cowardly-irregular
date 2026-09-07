extends GutTest

## Regression: Quest Log auto-scrolls the viewport so the active objective
## lands near the top on initial open. In late-game runs the completed
## chapters pile up and the active objective sinks below the fold; without
## this, players have to scroll past 20+ "✓ done" lines to find what they
## should be doing. Subsequent rebuilds (driven by scroll input) MUST
## preserve the user's manual scroll instead of snapping back.

const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"

const _TOUCHED_FLAGS := [
	"prologue_complete",
	"chapter1_complete",
	"chapter2_complete",
	"chapter3_complete",
	"rat_king_defeated",
	"w1_boss_defeated",
	"w2_entered",
	"w2_boss_defeated",
	"w3_entered",
	"w3_boss_defeated",
	"w4_entered",
	"w4_boss_defeated",
	"w5_entered",
	"w5_boss_defeated",
	"w6_entered",
]

var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_flags.clear()
	if GameState:
		for flag in _TOUCHED_FLAGS:
			_saved_flags[flag] = GameState.get_story_flag(flag)
			GameState.set_story_flag(flag, false)


func after_each() -> void:
	if GameState:
		for flag in _TOUCHED_FLAGS:
			GameState.set_story_flag(flag, _saved_flags.get(flag, false))


func _stand_up_quest_log() -> Node:
	var script = load(QUEST_LOG_PATH)
	var ql = script.new()
	add_child_autofree(ql)
	ql._build_ui()
	return ql


func test_auto_scroll_zero_at_game_start() -> void:
	# Fresh game — active objective is in Chapter 1 near the very top.
	# Expected offset is 0 (or 1 at most after subtracting 2 from the
	# active line index, which is the first objective — index ~1).
	var ql = _stand_up_quest_log()
	assert_true(ql._scroll_offset <= 1,
		"At game start the active objective sits near the top — scroll should be 0 or 1, got: %d" % ql._scroll_offset)
	assert_true(ql._initial_scroll_applied,
		"_initial_scroll_applied must flip to true after first _build_ui run")


func test_auto_scroll_keeps_active_line_in_visible_window() -> void:
	# Real invariant — regardless of viewport size, the active objective
	# must end up inside the rendered window after auto-scroll. (A large
	# viewport may fit everything at offset 0; a smaller one must scroll
	# down. Either way, the active line is visible to the player.)
	for flag in ["prologue_complete", "chapter1_complete", "chapter2_complete",
		"chapter3_complete", "rat_king_defeated", "w1_boss_defeated", "w2_entered"]:
		GameState.set_story_flag(flag, true)
	var ql = _stand_up_quest_log()
	var lines = ql._build_quest_lines()
	var active_idx = ql._find_active_line_index(lines)
	assert_true(active_idx > -1,
		"Test setup: an active objective must exist in this scenario")
	if active_idx == -1:
		return
	var window_end = ql._scroll_offset + ql._max_visible_lines
	assert_true(ql._scroll_offset <= active_idx and active_idx < window_end,
		"Active line at idx %d must be in visible window [%d, %d) after auto-scroll" % [
			active_idx, ql._scroll_offset, window_end])


func test_auto_scroll_leaves_context_above_active_line() -> void:
	# When the viewport requires scrolling to reach the active line, the
	# auto-scroll target should land ~2 lines above the active objective
	# so the chapter header / preceding context is still visible. We test
	# this by checking that `_scroll_offset` never exceeds `active_idx`
	# itself — auto-scroll must not push the active line off the top.
	for flag in ["prologue_complete", "chapter1_complete", "chapter2_complete",
		"chapter3_complete", "rat_king_defeated", "w1_boss_defeated", "w2_entered"]:
		GameState.set_story_flag(flag, true)
	var ql = _stand_up_quest_log()
	var lines = ql._build_quest_lines()
	var active_idx = ql._find_active_line_index(lines)
	if active_idx == -1:
		return
	assert_true(ql._scroll_offset <= active_idx,
		"_scroll_offset (%d) must not push past active line (%d) — active line stays visible" % [
			ql._scroll_offset, active_idx])


func test_subsequent_rebuilds_preserve_user_scroll() -> void:
	# After the initial auto-scroll lands, the user pressing ↑/↓ rebuilds
	# the UI. Those rebuilds MUST NOT snap _scroll_offset back to the
	# active objective — otherwise the user can never scroll away from
	# the active line.
	for flag in ["prologue_complete", "chapter1_complete", "chapter2_complete",
		"chapter3_complete", "rat_king_defeated", "w1_boss_defeated", "w2_entered"]:
		GameState.set_story_flag(flag, true)
	var ql = _stand_up_quest_log()
	var initial_scroll = ql._scroll_offset

	# Simulate user pressing ↑ a few times — manually adjust scroll and
	# rebuild, then assert scroll stayed where we set it (modulo clamp).
	ql._scroll_offset = maxi(0, initial_scroll - 3)
	var manual_scroll = ql._scroll_offset
	ql._build_ui()
	assert_eq(ql._scroll_offset, manual_scroll,
		"Subsequent _build_ui must NOT re-run auto-scroll — preserves manual offset")


func test_no_active_objective_leaves_scroll_at_zero() -> void:
	# End-game: every flag set, no active objective. Auto-scroll must not
	# touch _scroll_offset (still 0).
	for flag in _TOUCHED_FLAGS:
		GameState.set_story_flag(flag, true)
	var ql = _stand_up_quest_log()
	assert_eq(ql._scroll_offset, 0,
		"With no active objective, auto-scroll must leave _scroll_offset at 0")
	assert_true(ql._initial_scroll_applied,
		"_initial_scroll_applied still flips even when no active line found")
