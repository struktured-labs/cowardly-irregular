extends GutTest

## Orrery-chain seam (ruling 2026-07-08, msgs 2299-2307): the worldN_orrery
## cutscenes advance fool_card_marks toward the W6 payoff but had NO trigger —
## the chain was unreachable. Quests now fire them via cutscene_on_complete.
## Contract pinned here:
##   1. cutscene-owns-items: a quest WITH cutscene_on_complete authors NO item
##      rewards and NO job_variants (gold/exp fine) — the cinematic is the
##      single grant source, so the seam can't double-grant
##   2. the target cutscene exists and parses
##   3. the quest's FINAL objective is talk-type (the flush fires from the
##      turn-in dialogue tail; a non-talk completion would strand the stash)
##   4. sequencing: _complete_quest only STASHES — play_cutscene is called
##      nowhere near it (firing mid-dialogue letterboxes over open NPCDialogue)
##   5. the original bug: the wired chain steps actually advance the marks

const QS_PATH := "res://src/quests/QuestSystem.gd"


func _quests_with_seam() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://data/quests")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + f))
		if typeof(q) == TYPE_DICTIONARY and str(q.get("cutscene_on_complete", "")) != "":
			out[f] = q
	return out


func test_seam_quests_author_no_item_rewards() -> void:
	var seam := _quests_with_seam()
	assert_gt(seam.size(), 1, "sanity: fools_spread + fine_print are wired")
	for f in seam:
		var rewards: Dictionary = seam[f].get("rewards", {})
		assert_eq(rewards.get("items", []).size(), 0,
			"%s has cutscene_on_complete — its cinematic owns item grants; quest items[] must be empty" % f)
		# dialogue-only variants (items: []) are legal — the rule guards GRANTS, not presentation (W5 long_way_around's Time Mage read)
		for job in rewards.get("job_variants", {}):
			assert_eq(rewards["job_variants"][job].get("items", []).size(), 0,
				"%s: variant '%s' authors ITEMS — grants live in the cutscene's lead_job branch" % [f, job])


func test_seam_targets_exist_and_final_objective_is_talk() -> void:
	for f in _quests_with_seam():
		var q: Dictionary = _quests_with_seam()[f]
		var cs := str(q.get("cutscene_on_complete"))
		var path := "res://data/cutscenes/%s.json" % cs
		assert_true(FileAccess.file_exists(path), "%s targets missing cutscene %s" % [f, cs])
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_eq(typeof(data), TYPE_DICTIONARY, "%s must parse" % path)
		var objectives: Array = q.get("objectives", [])
		assert_gt(objectives.size(), 0, "%s must have objectives" % f)
		assert_eq(str(objectives[-1].get("type", "")), "talk",
			"%s: cutscene_on_complete quests must END on a talk objective — the flush only fires from the dialogue tail" % f)


func test_complete_quest_stashes_but_never_plays_directly() -> void:
	var src := FileAccess.get_file_as_string(QS_PATH)
	var i := src.find("func _complete_quest")
	assert_gt(i, 0, "_complete_quest must exist")
	var block := src.substr(i, src.find("\nfunc ", i + 10) - i)
	assert_true("_pending_completion_cutscene" in block,
		"_complete_quest must stash the pending cutscene")
	assert_false("play_cutscene" in block,
		"_complete_quest must NEVER call play_cutscene directly — mid-dialogue fire letterboxes over open NPCDialogue (hazard msg 2302)")
	assert_true("_flush_completion_cutscene()" in src.substr(src.find("func run_giver_dialogue")),
		"the dialogue tails must flush the stash")


func test_orrery_chain_marks_actually_advance() -> void:
	# The dead-seam bug: fool_card_marks never moved. Pin the counter on all
	# five mark-granting worlds (W6 is the payoff — it spends, not grants).
	for pair in [["world1_orrery", 1], ["world2_orrery", 2], ["world3_orrery", 3], ["world4_orrery", 4], ["world5_orrery", 5]]:
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % pair[0]))
		var found := false
		var steps: Array = data.get("steps", [])
		for s in steps:
			if str(s.get("type", "")) == "set_flag" and str(s.get("flag", "")) == "fool_card_marks" and int(s.get("value", -1)) == int(pair[1]):
				found = true
		# lead_job branches nest steps — search those too
		for s in steps:
			for case_steps in s.get("cases", {}).values():
				for cs in case_steps:
					if str(cs.get("type", "")) == "set_flag" and str(cs.get("flag", "")) == "fool_card_marks" and int(cs.get("value", -1)) == int(pair[1]):
						found = true
		assert_true(found, "%s must set fool_card_marks=%d — that counter IS the chain" % [pair[0], pair[1]])


func test_five_marks_emitter_fires_at_threshold() -> void:
	# The finale (world6_last_appointment) gates prereq+spawn on the WIRING-OWNED
	# boolean quest_wiring_fool_card_five_marks. Marks are int-valued and land in
	# _step_set_flag, so the emitter lives there. Pin: 4 doesn't fire, 5 does.
	# CutsceneDirector is GameLoop-owned, not an autoload — a bare instance works (_step_set_flag only touches GameState)
	var director := CutsceneDirector.new()
	add_child_autofree(director)
	var had_bool: bool = GameState.story_flags.has("quest_wiring_fool_card_five_marks")
	var had_marks: bool = GameState.game_constants.has("cutscene_flag_fool_card_marks")
	GameState.story_flags.erase("quest_wiring_fool_card_five_marks")

	director._step_set_flag({"flag": "fool_card_marks", "value": 4})
	assert_false(GameState.get_story_flag("quest_wiring_fool_card_five_marks"),
		"marks=4 must NOT arm the finale gate")
	director._step_set_flag({"flag": "fool_card_marks", "value": 5})
	assert_true(GameState.get_story_flag("quest_wiring_fool_card_five_marks"),
		"marks=5 must emit quest_wiring_fool_card_five_marks — the chain finale is unreachable without it")

	GameState.story_flags.erase("fool_card_marks")
	if not had_bool:
		GameState.story_flags.erase("quest_wiring_fool_card_five_marks")
	if not had_marks:
		GameState.game_constants.erase("cutscene_flag_fool_card_marks")


func test_finale_quest_gates_on_the_emitted_boolean() -> void:
	var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/world6_last_appointment.json"))
	assert_eq(str(q.get("prereq_flag", "")), "quest_wiring_fool_card_five_marks",
		"finale prereq must match the emitter's flag name exactly")
	assert_eq(str(q.get("giver", {}).get("spawn_flag", "")), "quest_wiring_fool_card_five_marks",
		"finale giver spawn must match the emitter's flag name exactly")


func test_fools_spread_wired_to_world1_orrery() -> void:
	var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/world1_fools_spread.json"))
	assert_eq(str(q.get("cutscene_on_complete", "")), "world1_orrery",
		"fools_spread is the chain's W1 entry — must fire world1_orrery at turn-in")
	var s := FileAccess.get_file_as_string("res://data/cutscenes/world1_orrery.json")
	assert_true("unwritten_chord" in s and "fool_card" in s,
		"world1_orrery must carry the grants incl. the Bard branch (story commit 7ecce261)")
