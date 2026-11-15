extends GutTest

## The boss gloat prompt quotes one authored victory/defeat line as a voice sample and then says "Do NOT include the
## boss name or a speaker label". 30 of those lines are authored as "Name: 'text'", so the sample modelled the very
## label the rules forbid. The sample is now the spoken text only, the way the intent prompt quotes opening lines.

const POOLS: Array[String] = ["victory_lines", "defeat_lines"]


func _bm() -> Node:
	return get_tree().root.get_node("BattleManager")


## Every authored gloat line written with a speaker label, as [boss_id, pool, line, label].
func _tagged_lines() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_dialogue.json"))
	assert_true(parsed is Dictionary, "CONTROL: boss_dialogue.json parses")
	var out: Array = []
	for boss_id in (parsed as Dictionary):
		var entry: Variant = (parsed as Dictionary)[boss_id]
		if not (entry is Dictionary):
			continue
		for pool in POOLS:
			for l in (entry as Dictionary).get(pool, []):
				var line: String = str(l).strip_edges()
				var said: String = DialoguePrompts.spoken_line(line)
				if said != line:
					out.append([str(boss_id), pool, line, line.substr(0, line.length() - said.length() - 2)])
	return out


func test_the_rules_forbid_the_label_the_data_carries() -> void:
	var tagged: Array = _tagged_lines()
	assert_gt(tagged.size(), 10, "CONTROL: many authored gloat lines carry a speaker label")
	assert_string_contains(_bm()._build_gloat_prompt("glacius", "Glacius", true), "Do NOT include the boss name or a speaker label",
		"CONTROL: the rule this guard enforces is still in the prompt")


func test_no_sample_shows_its_speaker_label() -> void:
	var leaks: Array = []
	var checked: int = 0
	for row in _tagged_lines():
		var prompt: String = _bm()._build_gloat_prompt(row[0], "Boss", row[1] == "victory_lines", row[2])
		var said: String = DialoguePrompts.unrun_hyphens(DialoguePrompts.spoken_line(row[2]))
		checked += 1
		if prompt.contains(str(row[3])) or not prompt.contains("  %s\n" % said):
			leaks.append("%s.%s: %s" % [row[0], row[1], str(row[2]).left(50)])
	assert_gt(checked, 10, "CONTROL: every tagged line was built into a prompt")
	assert_eq(leaks, [], "a gloat sample must be the spoken words, never the 'Name: ...' label the rules forbid: %s" % str(leaks))


func test_an_untagged_sample_is_quoted_as_written() -> void:
	var sample := "You read every face and matched it. Pass."
	assert_string_contains(_bm()._build_gloat_prompt("glacius", "Glacius", true, sample), "  %s\n" % sample,
		"a line with no label reaches the prompt unchanged")
