extends GutTest

## world1_thirty_seven step 3 is a fetch with consume:true, and step 4 is the
## trade with guild_scholar_scriptura. notify_talk treated every conversation
## as the handoff: talking to a plaza citizen while the book was in the bag
## deleted it, advanced the log to "Trade the book", and the returns bin
## (chest_scriptura_overdue_book_bin) will not give another. The scholar
## still paid out later, so the trade line was a lie about an item already gone.

const QUEST_ID := "world1_thirty_seven"
const BOOK := "overdue_guild_book"
const FAVOR := "quest_world1_thirty_seven_favor_asked"
const DONE := "quest_world1_thirty_seven_complete"
const FETCH_INDEX := 2
const BYSTANDER := "scriptura_citizen_1"
const SCHOLAR := "guild_scholar_scriptura"
const FIXTURE := "zz_fetch_not_a_delivery"


class FakeGameLoop extends Node:
	var party: Array = []
	var equipment_pool: Dictionary = {"weapons": [], "armors": [], "accessories": []}


var _fake: FakeGameLoop = null
var _holder: Combatant = null


func before_each() -> void:
	GameState.quests.clear()
	GameState.set_story_flag(FAVOR, false)
	GameState.set_story_flag(DONE, false)
	GameState.set_story_flag("zz_turnin_not_ready", false)
	QuestSystem._last_reward_summary = ""
	QuestSystem._pending_completion_cutscene = ""
	_fake = FakeGameLoop.new()
	_fake.name = "GameLoop"
	_holder = Combatant.new()
	_holder.combatant_name = "Holder"
	# Stay under the level threshold so a real turn-in cannot learn spells on the shared JobSystem.
	_holder.job_level = 98
	_fake.party = [_holder]
	get_tree().root.add_child(_fake)


func after_each() -> void:
	GameState.quests.clear()
	GameState.set_story_flag(FAVOR, false)
	GameState.set_story_flag(DONE, false)
	GameState.set_story_flag("zz_turnin_not_ready", false)
	QuestSystem._last_reward_summary = ""
	QuestSystem._pending_completion_cutscene = ""
	QuestSystem._quests.erase(FIXTURE)
	if is_instance_valid(_holder):
		_holder.free()
	_holder = null
	if is_instance_valid(_fake):
		get_tree().root.remove_child(_fake)
		_fake.free()
	_fake = null


func _arm_book() -> void:
	GameState.set_story_flag(FAVOR)
	GameState.quests[QUEST_ID] = {"state": "active", "objective_index": FETCH_INDEX}
	_holder.add_item(BOOK, 1)


func test_bystander_talk_does_not_consume_the_book() -> void:
	_arm_book()
	var done: String = QuestSystem.notify_talk(BYSTANDER)
	assert_eq(done, "", "a plaza citizen is not the turn-in")
	assert_eq(_holder.get_item_count(BOOK), 1,
		"the overdue book must stay in the bag until the scholar — the returns bin is a one-shot chest")
	assert_eq(QuestSystem.get_state(QUEST_ID), "active")
	assert_eq(QuestSystem.get_objective_index(QUEST_ID), FETCH_INDEX,
		"the log must keep showing the fetch, not 'Trade the book', while the book is still held")
	assert_eq(_holder.get_item_count("guild_record"), 0, "a bystander must not pay the quest reward")


func test_scholar_turn_in_consumes_the_book_and_pays_once() -> void:
	_arm_book()
	var done: String = QuestSystem.notify_talk(SCHOLAR)
	assert_eq(done, QUEST_ID, "the scholar is the trade")
	assert_eq(_holder.get_item_count(BOOK), 0, "the book leaves inventory at the turn-in")
	assert_eq(QuestSystem.get_state(QUEST_ID), "complete")
	assert_eq(_holder.get_item_count("guild_record"), 1, "guild record is the turn-in reward")
	assert_eq(_holder.get_item_count("research_pass"), 1, "research pass is the turn-in reward")


func test_talking_to_the_scholar_again_does_not_pay_again() -> void:
	_arm_book()
	assert_eq(QuestSystem.notify_talk(SCHOLAR), QUEST_ID)
	var again: String = QuestSystem.notify_talk(SCHOLAR)
	assert_eq(again, "", "a finished quest must not turn in a second time")
	assert_eq(_holder.get_item_count("guild_record"), 1, "re-talking must not grant the record again")
	assert_eq(_holder.get_item_count("research_pass"), 1, "re-talking must not grant the pass again")


func test_the_book_stays_when_the_turn_in_itself_is_still_blocked() -> void:
	# Same shape as a delivery, but the talk step's own flag is not set yet.
	QuestSystem._quests[FIXTURE] = {
		"id": FIXTURE,
		"objectives": [
			{"type": "fetch", "item_id": "herb", "count": 1, "consume": true},
			{"type": "talk", "target_npc": SCHOLAR, "required_flag": "zz_turnin_not_ready"},
		],
	}
	GameState.quests[FIXTURE] = {"state": "active", "objective_index": 0}
	GameState.set_story_flag("zz_turnin_not_ready", false)
	_holder.add_item("herb", 1)
	assert_eq(QuestSystem.notify_talk(SCHOLAR), "")
	assert_eq(_holder.get_item_count("herb"), 1,
		"the item must not be traded when the turn-in talk cannot complete")
	assert_eq(QuestSystem.get_objective_index(FIXTURE), 0)
	GameState.set_story_flag("zz_turnin_not_ready", false)


func test_a_fetch_that_is_not_a_delivery_still_completes_on_any_talk() -> void:
	# Next step is custom, not a talk, so there is no recipient to wait for.
	QuestSystem._quests[FIXTURE] = {
		"id": FIXTURE,
		"objectives": [
			{"type": "fetch", "item_id": "herb", "count": 1, "consume": true},
			{"type": "custom", "required_flag": "zz_fetch_later"},
		],
	}
	GameState.quests[FIXTURE] = {"state": "active", "objective_index": 0}
	_holder.add_item("herb", 1)
	assert_eq(QuestSystem.notify_talk(BYSTANDER), "", "the custom step is not the final step")
	assert_eq(_holder.get_item_count("herb"), 0, "a non-delivery fetch still consumes when it completes")
	assert_eq(QuestSystem.get_objective_index(FIXTURE), 1)
