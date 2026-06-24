extends GutTest

## tick 102 regression: W2/W3/W4 dungeon defeat cutscenes must be
## reachable via _get_pending_story_cutscene. Pre-fix, DragonCave's
## _on_boss_defeated was dead code (no caller), so the
## `defeat_cutscene` field set in tick 95 was a no-op — the defeat
## cutscenes (world2_warden_defeat / world3_tempo_defeat /
## world4_warden_defeat) NEVER played.
##
## The actual play mechanism for defeat cutscenes is the same as W1's
## rat_king_defeat: a gate in _get_pending_story_cutscene that fires
## when (boss-defeat flag set) AND (defeat-cutscene-complete flag
## not set) AND (player in the dungeon scene).

const GAME_LOOP := "res://src/GameLoop.gd"


## Each entry: [defeat_flag, cutscene_id, completion_flag, dungeon_map_id]
const DEFEAT_GATES: Array[Array] = [
	["cutscene_flag_warden_suburban_defeated",
	 "world2_warden_defeat",
	 "cutscene_flag_world2_warden_defeat_complete",
	 "suburban_underground"],
	["cutscene_flag_tempo_steampunk_defeated",
	 "world3_tempo_defeat",
	 "cutscene_flag_world3_tempo_defeat_complete",
	 "steampunk_mechanism"],
	["cutscene_flag_warden_industrial_defeated",
	 "world4_warden_defeat",
	 "cutscene_flag_world4_warden_defeat_complete",
	 "assembly_core"],
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


func test_each_defeat_gate_present() -> void:
	var body := _pending_cutscene_body()
	for entry in DEFEAT_GATES:
		var defeat_flag: String = entry[0]
		var cutscene_id: String = entry[1]
		var completion_flag: String = entry[2]
		var pattern: String = (
			"if flags.get(\"" + defeat_flag + "\", false) "
			+ "and not flags.get(\"" + completion_flag + "\", false):"
		)
		assert_true(body.contains(pattern),
			"defeat-cutscene gate for %s must check defeat_flag + completion_flag — without this guard the cutscene loops every dungeon entry" % cutscene_id)
		assert_true(body.contains("return \"" + cutscene_id + "\""),
			"%s must be a return path" % cutscene_id)


func test_each_gate_scoped_to_dungeon_map() -> void:
	# Pin: each defeat cutscene must fire IN the dungeon (player
	# returns there from boss battle scene). Firing on another map
	# would surface the cutscene at the wrong narrative beat.
	var body := _pending_cutscene_body()
	for entry in DEFEAT_GATES:
		var cutscene_id: String = entry[1]
		var dungeon_map: String = entry[3]
		var idx: int = body.find("return \"" + cutscene_id + "\"")
		assert_gt(idx, -1, "%s return must exist" % cutscene_id)
		var window_start: int = max(0, idx - 200)
		var window: String = body.substr(window_start, idx - window_start)
		assert_true(window.contains("_current_map_id == \"" + dungeon_map + "\""),
			"%s must be gated on _current_map_id == '%s' — dungeon scene player returns to after victory" % [cutscene_id, dungeon_map])


func test_each_cutscene_has_completion_flag_mapping() -> void:
	# Without a completion flag entry, the cutscene plays but no
	# flag is set on finish → cutscene loops forever (the Elder
	# Theron class of bug). Use a regex-flex pattern that tolerates
	# any whitespace between key and value (the const block is
	# column-aligned, easy to mismeasure manually).
	var src := _read(GAME_LOOP)
	for entry in DEFEAT_GATES:
		var cutscene_id: String = entry[1]
		var completion_flag: String = entry[2]
		# Find the key line.
		var key_quote: String = "\"" + cutscene_id + "\":"
		var key_idx: int = src.find(key_quote)
		assert_gt(key_idx, -1,
			"_CUTSCENE_COMPLETION_FLAGS must contain key '%s'" % cutscene_id)
		# Look forward to the end of the line for the value.
		var line_end: int = src.find("\n", key_idx)
		var line: String = src.substr(key_idx, line_end - key_idx) if line_end > -1 else src.substr(key_idx)
		assert_true(line.contains("\"" + completion_flag + "\""),
			"_CUTSCENE_COMPLETION_FLAGS line for %s must map to %s — current line: '%s'" % [cutscene_id, completion_flag, line])


func test_each_cutscene_file_exists_on_disk() -> void:
	for entry in DEFEAT_GATES:
		var cutscene_id: String = entry[1]
		var path: String = "res://data/cutscenes/" + cutscene_id + ".json"
		assert_true(FileAccess.file_exists(path),
			"%s.json must exist on disk — referenced by the new gate" % cutscene_id)


func test_each_defeat_flag_set_by_dungeon_defeat_cutscene_flags() -> void:
	# Sanity: each defeat_flag must be in some dungeon's
	# defeat_cutscene_flags array, otherwise the gate predicate is
	# never satisfied even with the gate wired.
	var dungeons: Array[String] = [
		"res://src/maps/dungeons/SuburbanUnderground.gd",
		"res://src/maps/dungeons/SteampunkMechanism.gd",
		"res://src/maps/dungeons/AssemblyCore.gd",
	]
	for entry in DEFEAT_GATES:
		var defeat_flag: String = entry[0]
		var found_in: String = ""
		for path in dungeons:
			var src := _read(path)
			if src.contains("\"" + defeat_flag + "\""):
				found_in = path
				break
		assert_ne(found_in, "",
			"%s must be set by some dungeon's defeat_cutscene_flags — otherwise the gate predicate is never satisfied" % defeat_flag)


func test_rat_king_defeat_pattern_preserved_as_reference() -> void:
	# Don't regress the W1 pattern that the W2-W4 gates were modeled
	# on — it's the canonical "play defeat cutscene in dungeon"
	# example.
	var body := _pending_cutscene_body()
	assert_true(body.contains("return \"world1_rat_king_defeat\""),
		"W1 rat king defeat gate must still exist — model for the new W2-W4 gates")
