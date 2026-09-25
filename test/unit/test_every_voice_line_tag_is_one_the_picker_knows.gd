extends GutTest

## An unknown tag makes its line ineligible forever, silently; a typo in the data must red here instead.


func test_every_tag_in_job_personas_is_known() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_personas.json"))
	assert_true(d is Dictionary and (d as Dictionary).has("jobs"), "job_personas.json did not parse")
	var entries := 0
	var tagged := 0
	var unknown: Array[String] = []
	for job in (d["jobs"] as Dictionary).keys():
		var tv: Variant = d["jobs"][job].get("trigger_voices", {})
		if not (tv is Dictionary):
			continue
		for trig in (tv as Dictionary).keys():
			var raw: Variant = tv[trig]
			for el in (raw if raw is Array else [raw]):
				entries += 1
				var tags: Array[String] = VoiceLines.tags_of(el)
				if not tags.is_empty():
					tagged += 1
				for t in tags:
					if not VoiceLineTags.is_known_tag(t):
						unknown.append("%s/%s: %s" % [job, trig, t])
	gut.p("corpus: %d entries, %d tagged" % [entries, tagged])
	assert_gt(entries, 0, "VOID: no trigger_voices entries were read, so nothing was checked")
	assert_eq(unknown, [] as Array[String], "unknown tags make their lines unplayable: %s" % [unknown])
