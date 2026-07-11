extends GutTest

## one_chicken_problem step-2 emitter (2026-07-08). QuestChicken + placements
## build the 7-catch puzzle cowir-main temp-gated the quest offer behind.
##
## Pins: 7 canonical hens, per-hen flag persistence, the all-7 → emit path that
## completes the custom step, the restored prereq (quest now offerable), and the
## placement sites across the 3 scenes.

const ChickenScript := preload("res://src/exploration/QuestChicken.gd")
const QUEST := "world1_one_chicken_problem"
const ALL_CAUGHT := "quest_world1_one_chicken_problem_all_chickens"

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()
	for cid in ChickenScript.ALL_CHICKEN_IDS:
		GameState.set_story_flag("chicken_caught_" + cid, false)
	GameState.set_story_flag(ALL_CAUGHT, false)


func after_each() -> void:
	GameState.quests.clear()
	for cid in ChickenScript.ALL_CHICKEN_IDS:
		GameState.set_story_flag("chicken_caught_" + cid, false)
	GameState.set_story_flag(ALL_CAUGHT, false)


func test_seven_canonical_hens() -> void:
	assert_eq(ChickenScript.ALL_CHICKEN_IDS.size(), 7, "the quest is 'actually seven'")
	var uniq := {}
	for cid in ChickenScript.ALL_CHICKEN_IDS:
		uniq[cid] = true
	assert_eq(uniq.size(), 7, "chicken ids must be unique — a dup would under-count the tally")


func test_prereq_restored_quest_offerable() -> void:
	# The temp gate (quest_wiring_chicken_catch_ready) must be gone now that the
	# emitter exists, or the quest stays permanently unofferable.
	var q: Dictionary = _qs.get_quest(QUEST)
	assert_eq(q.get("prereq_flag", "MISSING"), "",
		"prereq_flag must be restored to '' — the step-2 emitter now exists")
	assert_true(_qs.is_offerable(QUEST), "quest must be offerable with the gate lifted")


func test_catching_all_seven_completes_step_two() -> void:
	_qs.accept(QUEST)
	# accept auto-completes step 1 (talk-to-giver) → now on the custom step (idx 1).
	assert_eq(_qs.get_objective_index(QUEST), 1, "on the catch step after accept")
	# Pre-set 6 hens, then catch the 7th via a live node.
	for i in range(6):
		GameState.set_story_flag("chicken_caught_" + ChickenScript.ALL_CHICKEN_IDS[i])
	var hen = ChickenScript.new()
	hen.chicken_id = ChickenScript.ALL_CHICKEN_IDS[6]
	add_child_autofree(hen)
	await get_tree().process_frame
	hen._catch()
	assert_true(GameState.get_story_flag(ALL_CAUGHT), "7th catch emits the all-caught flag")
	assert_eq(_qs.get_objective_index(QUEST), 2, "custom step 2 completes → advance to turn-in step 3")


func test_partial_catch_does_not_emit() -> void:
	_qs.accept(QUEST)
	for i in range(5):
		GameState.set_story_flag("chicken_caught_" + ChickenScript.ALL_CHICKEN_IDS[i])
	var hen = ChickenScript.new()
	hen.chicken_id = ChickenScript.ALL_CHICKEN_IDS[5]  # the 6th
	add_child_autofree(hen)
	await get_tree().process_frame
	hen._catch()
	assert_false(GameState.get_story_flag(ALL_CAUGHT), "6/7 must NOT emit")
	assert_eq(_qs.get_objective_index(QUEST), 1, "still on the catch step at 6/7")


func test_caught_hen_starts_hidden() -> void:
	# A hen whose flag is already set (caught in a prior session) must not render
	# a duplicate — it's home.
	GameState.set_story_flag("chicken_caught_" + ChickenScript.ALL_CHICKEN_IDS[0])
	var hen = ChickenScript.new()
	hen.chicken_id = ChickenScript.ALL_CHICKEN_IDS[0]
	add_child_autofree(hen)
	await get_tree().process_frame
	assert_false(hen.visible, "already-caught hen starts hidden")


func test_placement_sites_across_four_scenes() -> void:
	var harmonia: String = FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	for cid in ["chicken_harmonia_market", "chicken_harmonia_flowerbed",
			"chicken_harmonia_backlot", "chicken_phil_well"]:
		assert_true(harmonia.contains(cid), "Harmonia must place %s" % cid)
	# The guild hen moved home 2026-07-11 — her Harmonia temp spot was inside
	# the Inn wall block (live playtest: uncatchable). Same id, state carries.
	assert_false(harmonia.contains("chicken_guild"), "guild hen no longer temp-placed in Harmonia")
	var guild: String = FileAccess.get_file_as_string("res://src/maps/interiors/ScripturaGuildInterior.gd")
	assert_true(guild.contains("chicken_guild"), "Scriptura Guild must place the guild hen")
	var overworld: String = FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	assert_true(overworld.contains("chicken_cave_approach"), "overworld must place the cave-approach hen")
	var inn: String = FileAccess.get_file_as_string("res://src/maps/interiors/InnInterior.gd")
	assert_true(inn.contains("chicken_inn_kitchen"), "Inn must place the kitchen hen")
