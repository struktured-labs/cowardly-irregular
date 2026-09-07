extends GutTest

## world1_untested_edge rewards `returned_sword` — a real +140-attack weapon in
## equipment.json. QuestSystem granted it with add_item alone, so it landed in the
## consumable inventory and NEVER in GameLoop.equipment_pool, which is the only
## thing the Equipment menu reads. The player finished the quest and could not
## equip the sword. Drops, chests and shops were all fixed for this exact class
## ("leaving equipment as unusable lore items" — BattleManager); quest rewards
## were missed, and an items.json stub silenced the one warning that pointed at it.

const QUEST_FILE := "res://data/quests/world1_untested_edge.json"

## A Node named GameLoop carrying only what _grant_rewards touches. GameLoop is a
## scene node, not an autoload, so no real one exists under GUT.
class FakeGameLoop extends Node:
	var equipment_pool: Dictionary = {"weapons": [], "armors": [], "accessories": []}
	var party: Array = []


var _fake: FakeGameLoop = null
var _leader: Combatant = null


func before_each() -> void:
	QuestSystem._last_reward_summary = ""
	_fake = FakeGameLoop.new()
	_fake.name = "GameLoop"
	_leader = Combatant.new()
	_fake.party = [_leader]
	get_tree().root.add_child(_fake)


func after_each() -> void:
	QuestSystem._last_reward_summary = ""
	if is_instance_valid(_leader):
		_leader.free()
	_leader = null
	if is_instance_valid(_fake):
		get_tree().root.remove_child(_fake)
		_fake.free()
	_fake = null


## FLOOR. Every assertion below is vacuous if the harness never reaches the block.
func test_harness_actually_reaches_the_item_grant() -> void:
	QuestSystem._grant_rewards({"rewards": {"items": [{"item_id": "potion", "count": 2}]}})
	assert_eq(_leader.get_item_count("potion"), 2,
		"a consumable reward must reach the leader's inventory — if this fails the fake "
		+ "GameLoop is not being found and the routing assertions below prove nothing")


## The corpus must still author the reward this guard is about.
func test_a_quest_really_does_reward_an_equipment_id() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEST_FILE))
	assert_true(parsed is Dictionary, "world1_untested_edge must parse")
	var ids: Array = []
	for entry in ((parsed as Dictionary).get("rewards", {}) as Dictionary).get("items", []):
		ids.append(str((entry as Dictionary).get("item_id", "")))
	assert_true(ids.has("returned_sword"),
		"this guard exists because a quest rewards a weapon; if the reward was renamed, "
		+ "re-point the guard rather than deleting it. got: %s" % [ids])
	assert_false(EquipmentSystem.get_weapon("returned_sword").is_empty(),
		"returned_sword must still be a real weapon in equipment.json")


## THE REGRESSION. A granted weapon must reach the pool the Equipment menu reads.
func test_equipment_reward_lands_in_the_equipment_pool() -> void:
	QuestSystem._grant_rewards({"rewards": {"items": [{"item_id": "returned_sword", "count": 1}]}})
	assert_true(_fake.equipment_pool["weapons"].has("returned_sword"),
		"a quest-granted weapon must land in GameLoop.equipment_pool.weapons — the Equipment "
		+ "menu builds its list from that pool ONLY, so a weapon that misses it can never be "
		+ "equipped no matter how many the player owns")


## ...and must not ALSO sit in the consumable inventory as a dead lore entry.
func test_equipment_reward_does_not_become_a_dead_inventory_item() -> void:
	QuestSystem._grant_rewards({"rewards": {"items": [{"item_id": "returned_sword", "count": 1}]}})
	assert_eq(_leader.get_item_count("returned_sword"), 0,
		"equipment must not double-file into the consumable inventory — items.json carries a "
		+ "stub for this id, so the entry renders as an unusable item with empty effects")


## Consumables must be untouched by the routing — the fix must not swallow potions.
func test_consumable_rewards_still_go_to_inventory() -> void:
	QuestSystem._grant_rewards({"rewards": {"items": [{"item_id": "potion", "count": 3}]}})
	assert_eq(_leader.get_item_count("potion"), 3, "consumables keep the inventory path")
	assert_false(_fake.equipment_pool["weapons"].has("potion"),
		"a consumable must never be routed into an equipment slot")


## The announcement must still name the reward — routing changed the destination, not the text.
func test_equipment_reward_is_still_announced() -> void:
	QuestSystem._grant_rewards({"rewards": {"items": [{"item_id": "returned_sword", "count": 1}]}})
	assert_true(QuestSystem._last_reward_summary.contains("Returned Sword"),
		"the player must still be told what they got, got: %s" % [QuestSystem._last_reward_summary])
