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
