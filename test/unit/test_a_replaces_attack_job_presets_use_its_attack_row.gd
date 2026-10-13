extends GutTest

## A JOB WHOSE FREE MOVE *IS* ITS ATTACK ROW MUST NOT HAVE PRESETS THAT PICK A BASIC ATTACK.
##
## All three Bard presets ended on `IF [always] -> attack` while `bard.free_move` carries
## `replaces_attack: true` — so a manual Bard has NO Attack row at all and always gets Riff, while
## every preset chose the one action the menu cannot offer. Riff and a basic attack cost the same
## (nothing) and deal the same damage (1.0x); Riff adds a 70% blind. So the presets gave up a free
## rider on the turn they fire most.
##
## 🔑 That is CLAUDE.md's own invariant inverted — "the menu must never be able to do LESS than
## autobattle", recorded when the 2026-08-22 defect ran the other way (Mage/Cleric/Bard traded Attack
## for their free move and could not basic-attack from the menu at all). cowir-main ruled it PARITY
## rather than a buff: Riff IS the attack row by struktured's 08-22 ruling, so a preset picking a
## basic attack is drift from that ruling, not a design choice.
##
## ⛔ RELATIONAL, not a list of template ids (cowir-main's requirement). The subject is derived from
## `jobs.json` — any job whose free_move declares replaces_attack — so a SECOND such job added later
## is covered on the day its free move is authored, with nothing here to update. A list would have
## gone stale exactly the way the pin it replaces did.
##
## 📌 Blind is live in the grind: test_blind_does_something_in_a_grind fixed the headless miss roll to
## read it. The rider lands; the presets simply never produced it.

const TEMPLATES := "res://data/autobattle_rule_templates.json"
const JOBS := "res://data/jobs.json"


func _json(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if raw is Dictionary else {}


func _templates() -> Array:
	var d: Dictionary = _json(TEMPLATES)
	var t: Variant = d.get("templates", [])
	return t if t is Array else []


## Jobs whose free_move REPLACES the attack row — derived, never listed.
func _replaces_attack_jobs() -> Dictionary:
	var out: Dictionary = {}
	var jd: Dictionary = _json(JOBS)
	var jobs: Variant = jd.get("jobs", jd)
	if not (jobs is Dictionary):
		return out
	for jid in (jobs as Dictionary).keys():
		var v: Variant = (jobs as Dictionary)[jid]
		if not (v is Dictionary):
			continue
		var fm: Variant = (v as Dictionary).get("free_move", {})
		if fm is Dictionary and bool((fm as Dictionary).get("replaces_attack", false)):
			out[str(jid)] = str((fm as Dictionary).get("ability_id", ""))
	return out


## A bare basic attack: an action of type "attack" carrying no ability id.
func _basic_attacks_in(rules: Array) -> int:
	var n: int = 0
	for r in rules:
		if not (r is Dictionary):
			continue
		for a in ((r as Dictionary).get("actions", []) as Array):
			if a is Dictionary and str((a as Dictionary).get("type", "")) == "attack" \
					and str((a as Dictionary).get("id", "")) == "":
				n += 1
	return n


## CONTROL, must pass on BOTH trees: the derivation finds a subject and the catalog is readable.
## Without it the arm below is a loop over nothing, which is what a broken derivation looks like.
func test_control_the_derivation_finds_a_subject_and_a_catalog() -> void:
	var jobs: Dictionary = _replaces_attack_jobs()
	assert_gt(jobs.size(), 0,
		"at least one job must declare free_move.replaces_attack — else this guard watches nothing")
	assert_true(jobs.has("bard"), "bard is the shipped instance (struktured 2026-08-22)")
	assert_eq(str(jobs.get("bard", "")), "riff", "and its attack row is Riff")
	assert_gt(_templates().size(), 10, "the preset catalog must be readable: %d" % _templates().size())


## THE GUARD.
func test_a_replaces_attack_job_has_no_basic_attack_in_its_presets() -> void:
	var jobs: Dictionary = _replaces_attack_jobs()
	var offenders: Array[String] = []
	var checked: int = 0
	for t in _templates():
		if not (t is Dictionary):
			continue
		var jid: String = str((t as Dictionary).get("job_id", ""))
		if not jobs.has(jid):
			continue
		checked += 1
		var n: int = _basic_attacks_in((t as Dictionary).get("rules", []) as Array)
		if n > 0:
			offenders.append("%s has %d basic-attack action(s); %s's attack row is %s"
				% [str((t as Dictionary).get("id", "?")), n, jid, str(jobs[jid])])
	assert_gt(checked, 0, "CONTROL: at least one preset for such a job must have been examined")
	assert_eq(offenders, [] as Array[String],
		"a preset picked the basic attack for a job that HAS no attack row — the menu cannot do this, so the preset plays worse than manual: %s" % str(offenders))


## NEGATIVE control: a job WITHOUT replaces_attack may name the basic attack, and most do. If this
## ever reports zero the guard has over-broadened into every job's presets.
func test_control_a_normal_job_may_still_name_the_basic_attack() -> void:
	var jobs: Dictionary = _replaces_attack_jobs()
	var normal_with_attack: int = 0
	for t in _templates():
		if not (t is Dictionary):
			continue
		if jobs.has(str((t as Dictionary).get("job_id", ""))):
			continue
		if _basic_attacks_in((t as Dictionary).get("rules", []) as Array) > 0:
			normal_with_attack += 1
	assert_gt(normal_with_attack, 0,
		"jobs with a real Attack row must still be allowed to use it — zero here means this guard now forbids the basic attack everywhere")


## POSITIVE control on the detector: plant the exact shape and require a hit, so the empty offenders
## list above is a measurement rather than what a broken predicate returns.
func test_control_the_detector_flags_a_planted_basic_attack() -> void:
	var planted: Array = [{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true,
	}]
	assert_eq(_basic_attacks_in(planted), 1, "the detector must see a bare basic-attack action")
	var ability_form: Array = [{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "ability", "id": "riff", "target": "lowest_hp_enemy"}],
		"enabled": true,
	}]
	assert_eq(_basic_attacks_in(ability_form), 0, "and must NOT count the ability form as one")
