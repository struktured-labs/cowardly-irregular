extends GutTest

## cowir-main 21783 / cowir-sfx 21784: ONE completion sound per turn-in. QuestSystem._complete_quest plays the music
## stinger stinger_quest_complete (unless a cutscene follows), then emits quest_state_changed(id, "complete"), and
## QuestTracker answered that same signal with the SFX quest_complete — two different completion jingles at once.
## test_a_quest_accept_chimes_once only walks signal LISTENERS, and QuestSystem plays its stinger itself, so it could not see this.
## The stinger wins when it is what is actually playing; the SFX marks a turn-in that chains into a cutscene.

const CHAINED := "world1_fools_spread"  # carries cutscene_on_complete

var _tracker: QuestTracker
var _music: Dictionary
var _quests: Dictionary
var _flags: Dictionary
var _gold: int
var _pending: String


func before_each() -> void:
	_music = SoundManager.capture_music_state()
	_quests = GameState.quests.duplicate(true)
	_flags = GameState.story_flags.duplicate(true)
	_gold = GameState.party_gold
	_pending = str(QuestSystem._pending_completion_cutscene)
	SoundManager.stop_music()
	_tracker = QuestTracker.new()
	add_child_autofree(_tracker)
	_tracker.setup(_tracker)
	await wait_frames(1)


func after_each() -> void:
	QuestSystem._pending_completion_cutscene = _pending
	GameState.quests = _quests
	GameState.story_flags = _flags
	GameState.party_gold = _gold
	SoundManager.restore_music_state(_music)


func _plain_quest() -> String:
	for qid in QuestSystem.get_all_ids():
		if str(QuestSystem.get_quest(str(qid)).get("cutscene_on_complete", "")) == "":
			return str(qid)
	return ""


func _turn_in(qid: String) -> String:
	## Drives the real completion and returns the file the UI player was handed (""= nothing played there).
	SoundManager._ui_player.stop()
	SoundManager._ui_player.stream = null
	if "_sfx_cooldowns" in SoundManager:
		SoundManager._sfx_cooldowns.clear()
	GameState.quests[qid] = {"state": "active", "objective_index": 0}
	QuestSystem._complete_quest(qid)
	var s: AudioStream = SoundManager._ui_player.stream
	return "" if s == null else str(s.resource_path).get_file().get_basename()


func test_a_plain_turn_in_plays_the_stinger_and_nothing_else() -> void:
	var qid := _plain_quest()
	assert_ne(qid, "", "PREMISE: a quest with no completion cutscene exists")
	if qid == "":
		return
	var ui := _turn_in(qid)
	assert_eq(SoundManager.playing_track_stem(), "stinger_quest_complete",
		"CONTROL: a plain turn-in must still play the music stinger (playing: '%s')" % SoundManager.playing_track_stem())
	assert_false(ui.begins_with("quest_complete"),
		"turning in \"%s\" played the music stinger AND the SFX '%s' on top of it: two completion jingles at once" % [qid, ui])


func test_a_turn_in_that_chains_a_cutscene_still_sounds() -> void:
	assert_ne(str(QuestSystem.get_quest(CHAINED).get("cutscene_on_complete", "")), "",
		"PREMISE: %s must still chain a cutscene, else this arm proves nothing" % CHAINED)
	var ui := _turn_in(CHAINED)
	assert_ne(SoundManager.playing_track_stem(), "stinger_quest_complete", "PREMISE: a chained turn-in skips the stinger")
	assert_true(ui.begins_with("quest_complete"),
		"a turn-in with no stinger must still mark the moment with the SFX quest_complete; the UI player got '%s'" % ui)
