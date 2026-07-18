extends GutTest

## Playtest 2026-07-12 v3.33.140:
##
## Bug 1 — "weird pauses in between attacks that make things feel odd."
## Root: BattleManager's inter-action + post-action pauses used
## create_timer(0.3 / Engine.time_scale) — DOUBLE-scaled because create_timer
## already applies Engine.time_scale. At 1x (time_scale=0.25) the actual
## wall-clock pause was 4.8s (0.3/0.25=1.2 arg → 1.2/0.25=4.8s wall). The
## author's stated intent (per line 3663 comment history) was 0.3s at 1x.
## 2026-07-17 cinematic pacing: timers now route through _consume_presentation_hold(base) which returns the SAME constant when no hold is requested — the anti-double-scale intent pinned here is unchanged.
## Fix: constant create_timer(0.075) — gives 0.3s wall clock at 1x and
## proportional scaling at higher speeds. Same fix on the 0.1s
## confused-attack chain pause (was 1.6s at 1x).
##
## Bug 2 — Cleric spotlight didn't fire after chapter1. Root: gate at
## GameLoop.gd:1464 included `not _chaining_story_cutscene`, which blocks
## the chapter1 → cleric chain. Player wandered post-chapter1 wondering
## what to do. Fix: drop the chaining guard on the cleric spotlight gate
## so it fires as chapter1's payoff.


func test_battle_manager_pauses_not_divided_by_speed_scale() -> void:
	# The bug pattern was `create_timer(X / speed_scale).timeout`. Double-
	# scaling with time_scale gave a 4.8s wall clock pause at 1x speed.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.find("create_timer(0.3 / speed_scale") > -1,
		"inter-action / post-action pause must not double-scale by speed_scale — was 4.8s wall clock at 1x")
	assert_false(src.find("create_timer(0.1 / speed_scale") > -1,
		"confused-attack pause must not double-scale by speed_scale — was 1.6s wall clock at 1x")
	# Explicit contract: the fixed constants are present.
	assert_true(src.find("create_timer(_consume_presentation_hold(0.075))") > -1,
		"inter/post-action pause must use the constant that gives 0.3s wall clock at 1x battle speed")
	assert_true(src.find("create_timer(_consume_presentation_hold(0.025))") > -1,
		"confused-attack pause must use the constant that gives 0.1s wall clock at 1x battle speed")


func test_cleric_spotlight_chains_directly_after_chapter1() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("world1_spotlight_cleric_ch1")
	assert_gt(i, -1, "cleric spotlight gate must exist")
	# Read the ~200 chars leading up to the return — the guard lives right
	# before the map check.
	var head := src.substr(maxi(0, i - 350), 350)
	assert_true("cutscene_flag_chapter1_complete" in head,
		"gate must key on chapter1 complete")
	assert_true("cutscene_flag_spotlight_unlocked_cleric" in head,
		"gate must key on cleric not yet unlocked")
	assert_false("_chaining_story_cutscene" in head,
		"cleric spotlight must NOT be gated on chaining state — the guard blocked chapter1 → cleric chain, leaving the player with zero next-step cue")
