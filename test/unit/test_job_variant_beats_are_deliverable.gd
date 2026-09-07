extends GutTest

## 16 authored per-job beats sat in quest data rendered by nothing. struktured ruled
## "wire / rewrite"; this pins that a wired beat names a point that actually exists.

const QUEST_DIR := "res://data/quests/"


func _quests() -> Array:
	var out: Array = []
	var d := DirAccess.open(QUEST_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUEST_DIR + f))
			if parsed is Dictionary:
				out.append([f.trim_suffix(".json"), parsed])
		f = d.get_next()
	d.list_dir_end()
	return out


## Every flag an examine point is actually placed with, from the village source.
func _placed_flags() -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("_add_quest_examine_point\\(\\s*\"[^\"]+\"\\s*,\\s*\"([^\"]+)\"")
	var d := DirAccess.open("res://src/maps/villages")
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string("res://src/maps/villages/" + f)
			for m in re.search_all(src):
				out[m.get_string(1)] = true
		f = d.get_next()
	d.list_dir_end()
	return out


## FLOOR. An empty walk on either side makes the ratchet below vacuous.
func test_control_both_corpora_resolve() -> void:
	var placed := _placed_flags()
	assert_gt(placed.size(), 5, "must find real examine-point placements, else every beat "
		+ "below looks undeliverable and the guard inverts")
	## A named-member control is only valid while that member exists: this originally named
	## Sandrift's flag and went red the moment that point was deleted for the Warden encounter.
	## Re-point it when a member goes, never weaken it to a count.
	assert_true(placed.has("quest_w1_frosthold_meltwater_clock_accepted"),
		"a KNOWN-placed flag must resolve — a count alone passes while the scan matches nothing")
	assert_false(placed.has("zzz_never_placed"), "an invented flag must NOT resolve")
	assert_gt(_quests().size(), 25, "quest walk must load the real corpus")


## Dialogue beats name a SITE, and that site must be a string some interactable passes to
## job_beat_at — otherwise the authored text is unreachable exactly like an unplaced point.
func test_every_dialogue_beat_names_a_live_site() -> void:
	var sites := {}
	var re := RegEx.create_from_string("job_beat_at\\(\\s*[A-Z_]+\\s*,\\s*\"([^\"]+)\"")
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			var p: String = dir + "/" + f
			if d.current_is_dir():
				stack.append(p)
			elif f.ends_with(".gd"):
				for m in re.search_all(FileAccess.get_file_as_string(p)):
					sites[m.get_string(1)] = true
			f = d.get_next()
		d.list_dir_end()

	## NPC-sited beats are delivered generically: run_completion_dialogue passes the
	## npc_id as the site, so ANY real npc_id is a live site without a literal call.
	## My first version modelled only literal calls, and its control was drawn from that
	## same corpus — so it passed while the generic path was invisible to it.
	var id_re := RegEx.create_from_string("\\w+\\.npc_id\\s*=\\s*\"([^\"]+)\"")
	var stack2: Array = ["res://src"]
	while not stack2.is_empty():
		var dir2: String = stack2.pop_back()
		var d2 := DirAccess.open(dir2)
		if d2 == null:
			continue
		d2.list_dir_begin()
		var f2 := d2.get_next()
		while f2 != "":
			var p2: String = dir2 + "/" + f2
			if d2.current_is_dir():
				stack2.append(p2)
			elif f2.ends_with(".gd"):
				for m in id_re.search_all(FileAccess.get_file_as_string(p2)):
					sites[m.get_string(1)] = true
			f2 = d2.get_next()
		d2.list_dir_end()

	assert_gt(sites.size(), 0, "must find job_beat_at call sites, else every dialogue beat "
		+ "below reads as unreachable and this inverts")
	assert_true(sites.has("rowan_harmonia"), "a KNOWN npc-sited target must resolve — this is "
		+ "the control the literal-only version lacked, and its absence is why that version "
		+ "reported a deliverable beat as unreachable")
	assert_true(sites.has("quest_chicken"), "a KNOWN-wired site must resolve — a count alone "
		+ "passes while the scan matches nothing")
	assert_false(sites.has("zzz_no_such_site"), "an invented site must NOT resolve")

	var wired := 0
	var unreachable: Array = []
	for pair in _quests():
		var variants = pair[1].get("rewards", {}).get("job_variants", {})
		if not (variants is Dictionary):
			continue
		for job in variants:
			var v = variants[job]
			if not (v is Dictionary) or str(v.get("dialogue_text", "")) == "":
				continue
			wired += 1
			var site: String = str(v.get("dialogue_at", ""))
			if site == "" or not sites.has(site):
				unreachable.append("%s [%s] -> %s" % [pair[0], job, site if site != "" else "(no dialogue_at)"])
	assert_gt(wired, 0, "must find wired dialogue beats, else vacuous")
	assert_eq(unreachable, [], "this beat names a site nothing asks job_beat_at for, so the "
		+ "authored text can never reach the player: %s" % [unreachable])


## THE RATCHET. A beat with examine_text must name a point that exists.
func test_every_wired_beat_names_a_real_examine_point() -> void:
	var placed := _placed_flags()
	var wired := 0
	var undeliverable: Array = []
	var missing_flag: Array = []
	for pair in _quests():
		var variants = pair[1].get("rewards", {}).get("job_variants", {})
		if not (variants is Dictionary):
			continue
		for job in variants:
			var v = variants[job]
			if not (v is Dictionary) or str(v.get("examine_text", "")) == "":
				continue
			wired += 1
			var f: String = str(v.get("examine_flag", ""))
			if f == "":
				missing_flag.append("%s [%s]" % [pair[0], job])
			elif not placed.has(f):
				undeliverable.append("%s [%s] -> %s" % [pair[0], job, f])

	assert_gt(wired, 0, "must find wired beats, else this guard is vacuous")
	assert_eq(missing_flag, [], "a beat with examine_text needs an examine_flag naming WHICH point "
		+ "shows it — without one a quest with several points renders its single job beat at "
		+ "whichever the player reached first: %s" % [missing_flag])
	assert_eq(undeliverable, [], "this beat names an examine point that is not placed in any "
		+ "village, so the authored text can never reach the player — the same defect as the "
		+ "8 emitters, one layer up: %s" % [undeliverable])


## The prose is DISPLAYED now, so it must not still be in authoring-spec form.
func test_wired_beats_are_display_prose_not_specs() -> void:
	var specs: Array = []
	var checked := 0
	for pair in _quests():
		var variants = pair[1].get("rewards", {}).get("job_variants", {})
		if not (variants is Dictionary):
			continue
		for job in variants:
			var v = variants[job]
			if not (v is Dictionary):
				continue
			## BOTH delivery fields — a dialogue beat is rendered just as verbatim as an
			## examine one, and checking only examine_text left half the corpus unguarded.
			var text: String = str(v.get("examine_text", "")) + " " + str(v.get("dialogue_text", ""))
			if text.strip_edges() == "":
				continue
			checked += 1
			## The two tells of the authoring form these were written in.
			if text.contains("examine text") or text.contains("No mechanical effect") \
					or text.contains("Dialogue-only"):
				specs.append("%s [%s]" % [pair[0], job])
	assert_gt(checked, 0, "must examine real wired beats, else vacuous")
	assert_eq(specs, [], "this text is still an authoring SPEC ('Rogue examine text at ...', "
		+ "'No mechanical effect') and is now rendered verbatim to the player. Rewrite it as "
		+ "prose: %s" % [specs])
