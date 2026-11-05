extends GutTest

## A pooled line is written before its battle and may play in ANY world, so it may name no one in it. Its forbidden
## list held every job only as its id in words ("cleric"), so a line written in world 3 that said "the Steamknight"
## played in world 1 too. Every job's name in every world is now refused: multi-word names anywhere, single-word ones
## (Faith, Voice, Edge are ordinary words too) only as a capitalised title mid-sentence. Names derive from the data.


## [a multi-word world job name, a single-word one], from the live table, whichever names it holds.
func _names() -> Array:
	var multi: String = ""
	var single: String = ""
	var per_job: Dictionary = (JobSystem.job_world_names as Dictionary).get("jobs", {})
	for j in per_job:
		for theme in per_job[j]:
			var n: String = str(per_job[j][theme])
			if j.replace("_", " ") == n.to_lower():
				continue
			if n.contains(" ") and multi == "":
				multi = n
			elif not n.contains(" ") and single == "":
				single = n
	return [multi, single]


func test_a_multi_word_world_job_is_refused() -> void:
	var multi: String = _names()[0]
	assert_ne(multi, "", "CONTROL: the table holds a multi-word world job name")
	if multi == "":
		return
	assert_true(VoicePoolStore.names_anyone("No way past the %s today!" % multi.to_lower(), VoicePool.forbidden_names()),
		"THE DEFECT: '%s' was not on the list, so a line naming it could play in a world where nobody is called that" % multi)


func test_a_single_word_world_job_is_refused_as_a_title() -> void:
	var single: String = _names()[1]
	assert_ne(single, "", "CONTROL: the table holds a single-word world job name that is not a base job")
	if single == "":
		return
	assert_true(VoicePool.forbidden_titles().has(single), "it is on the title list")
	assert_true(VoicePoolStore.names_a_title("Hold the line, the %s is down!" % single, VoicePool.forbidden_titles()),
		"capitalised mid-sentence it names someone, so the line is refused")


func test_the_same_word_as_a_plain_word_is_fine() -> void:
	var single: String = _names()[1]
	if single == "":
		return
	var titles: Array[String] = VoicePool.forbidden_titles()
	assert_false(VoicePoolStore.names_a_title("Hold the line, my %s will not break!" % single.to_lower(), titles),
		"lowercase it is an ordinary word, which a line in any world may use")
	assert_false(VoicePoolStore.names_a_title("%s carries us through." % single, titles),
		"and a capital that only opens the sentence is not a title")


func test_the_fill_refuses_on_both_lists() -> void:
	## SOURCE CHECK, named as one: the arms above drive the predicates; this pins that _fill asks both.
	var src: String = FileAccess.get_file_as_string("res://src/llm/VoicePool.gd")
	assert_string_contains(src, "VoicePoolStore.names_a_title(line, forbidden_titles())", "the fill consults the title list")
	assert_string_contains(src, "VoicePoolStore.names_anyone(line, forbidden_names())", "and still the name list")
