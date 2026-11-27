extends GutTest
## 2026-11-27 (cowir-story): Mutual Exclusion's step 2 is a value choice whose _wiring_notes name two path flags (protocol / merged),
## but the step carried no authored text, so wiring had nothing to offer. It now authors `choices` in the shape
## QuestSystem._run_choice_emitter reads (label + sets + lines), one per path, so a CHOICE_EMITTERS entry is all wiring adds.
const QUEST := "res://data/quests/world5_mutual_exclusion.json"


func _step2() -> Dictionary:
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(QUEST))
	for o in q.get("objectives", []):
		if int(o.get("step", 0)) == 2:
			return o
	return {}


func test_each_path_named_in_the_notes_has_an_authored_answer() -> void:
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(QUEST))
	var notes := str(q.get("_wiring_notes", ""))
	var step := _step2()
	assert_eq(str(step.get("type", "")), "custom", "CONTROL: step 2 is the custom choice step")
	assert_eq(str(step.get("required_flag", "")), "quest_world5_mutual_exclusion_resolved", "CONTROL: it gates on _resolved")
	var sets: Array = []
	for c in step.get("choices", []):
		sets.append(str(c.get("sets", "")))
		assert_ne(str(c.get("label", "")).strip_edges(), "", "every answer has a label to pick")
		var lines: Array = c.get("lines", [])
		assert_gt(lines.size(), 0, "%s plays something" % c.get("sets", ""))
		for l in lines:
			assert_true(str(l.get("speaker", "")).begins_with("Race Condition ("), "spoken by the pair, as the giver note says: %s" % l.get("speaker", ""))
			assert_ne(str(l.get("text", "")).strip_edges(), "", "no empty line")
	for path in ["quest_world5_mutual_exclusion_protocol", "quest_world5_mutual_exclusion_merged"]:
		assert_true(notes.contains(path), "CONTROL: the notes name %s" % path)
		assert_has(sets, path, "an answer sets %s" % path)
	assert_eq(sets.size(), 2, "one answer per path, no more")


func test_the_shared_emitter_can_read_it() -> void:
	## The emitter offers only choices whose requires_item is held or absent; neither path is item-gated.
	for c in _step2().get("choices", []):
		assert_eq(str(c.get("requires_item", "")), "", "%s is open to any party" % c.get("sets", ""))
