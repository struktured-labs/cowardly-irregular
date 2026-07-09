extends GutTest

## Audit ratchet 2026-07-03: every ability id a job kit references —
## base list, starting_abilities, and the item-18 abilities_at_level
## ladder — must resolve in abilities.json. A typo here is the silent
## class: JobSystem's grant loop just skips unknown ids, so the player
## levels up and quietly never receives the spell.


func test_every_job_kit_ability_resolves() -> void:
	var jobs = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_true(jobs is Dictionary and abilities is Dictionary, "data files must parse")
	var dangling: Array = []
	for jid in jobs:
		var j = jobs[jid]
		if not (j is Dictionary):
			continue
		for a in j.get("abilities", []):
			if not abilities.has(str(a)):
				dangling.append("%s.abilities → %s" % [jid, a])
		for a in j.get("starting_abilities", []):
			if not abilities.has(str(a)):
				dangling.append("%s.starting → %s" % [jid, a])
		var ladder = j.get("abilities_at_level", {})
		if ladder is Dictionary:
			for lvl in ladder:
				for a in ladder[lvl]:
					if not abilities.has(str(a)):
						dangling.append("%s.lvl%s → %s" % [jid, lvl, a])
		# Free Move (per-job 0-AP command). ability-type free moves reference an
		# ability_id (Pray/Channel/Riff); basic_attack ones don't. A typo here
		# breaks the job's signature button silently — was unguarded before.
		var fm = j.get("free_move", {})
		if fm is Dictionary and str(fm.get("type", "")) == "ability":
			var fm_id = str(fm.get("ability_id", ""))
			if fm_id != "" and not abilities.has(fm_id):
				dangling.append("%s.free_move → %s" % [jid, fm_id])
	assert_eq(dangling.size(), 0,
		"job-kit ability ids that resolve NOWHERE (player levels up, spell never arrives): %s" % str(dangling))
