extends GutTest

## ally_alive/none_down hold in almost every fight; treated as moments they left the Fighter 2 turn_start lines of 10 and 1 low_hp line.

var _saved_rogue: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue


func _rogue_says(lines: Array) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["low_hp"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func _full_party(cleric_hp: float = 100.0) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Vex"
	for m in [["Vex", "rogue", 100.0], ["Mira", "cleric", cleric_hp], ["Brak", "fighter", 100.0]]:
		c.party.append({"name": m[0], "job_id": m[1], "hp_pct": m[2], "is_alive": true})
	c.enemies = [{"name": "Slime", "hp_pct": 100.0}]
	return c


func _texts(entries: Array) -> Array:
	return entries.map(func(e): return e["line"])


func test_a_precondition_that_holds_joins_the_pool_instead_of_replacing_it() -> void:
	_rogue_says(["G1.", "G2.", "G3.", {"line": "Cleric, now.", "when": "ally_alive:cleric"}])
	var got: Array = _texts(PartyPersonas.eligible_trigger_entries("rogue", "low_hp", _full_party()))
	assert_eq(got, ["G1.", "G2.", "G3.", "Cleric, now."], "ally_alive only says the line MAY play; it must compete evenly")


func test_none_down_and_all_full_are_preconditions_too() -> void:
	_rogue_says(["G1.", {"line": "Nobody fell.", "when": "none_down"}, {"line": "All topped up.", "when": "all_full"}])
	var got: Array = _texts(PartyPersonas.eligible_trigger_entries("rogue", "low_hp", _full_party()))
	assert_eq(got, ["G1.", "Nobody fell.", "All topped up."], "a party state is a precondition, not a moment")


func test_a_moment_that_holds_still_wins() -> void:
	_rogue_says(["G1.", "G2.", {"line": "Cleric's hurt. Cover her.", "when": "ally_low"}])
	var got: Array = _texts(PartyPersonas.eligible_trigger_entries("rogue", "low_hp", _full_party(20.0)))
	assert_eq(got, ["Cleric's hurt. Cover her."], "a line written for a rare moment outranks the generic ones")


func test_a_line_with_a_precondition_and_a_moment_counts_as_a_moment() -> void:
	_rogue_says(["G1.", {"line": "Mira, you're bleeding.", "when": ["ally_alive:cleric", "ally_low"]}])
	var got: Array = _texts(PartyPersonas.eligible_trigger_entries("rogue", "low_hp", _full_party(20.0)))
	assert_eq(got, ["Mira, you're bleeding."])


func test_all_full_needs_every_member_up_and_at_full_hp() -> void:
	assert_true(VoiceLineTags.tag_holds("all_full", _full_party()))
	assert_false(VoiceLineTags.tag_holds("all_full", _full_party(99.0)), "one member below full HP")
	var duel := PartyCombatLineContext.new()
	duel.speaker_name = "Vex"
	duel.party = [{"name": "Vex", "job_id": "rogue", "hp_pct": 100.0, "is_alive": true}]
	assert_false(VoiceLineTags.tag_holds("all_full", duel), "like none_down, a party of one has no 'all party members'")


func test_only_the_listed_tags_are_moments() -> void:
	for t in ["ally_alive:mage", "none_down", "all_full"]:
		assert_false(VoiceLineTags.is_moment_tag(t), "%s is a precondition" % t)
	for t in ["ally_down", "ally_low", "last_standing", "enemy_last", "enemy_nearly_dead", "many_enemies", "self_status"]:
		assert_true(VoiceLineTags.is_moment_tag(t), "%s is a moment" % t)
	assert_false(VoiceLineTags.is_moment_tag("typo_tag"), "an unknown tag is neither")


func test_in_an_ordinary_fight_no_trigger_shrinks_below_its_untagged_lines() -> void:
	## The shipped corpus, a full five-member party at full HP: the measured defect had 9 pairs below this floor.
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Speaker"
	for j in ["fighter", "cleric", "mage", "rogue", "bard"]:
		c.party.append({"name": j, "job_id": j, "hp_pct": 100.0, "is_alive": true})
	c.enemies = [{"name": "Goblin", "hp_pct": 100.0}, {"name": "Goblin B", "hp_pct": 100.0}]
	var checked := 0
	var tagged_pairs := 0
	var shrunk: Array[String] = []
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		c.speaker_name = job
		for trig in ["turn_start", "low_hp", "big_hit_taken", "used_signature_ability", "victory"]:
			var all_e: Array = PartyPersonas.get_trigger_entries(job, trig)
			var untagged: int = all_e.filter(func(e): return (e["tags"] as Array).is_empty()).size()
			if untagged < all_e.size():
				tagged_pairs += 1
			var n: int = PartyPersonas.eligible_trigger_entries(job, trig, c).size()
			checked += 1
			if n < untagged:
				shrunk.append("%s.%s %d < %d untagged" % [job, trig, n, untagged])
	gut.p("checked %d pairs, %d carry tags" % [checked, tagged_pairs])
	assert_eq(checked, 25, "VOID: the corpus walk did not reach every job x trigger")
	assert_gt(tagged_pairs, 0, "VOID: no pair carries a tag, so crowding-out cannot show here; guard a fixture instead")
	assert_eq(shrunk, [] as Array[String], "an ordinary fight must never lose its generic lines: %s" % [shrunk])
