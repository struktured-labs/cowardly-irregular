extends GutTest

## The EventLog had six writers (boss, wipe, area, item, level, cutscene) and none for a finished quest,
## so the Elder could not know the party had just done the thing he asked for.
## QuestSystem now records the turn-in by the title the Quest Log shows; the prompt's recent events carry it.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _qs: Node
var _saved_log: Array = []
var _saved_gold: int = 0
var _saved_quests: Dictionary = {}
var _saved_summary: String = ""
var _saved_pending: String = ""
var _saved_flags: Dictionary = {}


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_saved_log = GameState.event_log.serialize()
	_saved_gold = int(GameState.party_gold)
	_saved_quests = GameState.quests.duplicate(true)
	_saved_summary = str(_qs._last_reward_summary)
	_saved_pending = str(_qs._pending_completion_cutscene)
	_saved_flags = GameState.story_flags.duplicate()
	GameState.event_log.clear()
	GameState.quests.clear()


func after_each() -> void:
	GameState.event_log.restore(_saved_log)
	GameState.party_gold = _saved_gold
	GameState.quests.clear()
	for k in _saved_quests:
		GameState.quests[k] = _saved_quests[k]
	_qs._last_reward_summary = _saved_summary
	_qs._pending_completion_cutscene = _saved_pending
	GameState.story_flags.clear()
	for f in _saved_flags:
		GameState.story_flags[f] = _saved_flags[f]
	SoundManager.stop_music()  # the turn-in stinger must not sound into the next file


## A titled quest with no turn-in cinematic, read from the loaded data.
func _plain_quest() -> String:
	var ids: Array = _qs.get_all_ids()
	ids.sort()
	for qid in ids:
		var q: Dictionary = _qs.get_quest(qid)
		if str(q.get("title", "")).strip_edges() != "" and str(q.get("cutscene_on_complete", "")) == "":
			return str(qid)
	return ""


func _finish(qid: String) -> void:
	GameState.quests[qid] = {"state": "active", "objective_index": 0}
	_qs._complete_quest(qid)


func _quest_events() -> Array:
	return GameState.event_log.by_type(EventLog.TYPE_QUEST_COMPLETE)


func test_finishing_a_quest_is_logged_by_its_title() -> void:
	var qid: String = _plain_quest()
	assert_ne(qid, "", "CONTROL: a titled quest exists")
	if qid == "":
		return
	var title: String = str(_qs.get_quest(qid)["title"])
	GameState.quests[qid] = {"state": "active", "objective_index": 0}
	assert_eq(_quest_events().size(), 0, "CONTROL: a quest merely underway is not logged as finished")
	_qs._complete_quest(qid)
	assert_eq(_qs.get_state(qid), "complete", "CONTROL: the quest did complete")
	var events: Array = _quest_events()
	assert_eq(events.size(), 1, "one finished quest, one event")
	if events.size() != 1:
		return
	assert_eq(str(events[0]["summary"]), "Finished the quest \"%s\"" % title, "it reads by the Quest Log's title")
	assert_false(str(events[0]["summary"]).contains(qid), "and never by the quest's file id")
	assert_eq(str(events[0]["data"].get("quest_id", "")), qid, "the id rides in the data, for code")


func test_the_npc_is_told() -> void:
	var qid: String = _plain_quest()
	if qid == "":
		fail_test("CONTROL: a titled quest exists")
		return
	var line: String = "Finished the quest \"%s\"" % str(_qs.get_quest(qid)["title"])
	var before: String = DP.build_npc_opening("Elder Theron", "an elder", "Harmonia Village", GameState.event_log.recent_varied(8))
	assert_false(before.contains(line), "CONTROL: before the turn-in his prompt does not say so")
	_finish(qid)
	var recent: Array = GameState.event_log.recent_varied(8)
	assert_string_contains(DP.build_npc_opening("Elder Theron", "an elder", "Harmonia Village", recent), line,
		"after it, the opening prompt names the quest")
	assert_string_contains(DP.build_npc_reply("Elder Theron", "an elder", "Harmonia Village", recent, "Hm.", "It is done."), line,
		"and so does the reply prompt")


func test_the_fact_survives_a_save() -> void:
	var qid: String = _plain_quest()
	if qid == "":
		fail_test("CONTROL: a titled quest exists")
		return
	_finish(qid)
	var saved: Variant = JSON.parse_string(JSON.stringify(GameState.event_log.serialize()))
	GameState.event_log.clear()
	assert_eq(_quest_events().size(), 0, "CONTROL: the log was emptied")
	GameState.event_log.restore(saved)
	assert_eq(_quest_events().size(), 1, "the finished quest is still known after a save and load")


func test_a_quest_with_no_title_says_nothing() -> void:
	assert_eq(EventLog.quest_complete_summary("  "), "", "no title, no sentence")
	_qs._record_quest_complete_event("zz_untitled", {"giver": "not a dictionary"})
	assert_eq(_quest_events().size(), 0, "an untitled quest logs nothing an NPC could misread")
	_qs._record_quest_complete_event("zz_titled", {"title": "A Test Errand", "giver": "not a dictionary"})
	assert_eq(_quest_events().size(), 1, "CONTROL: the same call with a title does log")


## cowir-story 24385: the sentence quotes the title, so a title holding a double quote would nest inside it.
func test_no_quest_title_breaks_the_quoted_sentence() -> void:
	var nested: Array = []
	var seen: int = 0
	for qid in _qs.get_all_ids():
		var title: String = str(_qs.get_quest(qid).get("title", ""))
		seen += 1
		if title.contains("\""):
			nested.append("%s: %s" % [qid, title])
	assert_gt(seen, 10, "CONTROL: the quests loaded")
	assert_eq(nested, [], "a quest title with a double quote in it would read as two quotes in an NPC's prompt")
