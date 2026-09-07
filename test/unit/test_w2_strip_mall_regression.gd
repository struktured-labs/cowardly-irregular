extends GutTest

## W2 wiring PR-B (2026-07-08): the rearranging strip mall.
## Pins: the TALK_TALLY_EMITTERS mechanism (all-3-owner interviews →
## owners_interviewed), the scene build + cast ids, GameLoop dispatch,
## and configuration_pending's full progression to turn-in.

const MallScript := preload("res://src/maps/villages/MapleStripMall.gd")

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()
	var owners := ["candle_shop_owner_w2", "armory_owner_w2", "yogurt_owner_w2"]
	for n in owners:
		GameState.set_story_flag("talked_quest_world2_configuration_pending_owners_interviewed_%s" % n, false)
	GameState.set_story_flag("quest_world2_configuration_pending_owners_interviewed", false)


func after_each() -> void:
	before_each()


func test_mall_scene_builds_with_cast() -> void:
	var mall = MallScript.new()
	add_child_autofree(mall)
	await get_tree().process_frame
	assert_eq(mall._get_area_id(), "maple_heights_strip_mall")
	assert_true(mall.spawn_points.has("entrance"))
	var src: String = FileAccess.get_file_as_string("res://src/maps/villages/MapleStripMall.gd")
	for id in ["surplus_teen_w2", "candle_shop_owner_w2", "armory_owner_w2",
			"yogurt_owner_w2", "madame_orrery_w2"]:
		assert_true(src.contains(id), "mall must place %s" % id)


func test_gameloop_dispatch_and_door() -> void:
	var g: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(g.contains("\"maple_heights_strip_mall\":"), "GameLoop dispatches the mall")
	var mh: String = FileAccess.get_file_as_string("res://src/maps/villages/MapleHeightsVillage.gd")
	assert_true(mh.contains("strip_mall_return"), "Maple Heights registers the return spawn")
	assert_true(mh.contains("maple_heights_strip_mall"), "Maple Heights has the mall road")
	assert_true(mh.contains("retired_surveyor_w2"), "surveyor placed on Birch Court")


func test_owner_tally_requires_all_three() -> void:
	_qs.accept("world2_configuration_pending")
	assert_eq(_qs.get_objective_index("world2_configuration_pending"), 1, "on interviews after accept")
	_qs.notify_talk("candle_shop_owner_w2")
	_qs.notify_talk("armory_owner_w2")
	assert_false(GameState.get_story_flag("quest_world2_configuration_pending_owners_interviewed"),
		"2 of 3 must NOT fire the group flag")
	assert_eq(_qs.get_objective_index("world2_configuration_pending"), 1)
	_qs.notify_talk("yogurt_owner_w2")
	assert_true(GameState.get_story_flag("quest_world2_configuration_pending_owners_interviewed"),
		"third interview completes the set")
	assert_eq(_qs.get_objective_index("world2_configuration_pending"), 2, "advanced to the surveyor step")


func test_tally_order_independent_and_persistent() -> void:
	_qs.accept("world2_configuration_pending")
	_qs.notify_talk("yogurt_owner_w2")
	assert_true(GameState.get_story_flag(
		"talked_quest_world2_configuration_pending_owners_interviewed_yogurt_owner_w2"),
		"per-NPC progress persists as a story flag (save-safe)")
	_qs.notify_talk("candle_shop_owner_w2")
	_qs.notify_talk("armory_owner_w2")
	assert_eq(_qs.get_objective_index("world2_configuration_pending"), 2, "any order works")


func test_tally_inert_when_quest_inactive() -> void:
	_qs.notify_talk("candle_shop_owner_w2")
	assert_false(GameState.get_story_flag(
		"talked_quest_world2_configuration_pending_owners_interviewed_candle_shop_owner_w2"),
		"no tally progress before the quest is active")


func test_configuration_pending_full_chain_to_turn_in() -> void:
	_qs.accept("world2_configuration_pending")
	for n in ["candle_shop_owner_w2", "armory_owner_w2", "yogurt_owner_w2"]:
		_qs.notify_talk(n)
	_qs.notify_talk("retired_surveyor_w2")
	assert_eq(_qs.get_objective_index("world2_configuration_pending"), 3, "surveyor talk → final step")
	var done: String = _qs.notify_talk("surplus_teen_w2")
	assert_eq(done, "world2_configuration_pending", "turn-in at the teen completes")
	assert_eq(_qs.get_state("world2_configuration_pending"), "complete")
