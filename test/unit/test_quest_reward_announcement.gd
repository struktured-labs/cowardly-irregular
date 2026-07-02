extends GutTest

## Quest rewards (gold/EXP/items) were granted in TOTAL silence —
## _grant_rewards mutated state with no announcement or SFX of any
## kind. Completion dialogue now ends with "Received: …" + the
## item_obtain chime. These tests drive _grant_rewards directly and
## inspect the stashed summary line.

var _saved_gold: int


func before_each() -> void:
	_saved_gold = GameState.party_gold
	QuestSystem._last_reward_summary = ""


func after_each() -> void:
	GameState.party_gold = _saved_gold
	QuestSystem._last_reward_summary = ""


func test_gold_reward_builds_summary() -> void:
	QuestSystem._grant_rewards({"rewards": {"gold": 200}})
	assert_eq(QuestSystem._last_reward_summary, "Received: 200 gold.")
	assert_eq(GameState.party_gold, _saved_gold + 200, "gold must actually land too")


func test_empty_rewards_stay_silent() -> void:
	QuestSystem._grant_rewards({"rewards": {}})
	assert_eq(QuestSystem._last_reward_summary, "",
		"no rewards → no announcement line (word_from_capital is zero-reward BY DESIGN)")


func test_item_names_resolve_through_item_system() -> void:
	# unwritten_chord is a real authored quest reward — its display
	# name (not the snake_case id) must appear.
	var display: String = QuestSystem._item_display_name("unwritten_chord")
	assert_false(display.contains("_"), "item ids must render as display names, got: %s" % display)
	assert_true(display.length() > 0)


func test_announce_consumes_the_summary_once() -> void:
	QuestSystem._last_reward_summary = "Received: 5 gold."
	# _announce_rewards plays dialogue (needs an npc node) — use a bare
	# Node2D shell; NPCDialogue attaches to it.
	var shell := Node2D.new()
	add_child_autofree(shell)
	QuestSystem._announce_rewards(shell)
	assert_eq(QuestSystem._last_reward_summary, "",
		"summary must clear on announce so it can't replay on the next quest")
