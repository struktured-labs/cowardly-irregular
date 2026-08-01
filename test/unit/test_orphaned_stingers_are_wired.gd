extends GutTest

## Three composed stingers shipped with zero call sites (2026-07-31).
##
## stinger_item_found, stinger_quest_complete and stinger_save_point sat in
## music_manifest.json with real audio (5.0s / 5.0s / 7.2s) and were named
## nowhere in src/ or data/cutscenes/. The mechanism was never in doubt —
## stinger_level_up and stinger_boss_defeated are called by name and work — so
## these were simply never hooked up. Same defect class as the dragon-cave
## themes: composed, shipped, unreachable.
##
## Each hook is DELIBERATELY gated, and the gate is the interesting part:
##   quest_complete  skipped when the quest chains into a cutscene, which sets
##                   its own music and would cut the stinger off mid-phrase
##   item_found      equipment only — a fanfare per potion is what stops a
##                   fanfare meaning anything (7 equipment chests, 20 item)
##   save_point      FIRST attunement of a crystal only, not every save; the
##                   ordering against activate_crystal is what makes it once
##
## See test_stinger_resume_over_area_music.gd for the prerequisite fix: all
## three fire during EXPLORATION, where a stinger used to kill the music dead.

const SM_PATH := "res://src/audio/SoundManager.gd"
const SAVEPOINT := "res://src/exploration/SavePoint.gd"
const CHEST := "res://src/exploration/TreasureChest.gd"

var _saved_quests: Dictionary = {}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)


func after_each() -> void:
	GameState.quests = _saved_quests


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "expected %s to be readable" % p)
	return t


## A quest id that does NOT chain into a cutscene, derived from the data rather
## than named here — a hand-picked id silently stops testing the ungated path
## the day someone adds cutscene_on_complete to it.
func _quest_without_completion_cutscene() -> String:
	var dir := DirAccess.open("res://data/quests")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var raw: String = FileAccess.get_file_as_string("res://data/quests/" + f)
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary and str(parsed.get("cutscene_on_complete", "")) == "":
				var qid: String = str(parsed.get("id", ""))
				if qid != "":
					return qid
		f = dir.get_next()
	return ""


func test_quest_completion_plays_the_stinger() -> void:
	## Behavioural: drive the real _complete_quest and read what the music
	## player ended up on. A source pin here would only prove the line is spelled.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var qid := _quest_without_completion_cutscene()
	assert_ne(qid, "", "setup: expected at least one quest with no completion cutscene")
	if qid == "":
		return
	var prev: Dictionary = sm.capture_music_state()

	GameState.quests[qid] = {"state": "active", "objective_index": 0}
	QuestSystem._complete_quest(qid)
	await get_tree().create_timer(0.3).timeout

	assert_eq(str(sm._current_music), "stinger_quest_complete",
		"completing \"%s\" must play the turn-in stinger; music is on \"%s\"" % [qid, sm._current_music])

	sm.restore_music_state(prev)


func test_a_quest_that_chains_a_cutscene_stays_silent() -> void:
	## The gate. Without it the stinger starts and the chained cutscene's own
	## play_music cuts it off a second later — worse than no stinger at all.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()
	sm.stop_music()

	var qid := "world1_fools_spread"  # carries cutscene_on_complete
	var q: Dictionary = QuestSystem.get_quest(qid)
	assert_ne(str(q.get("cutscene_on_complete", "")), "",
		"premise: %s must still chain a cutscene, else this test proves nothing" % qid)
	GameState.quests[qid] = {"state": "active", "objective_index": 0}
	QuestSystem._complete_quest(qid)
	await get_tree().create_timer(0.3).timeout

	assert_ne(str(sm._current_music), "stinger_quest_complete",
		"a quest that chains into a cutscene must NOT also fire the stinger")

	sm.restore_music_state(prev)


func test_save_point_stinger_is_gated_on_FIRST_attunement() -> void:
	## The ordering is the correctness: reading is_crystal_activated AFTER
	## activate_crystal would always be true and the stinger would never fire;
	## dropping the gate entirely fires it on every save, several times an hour.
	var src := _read(SAVEPOINT)
	var i_read := src.find("is_crystal_activated")
	var i_write := src.find("activate_crystal(_current_map_id())")
	var i_play := src.find('play_music("stinger_save_point")')
	assert_true(i_read > -1, "SavePoint must check is_crystal_activated to detect a first attunement")
	assert_true(i_play > -1, "SavePoint must play stinger_save_point")
	assert_lt(i_read, i_write,
		"the is_crystal_activated check must come BEFORE activate_crystal — after it, the flag is always true and the stinger can never fire")
	assert_lt(i_write, i_play,
		"the stinger should follow attunement so it marks the unlock")


func test_equipment_chests_fanfare_and_consumables_do_not() -> void:
	var src := _read(CHEST)
	assert_true(src.find('play_music("stinger_item_found")') > -1,
		"TreasureChest must play stinger_item_found for real gear")
	var i_equip := src.find('"equipment":')
	var i_play := src.find('play_music("stinger_item_found")')
	assert_true(i_equip > -1 and i_equip < i_play,
		"the fanfare must sit under the \"equipment\" arm, not fire for every chest")
	assert_eq(src.count('play_music("stinger_item_found")'), 1,
		"exactly one call site — a second would double-fire on the open+contents pair, which is the bug this slot already had once with chest_open")


func test_the_equipment_arm_is_reachable_at_all() -> void:
	## The gate is only worth having if content uses it. Derived by scanning the
	## placements: if every chest in the game were "item"/"gold", the arm above
	## would be correct, tested, and permanently dead.
	var count := 0
	var dirs: Array = ["res://src/maps/villages", "res://src/exploration", "res://src/maps/dungeons"]
	for d in dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".gd"):
				var s: String = FileAccess.get_file_as_string(d + "/" + f)
				count += s.count('contents_type = "equipment"')
			f = dir.get_next()
	assert_gt(count, 0,
		"no chest anywhere sets contents_type = \"equipment\", so stinger_item_found can never play — the hook would be as unreachable as before")


func test_positive_control_all_three_stingers_still_have_audio() -> void:
	## Guards the other end: a hook pointing at a manifest entry with no file
	## silently plays nothing, and every assertion above would still pass.
	var raw: String = FileAccess.get_file_as_string("res://data/music_manifest.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "music manifest must parse")
	var tracks: Dictionary = parsed.get("tracks", parsed)
	for id in ["stinger_item_found", "stinger_quest_complete", "stinger_save_point"]:
		assert_true(tracks.has(id), "%s must still be in the manifest" % id)
		var file: String = str(tracks.get(id, {}).get("file", ""))
		assert_ne(file, "", "%s must point at a real file" % id)
		assert_true(FileAccess.file_exists("res://" + file) or FileAccess.file_exists(file),
			"%s points at %s, which is not on disk" % [id, file])
