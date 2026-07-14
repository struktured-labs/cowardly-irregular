extends GutTest

## tick 107 regression: the W6 endgame closer must chain through
## world6_calibrant_defeat and world6_ending after chapter3. Pre-fix,
## the W6 chain stopped at chapter3 — both endgame cutscenes existed
## on disk (world6_calibrant_defeat.json + world6_ending.json) but
## no code path triggered them. Players who reached the W6 climax
## ("The Question") had no resolution.
##
## The Calibrant "battle" is elided as narrative beats matching the
## W2 Masterite auto-sets pattern (tick 101), since no Calibrant
## arena/dungeon exists in the codebase.

const GAME_LOOP := "res://src/GameLoop.gd"


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


func test_calibrant_defeat_gate_present() -> void:
	var body := _pending_cutscene_body()
	var pattern: String = (
		"if flags.get(\"cutscene_flag_world6_chapter3_complete\", false) "
		+ "and not flags.get(\"cutscene_flag_world6_calibrant_defeat_complete\", false):"
	)
	assert_true(body.contains(pattern),
		"calibrant defeat gate must check chapter3_complete + not calibrant_defeat_complete")
	assert_true(body.contains("return \"world6_calibrant_defeat\""),
		"_get_pending_story_cutscene must return world6_calibrant_defeat")


func test_ending_gate_chains_on_calibrant_defeat() -> void:
	var body := _pending_cutscene_body()
	var pattern: String = (
		"if flags.get(\"cutscene_flag_world6_calibrant_defeat_complete\", false) "
		+ "and not flags.get(\"cutscene_flag_world6_ending_complete\", false):"
	)
	assert_true(body.contains(pattern),
		"ending gate must chain on calibrant_defeat_complete + not ending_complete")
	assert_true(body.contains("return \"world6_ending\""),
		"_get_pending_story_cutscene must return world6_ending")


func test_both_endgame_gates_scoped_to_vertex_village() -> void:
	# Pin: both endgame cutscenes fire in vertex_village (the only
	# W6 reachable map). Wider scoping would have them fire at
	# arbitrary points in earlier worlds if the player somehow returns.
	var body := _pending_cutscene_body()
	for cutscene_id in ["world6_calibrant_defeat", "world6_ending"]:
		var idx: int = body.find("return \"" + cutscene_id + "\"")
		assert_gt(idx, -1, "%s return must exist" % cutscene_id)
		var window_start: int = max(0, idx - 200)
		var window: String = body.substr(window_start, idx - window_start)
		assert_true(window.contains("_current_map_id == \"vertex_village\""),
			"%s must be gated on vertex_village" % cutscene_id)


func test_calibrant_defeat_gate_precedes_ending_gate() -> void:
	# Critical ordering: calibrant_defeat must come BEFORE ending in
	# source so chapter3 → defeat → ending sequences correctly. If
	# swapped, ending's predicate (calibrant_defeat_complete=false)
	# never satisfies on a fresh path.
	var body := _pending_cutscene_body()
	var defeat_idx: int = body.find("return \"world6_calibrant_defeat\"")
	var ending_idx: int = body.find("return \"world6_ending\"")
	assert_gt(defeat_idx, -1, "calibrant_defeat return must exist")
	assert_gt(ending_idx, -1, "ending return must exist")
	assert_lt(defeat_idx, ending_idx,
		"calibrant_defeat gate must precede ending gate — sequence is chapter3 → defeat → ending")


func test_both_completion_flag_mappings_present() -> void:
	var src := _read(GAME_LOOP)
	for entry in [
		["world6_calibrant_defeat", "cutscene_flag_world6_calibrant_defeat_complete"],
		["world6_ending",           "cutscene_flag_world6_ending_complete"],
	]:
		var cutscene_id: String = entry[0]
		var completion_flag: String = entry[1]
		var key_quote: String = "\"" + cutscene_id + "\":"
		var key_idx: int = src.find(key_quote)
		assert_gt(key_idx, -1, "_CUTSCENE_COMPLETION_FLAGS must contain %s" % cutscene_id)
		var line_end: int = src.find("\n", key_idx)
		var line: String = src.substr(key_idx, line_end - key_idx) if line_end > -1 else src.substr(key_idx)
		assert_true(line.contains("\"" + completion_flag + "\""),
			"%s must map to %s" % [cutscene_id, completion_flag])


func test_both_cutscene_files_exist_on_disk() -> void:
	for path in [
		"res://data/cutscenes/world6_calibrant_defeat.json",
		"res://data/cutscenes/world6_ending.json",
	]:
		assert_true(FileAccess.file_exists(path),
			"%s must exist on disk" % path)


func test_w6_chain_now_traversable_to_ending() -> void:
	# Coverage: full W6 chain from prologue through ending has return
	# paths. Closes the W6 progression gap.
	var body := _pending_cutscene_body()
	for cutscene_id in [
		"world6_prologue",
		"world6_chapter1",
		"world6_chapter2",
		"world6_chapter3",
		"world6_calibrant_defeat",
		"world6_ending",
	]:
		assert_true(body.contains("return \"" + cutscene_id + "\""),
			"%s must have a return path — full W6 chain from prologue to ending" % cutscene_id)
