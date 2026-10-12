extends GutTest

## Six authored village-introduction scenes reached no player: nothing dispatched them, so ~90 lines were unreachable and their Theater rows could never unlock.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _intros() -> Dictionary:
	return load("res://src/GameLoop.gd").get_script_constant_map()["_VILLAGE_INTROS"]


func _completion_flags() -> Dictionary:
	return load("res://src/GameLoop.gd").get_script_constant_map()["_CUTSCENE_COMPLETION_FLAGS"]


## The flag the scene's own set_flag step writes, which is what must stop it re-firing.
func _authored_flag(cid: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cid))
	if not (parsed is Dictionary):
		return ""
	for step in (parsed as Dictionary).get("steps", []):
		if step is Dictionary and str((step as Dictionary).get("type", "")) == "set_flag":
			return "cutscene_flag_%s" % str((step as Dictionary).get("flag", ""))
	return ""


func test_every_wired_intro_names_a_scene_on_disk() -> void:
	var intros: Dictionary = _intros()
	assert_gt(intros.size(), 5, "CONTROL: the village intro table must be populated, saw %d" % intros.size())
	var missing: Array = []
	for map_id in intros:
		if not FileAccess.file_exists("res://data/cutscenes/%s.json" % str(intros[map_id])):
			missing.append("%s -> %s" % [map_id, intros[map_id]])
	assert_eq(missing, [], "a village intro names a scene that is not on disk: %s" % [missing])


func test_each_intro_can_stop_itself_re_firing() -> void:
	## The gate reads cutscene_flag_<id>_complete; the scene writes its own set_flag. If those two
	## disagree the scene replays on every entry to that village — the Elder Theron loop.
	var mismatched: Array = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		var gate_flag: String = "cutscene_flag_%s_complete" % cid
		var authored: String = _authored_flag(cid)
		assert_ne(authored, "", "CONTROL: %s must author a set_flag step" % cid)
		if authored != gate_flag:
			mismatched.append("%s writes %s, the gate reads %s" % [cid, authored, gate_flag])
	assert_eq(mismatched, [], "an intro that cannot set its own gate flag replays forever: %s" % [mismatched])


func test_each_intro_is_in_the_completion_flag_map() -> void:
	var absent: Array = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		if not _completion_flags().has(cid):
			absent.append(cid)
	assert_eq(absent, [], "a scene the engine fires must carry a completion flag or it loops: %s" % [absent])


func test_an_intro_cannot_pre_empt_a_story_beat() -> void:
	## Ordering is the whole safety property: every story gate returns before the intro loop, so
	## an intro can never take an entry a chapter beat wanted.
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	assert_true(code.contains("func _get_pending_story_cutscene"), "CONTROL: GameLoop code must survive comment-stripping")
	var fn_at: int = code.find("func _get_pending_story_cutscene")
	var intro_at: int = code.find("for vid in _VILLAGE_INTROS", fn_at)
	var prologue_at: int = code.find("\"world1_prologue\"", fn_at)
	var chapter_at: int = code.find("\"world1_chapter1\"", fn_at)
	assert_gt(intro_at, -1, "the intro loop must live inside the pending-cutscene gate")
	assert_gt(intro_at, prologue_at, "the prologue gate must be reached before any village intro")
	assert_gt(intro_at, chapter_at, "the chapter-1 gate must be reached before any village intro")


func test_no_two_villages_claim_the_same_scene() -> void:
	var seen: Dictionary = {}
	var dupes: Array = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		if seen.has(cid):
			dupes.append("%s is claimed by %s and %s" % [cid, seen[cid], map_id])
		seen[cid] = map_id
	assert_eq(dupes, [], "two maps firing one scene means the second can never play it: %s" % [dupes])


func test_an_intro_never_takes_a_chained_entry() -> void:
	## A story beat finishing in a village must not hand the entry straight to flavour.
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	var loop_at: int = code.find("for vid in _VILLAGE_INTROS")
	assert_gt(loop_at, -1, "CONTROL: the intro loop must exist")
	var before: String = code.substr(max(0, loop_at - 220), 220)
	assert_true(before.contains("not _chaining_story_cutscene"),
		"the intro loop must refuse to fire as a chain target, or an intro stacks on a story beat")


func test_a_new_game_cannot_land_on_a_wired_village() -> void:
	## New Game sets the map id before the opening cutscenes; if that id were ever a village key,
	## an intro would stack onto the opening and onto the web smoke's fresh-game path.
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	var at: int = code.find("func _on_title_new_game")
	assert_gt(at, -1, "CONTROL: the new-game entry point must exist")
	var body: String = code.substr(at, 2000)
	var set_at: int = body.find("_set_current_map_id(")
	assert_gt(set_at, -1, "CONTROL: New Game must set a map id")
	var landed: String = body.substr(set_at, 60)
	for vid in _intros():
		assert_false(landed.contains("\"%s\"" % str(vid)),
			"New Game lands on %s, which is wired to an intro — it would stack on the opening" % [vid])


## The village arms its OWN bed on entry (village_harmonia, village_maple_heights...). An intro that
## plays a generic world bed scores the player's first impression with the wrong music and only hands
## the village its theme back when the scene ends.
func test_an_intro_does_not_score_itself_with_the_generic_bed() -> void:
	var wrong: Array = []
	var checked := 0
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cid))
		assert_true(parsed is Dictionary, "CONTROL: %s must parse" % cid)
		var data: Dictionary = parsed
		checked += 1
		var beds: Array = []
		for step in data.get("steps", []):
			if step is Dictionary and str((step as Dictionary).get("type", "")) == "play_music":
				beds.append(str((step as Dictionary).get("track", "")))
		var village: String = str(map_id).trim_suffix("_village")
		for bed in beds:
			if bed != "village_%s" % village:
				wrong.append("%s plays %s" % [cid, bed])
		if beds.is_empty() and not bool(data.get("keep_music", false)):
			wrong.append("%s names no bed and does not keep_music, so it plays to dead air" % cid)
	assert_gt(checked, 5, "CONTROL: every wired intro must be read, saw %d" % checked)
	assert_eq(wrong, [], "an intro must keep the village's bed or name that village's own theme: %s" % [wrong])
