extends GutTest

## tick 77 regression: every area transition's fade-out must run
## under an InputLockManager lock. _start_exploration sets
## state=EXPLORATION and pops all locks, so without this guard the
## player can press D-pad and start walking BEFORE the fade-out
## reveals the new scene. Worst case: stepping into a wall they
## couldn't see, or re-triggering an exit they spawned next to.

const GAME_LOOP := "res://src/GameLoop.gd"
const LOCK_NAME := "area_transition_fade"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _on_area_transition_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_area_transition")
	assert_gt(idx, -1, "_on_area_transition must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_every_arm_pushes_lock_before_fade_out() -> void:
	# Pin: each of the 5 transition arms must push the lock after
	# _start_exploration and before its specific fade-out. If a
	# new arm is added without this, the player gets pre-fade
	# movement again.
	var body := _on_area_transition_body()
	var fade_out_funcs: Array[String] = [
		"_area_cave_transition_out",
		"_area_village_transition_out",
		"_area_interior_transition_out",
		"_area_overworld_transition_out",
		"_area_fade_from_black",
	]
	for fn in fade_out_funcs:
		# The push_lock line must appear before each fade-out call.
		var fade_idx: int = body.find("await " + fn + "()")
		assert_gt(fade_idx, -1, "fade-out '%s' must be awaited in a match arm" % fn)
		# Look back ~120 chars for the push_lock call in the same arm.
		var window_start: int = max(0, fade_idx - 120)
		var window: String = body.substr(window_start, fade_idx - window_start)
		assert_true(window.contains("InputLockManager.push_lock(\"" + LOCK_NAME + "\")"),
			"arm awaiting %s must push the '%s' lock before the fade-out — otherwise player can walk during the reveal" % [fn, LOCK_NAME])


func test_lock_pushed_after_start_exploration_not_before() -> void:
	# Critical ordering: _start_exploration calls
	# InputLockManager.pop_all(), so pushing the lock BEFORE
	# _start_exploration silently clobbers it. The fix is to push
	# AFTER. Pin by checking every push immediately follows a
	# `_start_exploration()` await.
	var body := _on_area_transition_body()
	# Find every push_lock occurrence and verify the preceding ~80 chars
	# contain '_start_exploration'.
	var pos: int = 0
	var pushes_found: int = 0
	while true:
		var p: int = body.find("push_lock(\"" + LOCK_NAME + "\")", pos)
		if p == -1:
			break
		pushes_found += 1
		var window_start: int = max(0, p - 80)
		var window: String = body.substr(window_start, p - window_start)
		assert_true(window.contains("_start_exploration"),
			"push_lock at offset %d must follow _start_exploration — otherwise pop_all in _start_exploration clobbers it" % p)
		pos = p + 1
	assert_gt(pushes_found, 0, "at least one push_lock call must exist")


func test_pop_lock_after_match_releases_for_all_arms() -> void:
	# A single pop_lock after the match block covers all 5 arms.
	# Pin its presence so a future refactor doesn't leave a stale lock.
	var body := _on_area_transition_body()
	assert_true(body.contains("InputLockManager.pop_lock(\"" + LOCK_NAME + "\")"),
		"_on_area_transition must pop the '%s' lock after the match — otherwise the lock leaks past the transition" % LOCK_NAME)
	# Ordering: pop must come AFTER the match block. The simplest check
	# is that pop_lock appears after the LAST fade-out reference.
	var pop_idx: int = body.find("pop_lock(\"" + LOCK_NAME + "\")")
	var last_fade_idx: int = body.rfind("_area_fade_from_black")
	assert_gt(pop_idx, -1, "pop_lock must be present")
	assert_gt(last_fade_idx, -1, "last fade-out reference must be present")
	assert_gt(pop_idx, last_fade_idx,
		"pop_lock must appear AFTER the match block's last fade-out — otherwise the lock leaks while a transition fade is still running")


func test_lock_name_constant_consistent() -> void:
	# Sanity: the literal string is reused 6 times (5 pushes + 1 pop).
	# A typo silently leaks the lock or pops something else. Count
	# occurrences to catch the rename-one-forget-rest class.
	var body := _on_area_transition_body()
	var quoted: String = "\"" + LOCK_NAME + "\""
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = body.find(quoted, pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 6,
		"'%s' literal must appear exactly 6 times in _on_area_transition body (5 pushes + 1 pop) — a typo silently leaks the lock" % LOCK_NAME)
