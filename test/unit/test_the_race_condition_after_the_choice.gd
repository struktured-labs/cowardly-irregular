extends GutTest
## 2026-11-27 (cowir-story): Mutual Exclusion's complete dialogue is the MERGED variant (the unison lines), and its _wiring_notes
## ask for a PROTOCOL variant "wired as dialogue branch on path flags"; the pair's idles also outlived the player's choice
## (story 28506). This authors both, keyed by the two path flags step 2's choices set, for the village to read on build
## (the NodePrimeVillage._attendant_lines shape). Data only: what reads it is overworld's.
const QUEST := "res://data/quests/world5_mutual_exclusion.json"


func _q() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(QUEST))


func _paths(q: Dictionary) -> Array:
	var out: Array = []
	for o in q.get("objectives", []):
		for c in o.get("choices", []):
			out.append(str(c.get("sets", "")))
	return out


func test_each_path_has_its_own_idles_after_the_choice() -> void:
	var q := _q()
	var paths := _paths(q)
	assert_eq(paths.size(), 2, "CONTROL: step 2's two choices were read")
	var idles: Dictionary = q.get("idle_after_resolved", {})
	assert_eq(idles.keys().size(), paths.size(), "one idle set per path, no stray key")
	for p in paths:
		var lines: Array = idles.get(p, [])
		assert_gt(lines.size(), 0, "%s has idles of its own" % p)
		for l in lines:
			assert_true(l is String and not str(l).strip_edges().is_empty(), "an idle is a plain line, as _create_npc takes")
			assert_false(str(l).contains("ever since"), "no idle still says they are reaching: '%s'" % l)
	assert_ne(idles.get(paths[0], []), idles.get(paths[1], []), "the two paths do not share their idles")


func test_the_protocol_path_ends_in_alternation_not_unison() -> void:
	var dlg: Dictionary = _q().get("dialogue", {})
	assert_gt((dlg.get("complete", []) as Array).size(), 0, "CONTROL: the merged completion is still there")
	var lines: Array = dlg.get("complete_protocol", [])
	assert_gt(lines.size(), 1, "the protocol path has its own completion")
	var last := ""
	for l in lines:
		var sp := str(l.get("speaker", ""))
		assert_true(sp == "Race Condition (First)" or sp == "Race Condition (Second)", "spoken by one of the two, never both: %s" % sp)
		assert_ne(sp, last, "they speak alternately, in schedule order")
		last = sp
