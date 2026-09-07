extends GutTest

## tick 100 regression: world{N}_complete flags must auto-set after
## the matching last-chapter flag fires, so the next world's prologue
## gate (which reads cutscene_flag_world{N}_complete) is satisfied.
##
## Pre-fix, cutscene_flag_world2_complete (and W3/W4/W5 equivalents)
## were referenced by the W3/W4/W5/W6 prologue gates but NOTHING set
## them. Players couldn't progress past W2 even after finishing
## chapter11. Same gap for each subsequent world's transition.
##
## The W2 → W3 path is critical: tick 92 fixed village music routing,
## tick 93 fixed dungeon music, tick 94-96 wired boss cutscenes, but
## the progression gate itself was completely unwired.

const GAME_LOOP := "res://src/GameLoop.gd"


## Each entry: [last_chapter_flag, world_complete_flag, description]
const AUTO_SETS: Array[Array] = [
	["cutscene_flag_chapter11_complete",       "cutscene_flag_world2_complete", "W2"],
	["cutscene_flag_world3_chapter5_complete", "cutscene_flag_world3_complete", "W3"],
	["cutscene_flag_world4_chapter5_complete", "cutscene_flag_world4_complete", "W4"],
	["cutscene_flag_world5_chapter5_complete", "cutscene_flag_world5_complete", "W5"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _pending_cutscene_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1, "_get_pending_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_each_world_auto_sets_world_complete_after_last_chapter() -> void:
	var body := _pending_cutscene_body()
	for entry in AUTO_SETS:
		var last_chapter: String = entry[0]
		var world_complete: String = entry[1]
		var world_label: String = entry[2]
		var pattern: String = (
			"if flags.get(\"" + last_chapter + "\", false) and not flags.get(\"" + world_complete + "\", false):"
		)
		assert_true(body.contains(pattern),
			"%s must auto-set %s after %s — without this, the next world's prologue gate never fires" % [world_label, world_complete, last_chapter])


func test_each_world_actually_sets_the_flag_in_game_constants() -> void:
	# Pin the actual assignment, not just the check. Tick 220 routes
	# these through the shared _set_cutscene_flag_and_mirror helper so
	# the flag lands in both game_constants AND story_flags. Pin the
	# helper call.
	var body := _pending_cutscene_body()
	for entry in AUTO_SETS:
		var world_complete: String = entry[1]
		var world_label: String = entry[2]
		var pattern: String = "_set_cutscene_flag_and_mirror(\"" + world_complete + "\")"
		assert_true(body.contains(pattern),
			"%s must call _set_cutscene_flag_and_mirror(%s) — the gate alone doesn't do anything" % [world_label, world_complete])


func test_w2_auto_set_immediately_precedes_w3_section() -> void:
	# Ordering: each world's auto-set must come AFTER its last chapter
	# but BEFORE the next world's prologue gate (which reads the
	# auto-set flag). If they're swapped, the next world's prologue
	# gate runs first and fails on a still-false flag.
	var body := _pending_cutscene_body()
	# Tick 220: pin the helper call instead of the bare write.
	var auto_set_idx: int = body.find("_set_cutscene_flag_and_mirror(\"cutscene_flag_world2_complete\")")
	var w3_section_idx: int = body.find("# ===== WORLD 3: STEAMPUNK =====")
	assert_gt(auto_set_idx, -1, "W2 auto-set must exist")
	assert_gt(w3_section_idx, -1, "W3 section marker must exist")
	assert_lt(auto_set_idx, w3_section_idx,
		"W2 world_complete auto-set must come BEFORE the W3 section marker — otherwise the W3 prologue gate at the start of that section reads world2_complete=false")


func test_w1_to_w2_path_unchanged() -> void:
	# Negative pin: the W1 → W2 transition uses mordaine_defeated, not
	# world1_complete. Don't accidentally introduce a world1_complete
	# auto-set (W1 doesn't use that flag).
	var body := _pending_cutscene_body()
	assert_false(body.contains("\"cutscene_flag_world1_complete\""),
		"GameLoop must NOT reference cutscene_flag_world1_complete — W1 uses mordaine_defeated to gate W2 prologue")


func test_each_world_complete_flag_still_in_chapter_titles() -> void:
	# Sanity: ChapterTitles still maps each world{N}_complete to a
	# "Falls" title. Without the auto-sets these titles never display;
	# with them, they show after each world's last chapter.
	var src := _read("res://src/save/ChapterTitles.gd")
	for entry in AUTO_SETS:
		var world_complete: String = entry[1]
		var quoted: String = "\"" + world_complete + "\""
		assert_true(src.contains(quoted),
			"ChapterTitles must still map %s to a chapter title" % world_complete)
