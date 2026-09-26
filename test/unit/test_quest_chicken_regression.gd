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


func _catch_toast(hen: Node) -> Label:
	for c in hen.get_children():
		if c is Label:
			return c
	return null


## The catch line is a child of the hen. The poof used to set visible=false on the hen at 0.35s, which hid "(n / 7)" before the line's own fade (it starts at 0.5s).
func test_catch_line_stays_up_after_the_hen_poofs() -> void:
	_qs.accept(QUEST)
	var hen = ChickenScript.new()
	hen.chicken_id = ChickenScript.ALL_CHICKEN_IDS[0]
	add_child_autofree(hen)
	await get_tree().process_frame
	hen._catch()
	await get_tree().create_timer(0.45).timeout
	var lbl := _catch_toast(hen)
	assert_not_null(lbl, "catching a hen must leave a line")
	assert_true(str(lbl.text).contains("1 / 7"), "the line must say how many are home")
	assert_false(hen._sprite.visible, "the hen itself still leaves")
	assert_true(hen.visible, "hiding the hen node is what hid the line")
	assert_true(lbl.is_visible_in_tree(),
		"the '(1 / 7)' line must still be on screen after the hen poofs")
	assert_gt(lbl.modulate.a, 0.5, "the line fades on its own timer, which has not started yet")


## The Rogue beat is one sentence wider than the old 192x18 toast, so it drew off the hen as a single line.
func test_a_long_catch_line_wraps_inside_its_box() -> void:
	_qs.accept(QUEST)
	var beat := str(_qs.get_quest(QUEST).get("rewards", {}).get("job_variants", {}).get("rogue", {}).get("dialogue_text", ""))
	assert_gt(beat.length(), 40, "control: the Rogue beat must still be authored")
	var hen = ChickenScript.new()
	hen.chicken_id = ChickenScript.ALL_CHICKEN_IDS[6]
	hen.catch_line = beat
	add_child_autofree(hen)
	await get_tree().process_frame
	hen._catch()
	var lbl := _catch_toast(hen)
	assert_not_null(lbl, "the Rogue beat must be toasted")
	assert_eq(lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	var font := lbl.get_theme_font("font")
	assert_not_null(font, "the toast must have a font or the wrap measurement says nothing")
	var fsz := lbl.get_theme_font_size("font_size")
	var single: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	assert_gt(single, lbl.size.x, "control: the beat is wider than the toast")
	var need: float = font.get_multiline_string_size(lbl.text, HORIZONTAL_ALIGNMENT_CENTER, lbl.size.x, fsz).y
	assert_gte(lbl.size.y, need - 0.5, "the toast must be tall enough for the wrapped beat")


func test_saved_roundup_count_is_zero_until_a_hen_is_caught() -> void:
	var obj := {"type": "custom", "required_flag": ChickenScript.ALL_CAUGHT_FLAG}
	assert_eq(ChickenScript.annotate_objective("Corner them.", obj), "[0/7] Corner them.")
	assert_eq(ChickenScript.annotate_objective("Ask Milo.", {"required_flag": "not_the_roundup"}), "Ask Milo.",
		"only the roundup objective grows a tally")
	assert_eq(ChickenScript.annotate_objective("Bring them home.", {"type": "talk", "required_flag": ChickenScript.ALL_CAUGHT_FLAG}),
		"Bring them home.", "the turn-in step shares the flag and is not the tally")


## Save/load keeps chicken_caught_* and drops the toast. The log and the HUD are what the player still has.
func test_quest_log_and_tracker_show_the_saved_catch_count() -> void:
	var prior_lp := QuestSystem.last_progressed_quest_id
	_qs.accept(QUEST)
	for i in range(3):
		GameState.set_story_flag("chicken_caught_" + ChickenScript.ALL_CHICKEN_IDS[i])
	var log := QuestLog.new()
	add_child_autofree(log)
	var text := ""
	for line in log._build_quest_lines():
		text += str(line.get("text", "")) + "\n"
	var count_at := text.find("[3/7]")
	var corner_at := text.find("Corner all seven")
	assert_gt(count_at, -1, "the quest log must show the saved 3/7")
	assert_gt(corner_at, count_at, "the count sits in front of the description so a clipped row keeps it")
	var host := Node.new()
	add_child_autofree(host)
	var tracker: Node = (load("res://src/exploration/QuestTracker.gd") as GDScript).new()
	host.add_child(tracker)
	tracker.setup(host)
	var hud := str(tracker._side_label.text)
	assert_true(hud.contains("[3/7]"), "the tracker must show the same saved count: %s" % hud)
	assert_lt(hud.find("[3/7]"), hud.find("Corner all seven"),
		"the HUD count must come before the long description")
	QuestSystem.last_progressed_quest_id = prior_lp


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
