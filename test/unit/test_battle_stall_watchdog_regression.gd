extends GutTest

## Live playtest 2026-07-01: battle froze PERMANENTLY at
## "Round 1 - EXECUTE: Bard" (screenshot 20-20-19). Root causes this
## suite pins:
##
## 1. _execute_advance's empty-actions branch was a bare `return` —
##    but the caller returns after it ("advance handles its own
##    continuation"), so nothing ever called _execute_next_action
##    again. Battle dead, input alive (user: "if I jam enough buttons
##    might be able to fix.. nope it was stuck").
## 2. No recovery mechanism existed for ANY death of the execution
##    coroutine (a mid-coroutine script error stalls identically and
##    silently). BattleManager now runs a WALL-CLOCK watchdog
##    (Time.get_ticks_msec — immune to Engine.time_scale up to the
##    32x battle speed the user was jamming) that force-kicks
##    _execute_next_action after a threshold of zero progress.
##
## Same session, same cave: "fighting goblin, he suddenly became
## small and facing wrong way near end of battle" — goblin manifest
## mapped hit=6-8 / dead=8, the late-ATK crouch-twist follow-through
## frames (artist source only had Idle+ATK tags). Every hit near the
## end of a fight displayed a hunched, turned goblin. Remapped.

const BM_PATH := "res://src/battle/BattleManager.gd"
const MANIFEST_PATH := "res://data/sprite_manifest.json"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _fn_body(src: String, fn_name: String) -> String:
	var idx: int = src.find("func %s" % fn_name)
	assert_gt(idx, -1, "%s must exist in BattleManager" % fn_name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx)


func test_empty_advance_keeps_execution_chain_alive() -> void:
	var body := _fn_body(_read(BM_PATH), "_execute_advance")
	var empty_idx: int = body.find("actions.is_empty()")
	assert_gt(empty_idx, -1, "_execute_advance must guard empty actions")
	# The continuation call must live inside the empty-actions branch —
	# a bare return here is the exact freeze the user hit. 500 chars
	# bounds the search to this branch (next code is the trash-talk
	# block, well past it).
	var window: String = body.substr(empty_idx, 500)
	assert_gt(window.find("_execute_next_action()"), -1,
		"empty-advance branch must call _execute_next_action (bare return froze the battle at EXECUTE: Bard)")


func test_watchdog_exists_and_uses_wall_clock() -> void:
	var src := _read(BM_PATH)
	assert_true(src.contains("_WD_STALL_MS"),
		"stall watchdog threshold const must exist")
	var body := _fn_body(src, "_process(")
	assert_true(body.contains("Time.get_ticks_msec"),
		"watchdog must measure WALL CLOCK — Engine.time_scale-based deltas are exactly what the 32x battle speed distorts")
	assert_true(body.contains("_execute_next_action()"),
		"watchdog recovery must force-kick the execution chain")
	assert_true(body.contains("push_error"),
		"recovery must be loud — a silent auto-recover hides the underlying coroutine death")


func test_watchdog_scoped_to_execution_states() -> void:
	var body := _fn_body(_read(BM_PATH), "_process(")
	assert_true(body.contains("EXECUTION_PHASE") and body.contains("PROCESSING_ACTION"),
		"watchdog must gate on execution states")
	# Outside those states it must reset, or a long player think-time
	# in selection would trip a false recovery.
	assert_true(body.contains("_wd_last_progress_ms = 0"),
		"watchdog must reset outside execution states (selection-phase think time is unbounded)")


func test_watchdog_armed_only_inside_real_battles() -> void:
	# First shipped unarmed, the watchdog fired mid-test-suite: battle
	# tests leave current_state in execution states without start_battle,
	# and 10 wall-seconds later recovery end_battle'd empty parties while
	# the RuleComposer tests sat in long Ollama awaits — green-isolation/
	# red-full-suite contamination. Arm strictly via battle lifecycle.
	var src := _read(BM_PATH)
	assert_true(_fn_body(src, "_process(").contains("if not _wd_armed"),
		"_process must early-out when unarmed")
	assert_true(_fn_body(src, "start_battle").contains("_wd_armed = true"),
		"start_battle must arm the watchdog")
	assert_true(_fn_body(src, "end_battle").contains("_wd_armed = false"),
		"end_battle must disarm the watchdog")


func test_watchdog_widens_threshold_at_slow_speeds() -> void:
	# At 0.25x battle speed legit cinematics run 4x longer in real
	# time — the threshold must scale by 1/time_scale so slow-mo
	# group attacks don't get interrupted by a false recovery.
	var body := _fn_body(_read(BM_PATH), "_process(")
	assert_true(body.contains("Engine.time_scale"),
		"watchdog threshold must account for slow battle speeds")


func test_progress_bumps_at_all_continuation_sites() -> void:
	var src := _read(BM_PATH)
	assert_true(_fn_body(src, "_execute_next_action").contains("_wd_bump()"),
		"_execute_next_action must mark progress")
	assert_true(_fn_body(src, "_execute_advance").contains("_wd_bump()"),
		"advance sub-action loop must mark progress (multi-action chains are the longest legit gaps)")
	assert_true(_fn_body(src, "_execute_group_action").contains("_wd_bump()"),
		"group attacks must mark progress after their cinematics")


func test_goblin_hit_dead_avoid_crouch_twist_frames() -> void:
	var manifest: Dictionary = JSON.parse_string(_read(MANIFEST_PATH))
	assert_not_null(manifest, "sprite_manifest.json must parse")
	var goblin: Dictionary = manifest["monster_sheets"]["goblin"]
	var anims: Dictionary = goblin["animations"]
	# Frames 6-8 are the attack follow-through: deep crouch + body
	# twist. Reused as hit/dead they read as "suddenly became small
	# and facing wrong way" (user report). hit/dead must stay clear
	# of them until the artist authors dedicated frames.
	for anim_name in ["hit", "dead"]:
		var a: Dictionary = anims[anim_name]
		assert_lt(int(a["end"]), 6,
			"goblin %s must not reuse late-ATK crouch-twist frames 6-8" % anim_name)
	# attack keeps its full authored range — only the reuse was wrong.
	assert_eq(int(anims["attack"]["start"]), 3)
	assert_eq(int(anims["attack"]["end"]), 8)
