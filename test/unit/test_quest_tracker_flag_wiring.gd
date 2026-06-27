extends GutTest

## tick 281: QuestTracker.OBJECTIVES flag wiring audit.
##
## Same dead-flag class as ticks 271 (QuestLog W2-W6), 278 (overworld
## boss flags), 280 (wanderer hints). 5 dead refs in QuestTracker
## stayed permanently inactive — the post-boss "Enter the portal" /
## "Find the portal to the next world" objectives never appeared in
## the on-screen tracker even after the player beat the boss.
##
## Dead → real mapping:
##   w1_boss_defeated     → world1_mordaine_defeated
##   w2_dungeon_cleared   → world2_complete
##   w3_dungeon_cleared   → world3_complete
##   w4_dungeon_cleared   → world4_complete
##   w5_dungeon_cleared   → world5_complete
##
## QuestTracker._update_objective does dual-namespace lookup
## (story_flags OR cutscene_flag_X in game_constants), so bare
## `world<N>_complete` resolves via the cutscene_flag_ prefix path.

const QUEST_TRACKER := "res://src/exploration/QuestTracker.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Dead flags removed ─────────────────────────────────────────────

func test_no_dead_w_boss_defeated_in_objectives() -> void:
	var src := _read(QUEST_TRACKER)
	assert_false(src.contains("\"flag\": \"w1_boss_defeated\""),
		"w1_boss_defeated must be removed (no writer in src/)")


func test_no_dead_w_dungeon_cleared_in_objectives() -> void:
	var src := _read(QUEST_TRACKER)
	var survivors: Array[String] = []
	for n in range(2, 6):  # W2-W5
		var dead := "w%d_dungeon_cleared" % n
		if src.contains("\"flag\": \"%s\"" % dead):
			survivors.append(dead)
	assert_eq(survivors.size(), 0,
		"w<N>_dungeon_cleared flags (W2-W5) must be removed (no writers in src/): %s" % str(survivors))


# ── Real flags now present ─────────────────────────────────────────

func test_world_complete_flags_now_in_objectives() -> void:
	var src := _read(QUEST_TRACKER)
	var missing: Array[String] = []
	for n in range(2, 6):
		var real := "world%d_complete" % n
		if not src.contains("\"flag\": \"%s\"" % real):
			missing.append(real)
	assert_eq(missing.size(), 0,
		"each W2-W5 must reference world<N>_complete: %s" % str(missing))


func test_mordaine_defeated_flag_in_objectives() -> void:
	var src := _read(QUEST_TRACKER)
	assert_true(src.contains("\"flag\": \"world1_mordaine_defeated\""),
		"W1 boss objective must reference world1_mordaine_defeated (Mordaine's real flag)")


# ── Cross-pin: real flags have emitters ────────────────────────────

func test_real_flags_have_emitters() -> void:
	# Each replacement flag must be written somewhere as bare or
	# cutscene_flag_-prefixed in src/.
	const REAL_FLAGS := [
		"world1_mordaine_defeated",
		"world2_complete",
		"world3_complete",
		"world4_complete",
		"world5_complete",
	]
	for flag in REAL_FLAGS:
		var found: bool = _grep_emitter(flag)
		assert_true(found,
			"replacement flag '%s' must have a writer in src/ (else still dead): %s" % [flag, flag])


func _grep_emitter(flag: String) -> bool:
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk(dir, "res://src", flag)


func _walk(dir: DirAccess, base: String, flag: String) -> bool:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var sub := DirAccess.open(full)
			if sub != null and _walk(sub, full, flag):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("QuestTracker.gd"):
			var content: String = FileAccess.get_file_as_string(full)
			# Match writer-shapes: cutscene_flag_<flag> in completion
			# map OR bare quoted name in defeat_cutscene_flags arrays.
			if content.contains("\"cutscene_flag_" + flag + "\"") or content.contains("\"" + flag + "\"") and (content.contains("defeat_cutscene_flags") or content.contains("_CUTSCENE_COMPLETION_FLAGS")):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false
