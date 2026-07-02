extends GutTest

## QuestSystem v1 (2026-07-01 huddle: msgs 2107/2109/2111/2124/2126).
## Pins: loader integrity over the W1 batch, state machine transitions,
## talk/custom/fetch objective semantics, reward grants incl. job
## variants, GameState.quests persistence round-trip, npc_id slugs.

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()


func after_each() -> void:
	GameState.quests.clear()
	for f in ["quest_world1_fools_spread_reading_received",
			"quest_world1_fools_spread_paper_obtained",
			"quest_world1_fools_spread_complete",
			"cutscene_flag_rat_king_defeated",
			"quest_world1_one_chicken_problem_all_chickens"]:
		GameState.set_story_flag(f, false)


func test_w1_batch_loads_all_six() -> void:
	assert_not_null(_qs, "QuestSystem autoload must exist")
	var ids: Array = _qs.get_all_ids()
	for expected in ["world1_fools_spread", "world1_one_chicken_problem",
			"world1_untested_edge", "world1_chapter_three",
			"world1_word_from_capital", "world1_thirty_seven"]:
		assert_has(ids, expected, "W1 batch quest %s must load" % expected)


func test_quest_data_integrity() -> void:
	# Every objective type is one the engine supports; every reward item
	# resolves; giver npc_ids are non-empty. Same guard shape as the
	# chest/monster integrity tests.
	var items_json = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var supported := ["talk", "custom", "fetch", "kill_n"]
	for qid in _qs.get_all_ids():
		var q: Dictionary = _qs.get_quest(qid)
		assert_ne(q.get("giver", {}).get("npc_id", ""), "", "%s giver needs npc_id" % qid)
		for obj in q.get("objectives", []):
			assert_has(supported, obj.get("type", ""), "%s has unsupported objective type %s" % [qid, obj.get("type", "")])
		for entry in q.get("rewards", {}).get("items", []):
			var iid: String = entry.get("item_id", "")
			assert_true(items_json.has(iid), "%s reward %s must exist in items.json" % [qid, iid])


func test_offerable_respects_prereq_flag() -> void:
	# untested_edge is prereq-gated on rat_king_defeated.
	assert_false(_qs.is_offerable("world1_untested_edge"), "gated before flag")
	GameState.set_story_flag("cutscene_flag_rat_king_defeated")
	assert_true(_qs.is_offerable("world1_untested_edge"), "offerable after flag")
	# one_chicken has no prereq — always offerable when unstarted.
	assert_true(_qs.is_offerable("world1_one_chicken_problem"))


func test_accept_completes_talk_to_giver_step_one() -> void:
	_qs.accept("world1_one_chicken_problem")
	assert_eq(_qs.get_state("world1_one_chicken_problem"), "active")
	# Step 1 targets the giver, so accepting advances to step 2 (custom).
	assert_eq(_qs.get_objective_index("world1_one_chicken_problem"), 1)


func test_custom_flag_and_turn_in_complete_quest_with_rewards() -> void:
	_qs.accept("world1_one_chicken_problem")
	var gold_before: int = GameState.get_gold()
	# External emitter sets the chicken flag → notify.
	GameState.set_story_flag("quest_world1_one_chicken_problem_all_chickens")
	_qs.notify_flag("quest_world1_one_chicken_problem_all_chickens")
	assert_eq(_qs.get_objective_index("world1_one_chicken_problem"), 2)
	# Final talk-to-giver completes + grants (0 gold on this quest — flag mirror is the check).
	var done: String = _qs.notify_talk("farmer_aldwick")
	assert_eq(done, "world1_one_chicken_problem", "final talk returns the completed quest")
	assert_eq(_qs.get_state("world1_one_chicken_problem"), "complete")
	assert_true(GameState.get_story_flag("quest_world1_one_chicken_problem_complete"),
		"completion mirror flag set")
	assert_eq(GameState.get_gold(), gold_before, "chicken quest awards no gold")


func test_talk_objective_requires_flag_gate() -> void:
	GameState.set_story_flag("cutscene_flag_rat_king_defeated")
	_qs.accept("world1_fools_spread")
	# Step 2 targets Phil but requires reading_received — accept() already
	# completed step 1 (talk-to-giver), which SET that flag, so Phil works.
	assert_eq(_qs.get_objective_index("world1_fools_spread"), 1)
	assert_true(GameState.get_story_flag("quest_world1_fools_spread_reading_received"))
	var done: String = _qs.notify_talk("phil_the_lost")
	assert_eq(done, "", "step 2 is not final — no completion escalation")
	assert_eq(_qs.get_objective_index("world1_fools_spread"), 2)


func test_quests_dict_round_trips_through_save() -> void:
	_qs.accept("world1_one_chicken_problem")
	var data: Dictionary = GameState._create_save_data()
	assert_true(data.has("quests"))
	GameState.quests.clear()
	GameState._apply_save_data(data)
	assert_eq(_qs.get_state("world1_one_chicken_problem"), "active")
	assert_eq(_qs.get_objective_index("world1_one_chicken_problem"), 1)


func test_npc_id_slug_derivation() -> void:
	var NPCScript = load("res://src/exploration/OverworldNPC.gd")
	var npc = NPCScript.new()
	npc.npc_name = "Phil the Lost"
	assert_eq(npc.get_npc_id(), "phil_the_lost")
	npc.npc_name = "Rowan"
	npc.npc_id = "rowan_harmonia"
	assert_eq(npc.get_npc_id(), "rowan_harmonia", "explicit id overrides slug")
	npc.free()


func test_interact_routing_priority_pinned_in_source() -> void:
	# The huddle-settled chain (quest > dynamic > scripted) lives in
	# OverworldNPC._start_dialogue — pin the ordering so a refactor can't
	# silently flip it back to dynamic-first (msg 2124 collision).
	var src: String = FileAccess.get_file_as_string("res://src/exploration/OverworldNPC.gd")
	var quest_gate: int = src.find("has_giver_business")
	var dynamic_gate: int = src.find("_llm_conversation_available()")
	assert_gt(quest_gate, 0)
	assert_gt(dynamic_gate, 0)
	assert_lt(quest_gate, dynamic_gate,
		"quest-business gate must precede the dynamic-LLM gate in _start_dialogue")
