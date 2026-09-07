extends GutTest

## tick 103 regression: W5 RootProcess defeat cutscene must be
## reachable via _get_pending_story_cutscene. Completes the tick 102
## defeat-cutscene fix series for W5. NullChamber (W6) excluded:
## world6_curator_defeat.json doesn't exist on disk — only
## world6_calibrant_defeat which is the final-boss closer, not the
## NullChamber dungeon Curator.

const GAME_LOOP := "res://src/GameLoop.gd"
const ROOT_PROCESS := "res://src/maps/dungeons/RootProcess.gd"


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


func test_root_process_declares_defeat_cutscene_flags() -> void:
	var src := _read(ROOT_PROCESS)
	assert_true(src.contains("defeat_cutscene_flags = [\"cutscene_flag_arbiter_futuristic_defeated\"]"),
		"RootProcess must set defeat_cutscene_flags so the W5 arbiter defeat flag fires on victory")


func test_w5_arbiter_defeat_gate_present() -> void:
	var body := _pending_cutscene_body()
	var pattern: String = (
		"if flags.get(\"cutscene_flag_arbiter_futuristic_defeated\", false) "
		+ "and not flags.get(\"cutscene_flag_world5_arbiter_defeat_complete\", false):"
	)
	assert_true(body.contains(pattern),
		"_get_pending_story_cutscene must check W5 arbiter defeat flag + completion guard")
	assert_true(body.contains("return \"world5_arbiter_defeat\""),
		"_get_pending_story_cutscene must return world5_arbiter_defeat")


func test_w5_gate_scoped_to_root_process_map() -> void:
	var body := _pending_cutscene_body()
	var idx: int = body.find("return \"world5_arbiter_defeat\"")
	assert_gt(idx, -1, "W5 arbiter defeat return must exist")
	var window_start: int = max(0, idx - 200)
	var window: String = body.substr(window_start, idx - window_start)
	assert_true(window.contains("_current_map_id == \"root_process\""),
		"W5 arbiter defeat must be gated on root_process — dungeon player returns to after victory")


func test_w5_arbiter_defeat_in_completion_flag_map() -> void:
	var src := _read(GAME_LOOP)
	var key_quote: String = "\"world5_arbiter_defeat\":"
	var key_idx: int = src.find(key_quote)
	assert_gt(key_idx, -1,
		"_CUTSCENE_COMPLETION_FLAGS must contain key 'world5_arbiter_defeat'")
	var line_end: int = src.find("\n", key_idx)
	var line: String = src.substr(key_idx, line_end - key_idx) if line_end > -1 else src.substr(key_idx)
	assert_true(line.contains("\"cutscene_flag_world5_arbiter_defeat_complete\""),
		"world5_arbiter_defeat must map to cutscene_flag_world5_arbiter_defeat_complete")


func test_world5_arbiter_defeat_file_exists() -> void:
	assert_true(FileAccess.file_exists("res://data/cutscenes/world5_arbiter_defeat.json"),
		"world5_arbiter_defeat.json must exist on disk")


func test_w6_null_chamber_curator_defeat_not_authored() -> void:
	# Documenting why W6 is excluded from this fix. If a future commit
	# authors world6_curator_defeat.json AND wires NullChamber's
	# defeat_cutscene_flags, this negative pin should be removed and
	# a positive gate added.
	assert_false(FileAccess.file_exists("res://data/cutscenes/world6_curator_defeat.json"),
		"If world6_curator_defeat.json now exists, wire NullChamber's defeat_cutscene_flags + add a gate, then remove this guard")


func test_full_defeat_cutscene_series_complete_for_w1_w5() -> void:
	# Coverage assertion: every authored dungeon-boss defeat cutscene
	# from W1 through W5 has a return path. This closes the series
	# started in tick 102.
	var body := _pending_cutscene_body()
	for cutscene_id in [
		"world1_rat_king_defeat",
		"world2_warden_defeat",
		"world3_tempo_defeat",
		"world4_warden_defeat",
		"world5_arbiter_defeat",
	]:
		assert_true(body.contains("return \"" + cutscene_id + "\""),
			"%s must have a return path — completing the W1-W5 defeat-cutscene series" % cutscene_id)
