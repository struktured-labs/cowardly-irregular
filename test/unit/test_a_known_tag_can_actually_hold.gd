extends GutTest

## A tag added to VoiceLineTags.SIMPLE_TAGS with no arm in `tag_holds`'s match passes every
## authoring check and silently mutes every line carrying it. MEASURED 2026-10-12 by planting a
## tenth tag in the const and running the real evaluator:
##
##   is_known_tag("zz_planted")    true     <- test_every_voice_line_tag_is_one_the_picker_knows PASSES
##   is_moment_tag("zz_planted")   true     <- it would even OUTRANK a ready pooled line
##   tag_holds(...)                false    in every context tried
##   is_eligible(["zz_planted"])   false    -> the line can never be spoken, and nothing says so
##
## 🔑 THE DOMAIN-GROWTH CLASS, ANSWERED AT RUNTIME. Four lanes spent today on this shape — a producer
## gains a member and the consumer has no branch for it — and concluded a static `produced ⊆ consumed`
## is the only instrument, because the members are ARGUMENTS INSIDE A FUNCTION BODY and a new one does
## not exist until someone edits the producer. Here the producer is a READABLE CONST and the consumer
## is a CALLABLE PREDICATE, so the relation is testable by calling it: a branchless tag holds in NO
## context, and that is a runtime fact. No literal is extracted from source, so @cowir-deploy's
## unbounded-quote hazard cannot apply, and this needs no liveness partner — it IS the liveness arm.
##
## ⚠️ THE BURDEN THIS PUTS ON THE NEXT TAG IS THE POINT: a new tag must come with a context that makes
## it true. If none can be written, the tag is unreachable and the lines written for it are mute.

const TAGS := preload("res://src/llm/VoiceLineTags.gd")


func _ctx(party: Array, enemies: Array, status: Array = []) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Brom"
	c.party = party
	c.enemies = enemies
	c.speaker_status = status
	return c


func _m(who: String, job: String, hp: float = 100.0, alive: bool = true) -> Dictionary:
	return {"name": who, "job_id": job, "hp_pct": hp, "is_alive": alive}


func _e(who: String, hp: float = 100.0) -> Dictionary:
	return {"name": who, "hp_pct": hp}


## The outcome tags read event_data, which only a victory line carries — so they need their own situations.
func _ectx(data: Dictionary) -> PartyCombatLineContext:
	var c: PartyCombatLineContext = _ctx([_m("Brom", "fighter"), _m("Mira", "cleric")], [_e("Slime")])
	c.event_kind = PartyCombatLineContext.EVENT_VICTORY
	c.event_data = data
	return c


## The situations the evaluator is written about. A tag that holds in none of them holds in none that
## a battle can produce — and any new tag owes this table an entry.
func _situations() -> Dictionary:
	var me: Dictionary = _m("Brom", "fighter")
	var one_foe: Array = [_e("Slime")]
	var two_foes: Array = [_e("Slime"), _e("Rat")]
	return {
		"a whole party, nobody hurt": _ctx([me, _m("Mira", "cleric")], two_foes),
		"an ally down, another standing": _ctx([me, _m("Mira", "cleric", 0.0, false), _m("Zeph", "mage")], two_foes),
		"an ally badly hurt": _ctx([me, _m("Mira", "cleric", 10.0)], two_foes),
		"the last one standing": _ctx([me, _m("Mira", "cleric", 0.0, false)], two_foes),
		"one enemy left": _ctx([me, _m("Mira", "cleric")], one_foe),
		"an enemy nearly dead": _ctx([me, _m("Mira", "cleric")], [_e("Slime", 5.0), _e("Rat")]),
		"outnumbered": _ctx([me, _m("Mira", "cleric")], [_e("Slime"), _e("Rat"), _e("Bat")]),
		"the speaker is poisoned": _ctx([me, _m("Mira", "cleric")], two_foes, ["poison"]),
		"a cleric is alive beside me": _ctx([me, _m("Mira", "cleric")], two_foes),
		"the speaker levelled on this win": _ectx({PartyCombatLineContext.VICTORY_SELF_LEVELED: true}),
		"the speaker learned an ability": _ectx({PartyCombatLineContext.VICTORY_SELF_LEARNED: true}),
		"a long grind of a fight": _ectx({PartyCombatLineContext.VICTORY_ROUNDS: TAGS.LONG_FIGHT_ROUNDS}),
		"the field wiped in one strike": _ectx({PartyCombatLineContext.VICTORY_ONE_SHOT: true}),
	}


func _simple_tags() -> Array:
	return TAGS.SIMPLE_TAGS


func test_the_corpora_are_real() -> void:
	## An empty tag list or an empty situation table passes every arm below for the wrong reason.
	assert_gt(_simple_tags().size(), 5, "CONTROL: SIMPLE_TAGS has only %d entries" % _simple_tags().size())
	assert_gt(_situations().size(), 5, "CONTROL: the situation table has only %d entries" % _situations().size())


func test_every_known_tag_can_hold_in_some_situation() -> void:
	## ⛔ THE ARM. A tag no battle can satisfy is a tag whose lines are mute, and nothing else notices:
	## the authoring guards check the tag is KNOWN, and a known tag with no branch is known.
	var mute: Array[String] = []
	for tag in _simple_tags():
		var held := false
		for label in _situations():
			if TAGS.tag_holds(str(tag), _situations()[label]):
				held = true
				break
		if not held:
			mute.append(str(tag))
	assert_eq(mute, ([] as Array[String]),
		"these tags hold in no situation a battle can produce, so every line carrying one is unspeakable — give the tag an arm in tag_holds, or this file a situation that makes it true: %s" % [mute])


