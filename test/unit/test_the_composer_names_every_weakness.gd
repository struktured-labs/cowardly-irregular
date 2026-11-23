extends GutTest

## The Rule Composer's grammar told the model which elements are worth an `enemy_weak_to` rule, with COUNTS typed in:
## "fire (38 of 106 monsters), holy (32), lightning (30), ice (27)". On 2026-11-12 monsters.json held 109 monsters and
## 39 / 33 / 31 / 28. The counts are gone; what the sentence still claims is derived here from the data it describes.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const MONSTERS := "res://data/monsters.json"


## element -> how many monsters carry it as a weakness.
func _weakness_counts() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	var out: Dictionary = {}
	if not (parsed is Dictionary):
		return out
	for id in parsed:
		var m: Variant = parsed[id]
		if not (m is Dictionary):
			continue
		var weak: Variant = (m as Dictionary).get("weaknesses", [])
		if weak is Array:
			for w in (weak as Array):
				out[str(w)] = int(out.get(str(w), 0)) + 1
	return out


## The grammar's own sentence about weakness elements, from "bestiary:" to "Pair it".
func _sentence() -> String:
	var g: String = DP.AUTOBATTLE_GRAMMAR_DESCRIPTION
	var from: int = g.find("appear as a weakness in the")
	var to: int = g.find("Pair it with an ability", from)
	return g.substr(from, to - from) if from != -1 and to > from else ""


func test_the_grammar_names_every_element_a_monster_is_weak_to() -> void:
	var counts: Dictionary = _weakness_counts()
	var sentence: String = _sentence()
	assert_gt(counts.size(), 3, "CONTROL: the bestiary carries weaknesses")
	assert_ne(sentence, "", "CONTROL: the grammar has its sentence about weakness elements")
	var missing: Array = []
	for element in counts:
		if not sentence.contains(str(element)):
			missing.append(str(element))
	assert_eq(missing, [], "a monster is weak to these and the composer is never told they exist")


func test_the_four_it_calls_commonest_are() -> void:
	var counts: Dictionary = _weakness_counts()
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	assert_gt(ranked.size(), 4, "CONTROL: more than four elements appear, so 'the four most' says something")
	if ranked.size() <= 4:
		return
	assert_gt(int(counts[ranked[3]]), int(counts[ranked[4]]), "CONTROL: the fourth is ahead of the fifth, so the top four are a set")
	var sentence: String = _sentence()
	var cut: int = sentence.find("(the four most")
	assert_gt(cut, 0, "CONTROL: the sentence makes the 'four most' claim")
	var named_first: String = sentence.substr(0, cut)
	for i in range(4):
		assert_string_contains(named_first, str(ranked[i]), "one of the four commonest weaknesses is not among the four it names")
	for i in range(4, ranked.size()):
		assert_false(named_first.contains(str(ranked[i])), "%s is named among the four commonest and is not one" % ranked[i])


func test_it_states_no_count_that_can_go_stale() -> void:
	var sentence: String = _sentence()
	var rx := RegEx.new()
	rx.compile("[0-9]")
	assert_null(rx.search(sentence), "the sentence types a number about the bestiary; it drifted once (38 of 106 → 39 of 109)")
	assert_not_null(rx.search("fire (38 of 106 monsters)"), "CONTROL: the same search finds a digit in the old sentence")
