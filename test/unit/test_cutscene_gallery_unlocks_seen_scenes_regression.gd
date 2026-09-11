extends GutTest

## The gallery marked a scene replayable when ANY of its set_flag flags was true. Measured over
## the corpus (2026-09-11): 21 eligible scenes set no flag at all — every W1 boss intro, all five
## spotlight duels, the PC scenes — so they could never unlock; and `fool_card_marks` is set by
## all five orrery scenes, so W1's orrery unlocked W2-W5's unseen. The Director now writes a seen
## ledger (cutscene_seen_<id>) at the end of a real, unaborted play; the gallery unlocks on that,
## falls back to the completion-flag map for older saves, and counts a set_flag flag only when
## no other scene sets it.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const SEEN := "cutscene_seen_"  # literal, never derived from the code under test

var _d: Node
var _keys: Array[String] = []


func before_each() -> void:
	_d = DirectorScript.new()
	add_child_autofree(_d)


func after_each() -> void:
	for k in _keys:
		GameState.game_constants.erase(k)
	_keys.clear()
	if _d and is_instance_valid(_d):
		_d._active = false


func _flag_on(key: String) -> void:
	GameState.game_constants[key] = true
	_keys.append(key)


func _seen(id: String) -> bool:
	return GameState.game_constants.get(SEEN + id, false) == true


func _scene(id: String) -> Dictionary:
	return {"id": id, "world": 1, "steps": [{"type": "wait", "duration": 0.05}]}


func _run_to_end(id: String, replay: bool = false, abort: bool = false, skip: bool = false) -> void:
	_keys.append(SEEN + id)
	var runner := func() -> void:
		await _d.play_cutscene_from_data(id, _scene(id), replay)
	runner.call()
	await get_tree().process_frame
	if abort:
		_d.abort_current("test")
	if skip:
		_d._trigger_skip()
	var frames := 0
	while _d._active and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_false(_d._active, "control: the scene finished within budget")


func test_the_ledger_key_is_what_the_gallery_reads() -> void:
	assert_eq(DirectorScript.SEEN_KEY_PREFIX, SEEN, "a renamed prefix would silently lock every gallery entry")


func test_a_finished_scene_lands_in_the_seen_ledger() -> void:
	await _run_to_end("t_seen")
	assert_true(_seen("t_seen"), "a real play writes cutscene_seen_<id>")


func test_a_skipped_scene_counts_as_seen() -> void:
	await _run_to_end("t_skipped", false, false, true)
	assert_true(_seen("t_skipped"), "the player chose to pass it — it is theirs to replay")


func test_a_replay_and_an_abort_do_not_write_the_ledger() -> void:
	await _run_to_end("t_replay", true)
	assert_false(_seen("t_replay"), "a gallery replay is not a first viewing")
	await _run_to_end("t_abort", false, true)
	assert_false(_seen("t_abort"), "an aborted scene will replay for real later — not seen yet")


func _entry(gallery: Node, id: String) -> Dictionary:
	for world in gallery._items_by_world:
		for e in gallery._items_by_world[world]:
			if e.get("id", "") == id:
				return e
	return {}


func test_the_gallery_unlocks_a_flagless_scene_once_seen() -> void:
	var gallery := CutsceneGallery.new()
	add_child_autofree(gallery)
	var before := _entry(gallery, "world1_rat_king_intro")
	assert_false(before.is_empty(), "control: the Rat King intro is a gallery entry")
	assert_false(before.get("unlocked", true), "control: unseen, it is locked")
	_flag_on(SEEN + "world1_rat_king_intro")
	gallery._scan_cutscenes()
	assert_true(_entry(gallery, "world1_rat_king_intro").get("unlocked", false),
		"a scene that sets no flag unlocks from the ledger — it could never unlock before")
	assert_false(_entry(gallery, "world1_glacius_intro").get("unlocked", true), "control: a sibling intro not in the ledger stays locked")


func test_a_shared_flag_no_longer_unlocks_unseen_scenes() -> void:
	var gallery := CutsceneGallery.new()
	add_child_autofree(gallery)
	_flag_on("cutscene_flag_fool_card_marks")  # what W1's orrery sets
	gallery._scan_cutscenes()
	for id in ["world2_orrery", "world3_orrery", "world4_orrery", "world5_orrery"]:
		assert_false(_entry(gallery, id).get("unlocked", true), "%s: a flag five scenes share proves nothing about this one" % id)


func test_old_saves_unlock_story_scenes_through_the_completion_flag() -> void:
	var gallery := CutsceneGallery.new()
	add_child_autofree(gallery)
	assert_false(_entry(gallery, "world1_chapter1").get("unlocked", true), "control: locked before")
	_flag_on("cutscene_flag_chapter1_complete")  # GameLoop's completion write, present in every pre-ledger save
	gallery._scan_cutscenes()
	assert_true(_entry(gallery, "world1_chapter1").get("unlocked", false), "a save from before the ledger keeps its unlocked chapters")


func test_is_scene_seen_rules_in_isolation() -> void:
	assert_true(CutsceneGallery.is_scene_seen("x", [], {}, {SEEN + "x": true}), "ledger wins")
	assert_true(CutsceneGallery.is_scene_seen("x", ["f"], {"f": 1}, {"cutscene_flag_f": true}), "an exclusive set_flag flag counts")
	assert_false(CutsceneGallery.is_scene_seen("x", ["f"], {"f": 2}, {"cutscene_flag_f": true}), "a shared set_flag flag does not")
	assert_false(CutsceneGallery.is_scene_seen("x", ["f"], {"f": 1}, {"unrelated": true}), "control: nothing set, locked")