func test_an_ally_alive_tag_can_hold_for_every_job_a_line_may_name() -> void:
	## `ally_alive:<job>` is matched against a party member's job_id DIRECTLY, so it does not resolve
	## aliases: `ally_alive:white_mage` is "known", never holds, and mutes its line. The three aliases
	## in data/job_aliases.json are exactly the ids a writer is most likely to reach for.
	var aliases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_aliases.json"))
	assert_true(aliases is Dictionary, "CONTROL: the alias table must parse")
	var me: Dictionary = _m("Brom", "fighter")
	for old_id in (aliases as Dictionary):
		var new_id: String = str((aliases as Dictionary)[old_id])
		var ctx: PartyCombatLineContext = _ctx([me, _m("Ally", new_id)], [_e("Slime")])
		assert_true(TAGS.tag_holds("ally_alive:%s" % new_id, ctx),
			"CONTROL: ally_alive:%s must hold when that job is standing" % new_id)
		assert_false(TAGS.tag_holds("ally_alive:%s" % old_id, ctx),
			"ally_alive:%s resolves the alias now; if that changed deliberately, the authored tags may use either id" % old_id)


func test_an_old_saves_cleric_still_answers_ally_alive_cleric() -> void:
	## THE PROPERTY THAT MAKES CANONICAL IDS THE RIGHT THING TO AUTHOR. `tag_holds` compares the tag's
	## job to a party member's job_id with no alias map, so if a save from before the rename could put
	## `white_mage` on the wire, all 15 authored ally_alive tags would be mute for that player — and
	## nothing would say so. It cannot: JobSystem.assign_job calls resolve_job_id BEFORE the lookup
	## (JobSystem:494) and assigns the canonical job dict, so `_resolve_party_job_id` only ever sees
	## the new id. Driven through the production path rather than asserted from reading it, because
	## removing that one line would mute the lines silently for exactly the players with old saves.
	var aliases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_aliases.json"))
	assert_true(aliases is Dictionary and not (aliases as Dictionary).is_empty(), "CONTROL: the alias table must parse and be non-empty")
	for old_id in (aliases as Dictionary):
		var new_id: String = str((aliases as Dictionary)[old_id])
		var ally := Combatant.new()
		autofree(ally)
		ally.combatant_name = "Saved Ally"
		assert_true(JobSystem.assign_job(ally, str(old_id)),
			"CONTROL: assign_job must accept the retired id %s, or an old save cannot load at all" % old_id)
		assert_eq(str((ally.job as Dictionary).get("id", "")), new_id,
			"assign_job left the retired id %s on the combatant, so every ally_alive:%s line goes mute for old saves" % [old_id, new_id])
		var me := Combatant.new()
		autofree(me)
		me.combatant_name = "Brom"
		JobSystem.assign_job(me, "fighter")
		var ctx := PartyCombatLineContext.new()
		ctx.speaker_name = "Brom"
		ctx.party = [_m("Brom", str((me.job as Dictionary).get("id", ""))),
			_m("Saved Ally", str((ally.job as Dictionary).get("id", "")))]
		ctx.enemies = [_e("Slime")]
		assert_true(TAGS.tag_holds("ally_alive:%s" % new_id, ctx),
			"an ally loaded from a save that called them %s does not answer ally_alive:%s" % [old_id, new_id])


func test_no_authored_ally_alive_tag_names_a_job_that_cannot_answer() -> void:
	## The content half: a tag naming a retired or misspelled job is accepted by every other guard and
	## never holds. 15 such tags are authored today and all name a live job.
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_true(jobs is Dictionary, "CONTROL: jobs.json must parse")
	## jobs.json is keyed BY job id at the top level — no "jobs" wrapper. The control below exists
	## because my first version read a wrapper that is not there, got zero jobs, and every authored
	## tag looked dead: an empty corpus makes this arm's verdict the opposite of the truth.
	var live: Array[String] = []
	for key in (jobs as Dictionary):
		live.append(str(key))
	assert_gt(live.size(), 4, "CONTROL: only %d jobs read from jobs.json" % live.size())
	for expected in ["fighter", "cleric", "mage", "rogue", "bard"]:
		assert_true(live.has(expected), "CONTROL: %s must be a live job id" % expected)
	var checked := 0
	var dead: Array[String] = []
	for job_id in PartyPersonas._data:
		var entry: Dictionary = PartyPersonas._data[job_id]
		for trigger in (entry.get("trigger_voices", {}) as Dictionary):
			for e in PartyPersonas.get_trigger_entries(str(job_id), str(trigger)):
				for t in (e.get("tags", []) as Array):
					if not str(t).begins_with(TAGS.ALLY_ALIVE_PREFIX):
						continue
					checked += 1
					var named: String = str(t).substr(TAGS.ALLY_ALIVE_PREFIX.length())
					if not live.has(named):
						dead.append("%s/%s names %s" % [job_id, trigger, named])
	assert_gt(checked, 10, "CONTROL: only %d ally_alive tags found to check" % checked)
	assert_eq(dead, ([] as Array[String]), "an ally_alive tag naming a job that cannot answer mutes its line: %s" % [dead])
