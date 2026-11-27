extends GutTest

## Mutual Exclusion's answer set a path flag nothing read: the pair kept saying "reaching ever since" and every ending was the merged one.
## Now the schedule earns complete_protocol and its own idles; the merge keeps complete and gets its own idles.

const QID := "world5_mutual_exclusion"
const NPC_ID := "race_condition_pair"
const CH2 := "cutscene_flag_world5_chapter2_complete"
const PROTOCOL := "quest_world5_mutual_exclusion_protocol"
const MERGED := "quest_world5_mutual_exclusion_merged"

var _qs: Node
var _dlg: Dictionary = {}
var _held: Dictionary = {}


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_dlg = _qs.get_quest(QID).get("dialogue", {})
	_held = {"story": GameState.story_flags.duplicate(true), "consts": GameState.game_constants.duplicate(true)}
	for f in [PROTOCOL, MERGED]:
		GameState.story_flags.erase(f)


func after_each() -> void:
	if _held.has("quest"):
		_restore_turn_in()
	GameState.story_flags = _held["story"]
	GameState.game_constants = _held["consts"]


func _first_text(lines: Array) -> String:
	return "" if lines.is_empty() else str(lines[0].get("text", ""))


func _pair_in_node_prime() -> Node:
	GameState.game_constants[CH2] = true
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v: Node = load("res://src/maps/villages/NodePrimeVillage.gd").new()
	vp.add_child(v)
	await get_tree().process_frame
	for n in v.npcs.get_children():
		if n.has_method("get_npc_id") and n.get_npc_id() == NPC_ID:
			return n
	return null


func test_the_schedule_ends_on_the_protocol_lines() -> void:
	assert_false((_dlg.get("complete_protocol", []) as Array).is_empty(), "CONTROL: story authored a protocol ending")
	assert_ne(_first_text(_dlg["complete_protocol"]), _first_text(_dlg["complete"]), "CONTROL: the two endings differ")
	GameState.set_story_flag(PROTOCOL, true)
	assert_eq(_qs.completion_lines(QID), _dlg["complete_protocol"], "a party that wrote them a schedule hears the protocol ending")


func test_the_merge_and_no_answer_end_on_the_unison_lines() -> void:
	assert_eq(_qs.completion_lines(QID), _dlg["complete"], "with no path flag the authored complete plays")
	GameState.set_story_flag(MERGED, true)
	assert_eq(_qs.completion_lines(QID), _dlg["complete"], "the merge keeps the unison ending")


func test_a_quest_without_path_endings_is_unchanged() -> void:
	var other: Dictionary = _qs.get_quest("world5_termination_condition").get("dialogue", {})
	assert_false(other.is_empty(), "CONTROL: another quest with dialogue exists")
	assert_eq(_qs.completion_lines("world5_termination_condition"), other.get("complete", []), "its complete plays as before")


func test_both_turn_in_paths_read_the_path_ending() -> void:
	var src := FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	assert_eq(src.count("await _play_lines(npc, completion_lines("), 2, "the giver turn-in and run_completion_dialogue both play the path's ending")
	assert_eq(src.count("_play_lines(npc, dlg.get(\"complete\""), 0, "no turn-in path plays the bare complete past the helper")


func test_before_any_answer_the_pair_are_still_reaching() -> void:
	var pair: Node = await _pair_in_node_prime()
	assert_not_null(pair, "CONTROL: the pair stand in Node Prime after chapter 2")
	if pair != null:
		assert_true(" ".join(PackedStringArray(pair.dialogue_lines)).contains("reaching"), "before the choice they are still reaching")


func test_after_the_schedule_the_pair_take_turns() -> void:
	var pair: Node = await _pair_in_node_prime()
	assert_not_null(pair, "CONTROL: the pair stand in Node Prime")
	if pair == null:
		return
	GameState.set_story_flag(PROTOCOL, true)
	_qs.objective_advanced.emit(QID, 2)
	var idles: Array = _qs.get_quest(QID)["idle_after_resolved"][PROTOCOL]
	assert_eq(pair.dialogue_lines, idles, "the answer reaches the pair the moment the quest moves, not on the next visit")
	assert_false(" ".join(PackedStringArray(pair.dialogue_lines)).contains("ever since"), "nothing left of the reaching")


func test_after_the_merge_a_fresh_village_has_one_voice() -> void:
	GameState.set_story_flag(MERGED, true)
	var pair: Node = await _pair_in_node_prime()
	assert_not_null(pair, "CONTROL: the pair stand in Node Prime")
	if pair != null:
		assert_eq(pair.dialogue_lines, _qs.get_quest(QID)["idle_after_resolved"][MERGED], "a later visit builds them merged")


## The real quest at its last step with rewards stripped, so a turn-in plays its lines and grants nothing.
func _arm_turn_in() -> Node2D:
	var q: Dictionary = (_qs.get_quest(QID) as Dictionary).duplicate(true)
	q["rewards"] = {}
	_held["quest"] = _qs.get_quest(QID).duplicate(true)
	_held["state"] = GameState.quests.get(QID, null)
	_qs._quests[QID] = q
	GameState.quests[QID] = {"state": "active", "objective_index": 2}
	GameState.set_story_flag("quest_world5_mutual_exclusion_resolved", true)
	GameState.set_story_flag(PROTOCOL, true)
	var npc := Node2D.new()
	npc.set("npc_name", "The Race Condition")
	add_child_autofree(npc)
	return npc


func _restore_turn_in() -> void:
	_qs._quests[QID] = _held["quest"]
	if _held["state"] == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = _held["state"]


## Every line any dialogue under the npc queued, advancing each so the turn-in runs to its end.
func _heard(npc: Node) -> String:
	var seen: Array = []
	var idle := 0
	for _i in range(40):
		await get_tree().process_frame
		var n := 0
		for node in npc.find_children("*", "", true, false):
			if not node.has_method("skip_all") or not ("_dialogue_queue" in node):
				continue
			for line in node._dialogue_queue:
				var t := str((line as Dictionary).get("text", "")) if line is Dictionary else ""
				if t != "" and not seen.has(t):
					seen.append(t)
					n += 1
			node.skip_all()
		idle = idle + 1 if n == 0 else 0
		if idle >= 6 and not seen.is_empty():
			break
	return "\n".join(seen)


func test_the_giver_turn_in_plays_the_schedule_ending() -> void:
	var npc := _arm_turn_in()
	var protocol_line := _first_text(_dlg["complete_protocol"])
	_qs.run_giver_dialogue(NPC_ID, npc)
	var heard: String = await _heard(npc)
	assert_eq(_qs.get_state(QID), "complete", "CONTROL: talking to the pair at step 3 turns the quest in")
	assert_true(heard.contains(protocol_line), "the pair's own turn-in plays complete_protocol: %s" % heard)
	assert_false(heard.contains(_first_text(_dlg["complete"])), "and not the unison ending")


func test_run_completion_dialogue_plays_the_schedule_ending() -> void:
	var npc := _arm_turn_in()
	_qs.run_completion_dialogue(QID, npc)
	var heard: String = await _heard(npc)
	assert_true(heard.contains(_first_text(_dlg["complete_protocol"])), "the non-giver turn-in plays complete_protocol too: %s" % heard)
	assert_false(heard.contains(_first_text(_dlg["complete"])), "and not the unison ending")
