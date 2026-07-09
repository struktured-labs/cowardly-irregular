extends GutTest

## W2 wiring PR-A (2026-07-08): Maple Heights quest hub.
## Pins: the quest cast placements + ids, the wildflower emitter (magic-gated),
## the annex_found dialogue emitters, and acceptable_variance's progression
## through the PR-A-owned steps (1-3). Step 4 (Form 44-Omega front desk) and
## the Annex itself land in PR-C.

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()
	for f in ["quest_world2_acceptable_variance_flower_examined",
			"quest_world2_relocated_annex_found",
			"cutscene_flag_world2_chapter1_complete",
			"quest_world2_relocated_complete"]:
		GameState.set_story_flag(f, false)


func after_each() -> void:
	before_each()


func test_maple_heights_places_the_w2_cast() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/maps/villages/MapleHeightsVillage.gd")
	for id in ["mail_carrier_w2", "gerald_w2", "mrs_pemberton_w2",
			"basement_developer_w2", "casper_kid"]:
		assert_true(src.contains(id), "Maple Heights must place %s" % id)
	assert_true(src.contains("WildflowerPatch"), "the wildflower emitter is placed")
	assert_true(src.contains("quest_world2_relocated_complete"),
		"Casper's placement is gated on the rescue")


func test_variance_progresses_through_pr_a_steps() -> void:
	assert_true(_qs.is_offerable("world2_acceptable_variance"), "no prereq — offerable")
	_qs.accept("world2_acceptable_variance")
	# accept auto-completes step 1 (talk-to-giver gerald) → flower step
	assert_eq(_qs.get_objective_index("world2_acceptable_variance"), 1)
	# flower emitter (simulating a magic-capable examine)
	GameState.set_story_flag("quest_world2_acceptable_variance_flower_examined")
	_qs.notify_flag("quest_world2_acceptable_variance_flower_examined")
	assert_eq(_qs.get_objective_index("world2_acceptable_variance"), 2)
	# step 3: talk to Pemberton
	_qs.notify_talk("mrs_pemberton_w2")
	assert_eq(_qs.get_objective_index("world2_acceptable_variance"), 3,
		"Pemberton talk advances to the 44-Omega step (PR-C's front desk)")


func test_annex_found_fires_from_tyler_or_carrier() -> void:
	GameState.set_story_flag("cutscene_flag_world2_chapter1_complete")
	_qs.accept("world2_relocated")
	assert_eq(_qs.get_objective_index("world2_relocated"), 1, "on annex_found after accept")
	# Tyler's intel fires the emitter
	_qs.notify_talk("tyler_on_bike")
	assert_true(GameState.get_story_flag("quest_world2_relocated_annex_found"))
	assert_eq(_qs.get_objective_index("world2_relocated"), 2, "advanced to kids_freed")


func test_annex_found_inert_before_accept() -> void:
	_qs.notify_talk("tyler_on_bike")
	assert_false(GameState.get_story_flag("quest_world2_relocated_annex_found"),
		"Tyler's emitter must not fire when the quest isn't active")


func test_wildflower_magic_gate_shape() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/WildflowerPatch.gd")
	assert_true(src.contains("MAGIC_JOBS"), "flower gates on magic-capable jobs")
	assert_true(src.contains("magic_surge"), "successful read uses the magic_surge cue")
	assert_true(src.contains("quest_world2_acceptable_variance_flower_examined"),
		"flower emits the variance step-2 flag")
