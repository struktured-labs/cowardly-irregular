extends GutTest

## A tagged line plays only when its condition is true; the solo duel is where an ally-naming line was wrong.


func _ctx(party: Array, enemies: Array = [{"name": "Slime", "hp_pct": 100.0}], status: Array = []) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Aria"
	c.speaker_job_id = "fighter"
	c.speaker_status = status
	c.party = party
	c.enemies = enemies
	return c


func _m(name: String, job: String, hp: float = 100.0, alive: bool = true) -> Dictionary:
	return {"name": name, "job_id": job, "hp_pct": hp, "is_alive": alive}


func test_a_solo_duel_has_no_cleric_to_call_on() -> void:
	var duel := _ctx([_m("Aria", "fighter")])
	assert_false(VoiceLineTags.tag_holds("ally_alive:cleric", duel),
		"in a spotlight duel the speaker is alone, so a line naming the Cleric must not play")
	assert_false(VoiceLineTags.is_eligible(["ally_alive:cleric"], duel))


func test_ally_alive_needs_the_ally_present_and_standing() -> void:
	var party := _ctx([_m("Aria", "fighter"), _m("Mira", "cleric")])
	assert_true(VoiceLineTags.tag_holds("ally_alive:cleric", party))
	var down := _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])
	assert_false(VoiceLineTags.tag_holds("ally_alive:cleric", down), "a KO'd Cleric can't answer")


func test_the_speaker_is_not_their_own_ally() -> void:
	var c := _ctx([_m("Aria", "fighter")])
	assert_false(VoiceLineTags.tag_holds("ally_alive:fighter", c),
		"the speaker's own job must not satisfy an ally tag")


func test_none_down_needs_a_party_and_nobody_down() -> void:
	assert_true(VoiceLineTags.tag_holds("none_down", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric")])))
	assert_false(VoiceLineTags.tag_holds("none_down", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])))
	assert_false(VoiceLineTags.tag_holds("none_down", _ctx([_m("Aria", "fighter")])),
		"'Nobody fell' is about a group; in a solo duel there is no group")


func test_the_remaining_tags() -> void:
	var two := [_m("Aria", "fighter"), _m("Mira", "cleric", 20.0)]
	assert_true(VoiceLineTags.tag_holds("ally_low", _ctx(two)))
	assert_false(VoiceLineTags.tag_holds("ally_down", _ctx(two)))
	assert_true(VoiceLineTags.tag_holds("ally_down", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])))
	assert_true(VoiceLineTags.tag_holds("last_standing", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])))
	assert_false(VoiceLineTags.tag_holds("last_standing", _ctx([_m("Aria", "fighter")])), "alone from the start is not last standing")
	assert_true(VoiceLineTags.tag_holds("enemy_last", _ctx(two, [{"name": "A", "hp_pct": 50.0}, {"name": "B", "hp_pct": 0.0}])))
	assert_true(VoiceLineTags.tag_holds("enemy_nearly_dead", _ctx(two, [{"name": "A", "hp_pct": 12.0}])))
	assert_false(VoiceLineTags.tag_holds("enemy_nearly_dead", _ctx(two, [{"name": "A", "hp_pct": 0.0}])), "a dead enemy is not nearly dead")
	assert_true(VoiceLineTags.tag_holds("many_enemies", _ctx(two, [{"name": "A", "hp_pct": 9.0}, {"name": "B", "hp_pct": 9.0}, {"name": "C", "hp_pct": 9.0}])))
	assert_true(VoiceLineTags.tag_holds("self_status", _ctx(two, [{"name": "A", "hp_pct": 50.0}], ["poison"])))


func test_every_tag_must_hold_and_an_unknown_one_never_does() -> void:
	var c := _ctx([_m("Aria", "fighter"), _m("Mira", "cleric")])
	assert_true(VoiceLineTags.is_eligible([], c), "an untagged line is always eligible")
	assert_true(VoiceLineTags.is_eligible(["ally_alive:cleric", "none_down"], c))
	assert_false(VoiceLineTags.is_eligible(["ally_alive:cleric", "ally_down"], c), "all tags must hold")
	assert_false(VoiceLineTags.is_known_tag("ally_dwon"), "a typo is not a tag")
	assert_false(VoiceLineTags.is_eligible(["ally_dwon"], c), "an unknown tag makes the line ineligible, never silently true")
	assert_true(VoiceLineTags.is_known_tag("ally_alive:bard"))
	assert_false(VoiceLineTags.is_known_tag("ally_alive:"), "a parameterised tag needs its parameter")
